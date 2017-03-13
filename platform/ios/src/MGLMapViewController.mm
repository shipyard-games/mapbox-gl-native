//
//  MGLMapViewController.m
//  ios
//
//  Created by Teemu Harju on 08/03/2017.
//  Copyright © 2017 Mapbox. All rights reserved.
//

#import <Foundation/Foundation.h>

#include <mbgl/platform/log.hpp>
#include <mbgl/gl/extension.hpp>
#include <mbgl/gl/context.hpp>

#import <GLKit/GLKit.h>

#import "MGLMapViewController.h"

#import <OpenGLES/EAGL.h>
#import <SceneKit/SceneKit.h>

#include <mbgl/mbgl.hpp>
#include <mbgl/platform/default/thread_pool.hpp>
#include <mbgl/storage/default_file_source.hpp>
#include <mbgl/map/backend.hpp>
#include <mbgl/map/mode.hpp>
#include <mbgl/map/camera.hpp>
#include <mbgl/util/geo.hpp>

#import "MGLOfflineStorage_Private.h"
#import "MGLGeometry_Private.h"
#import "MGLMapboxEvents.h"
#import "NSDate+MGLAdditions.h"

class MBGLControllerView;

void MGLinitializeRunLoop();

const CGFloat MGLMapViewDecelerationRateNormal = UIScrollViewDecelerationRateNormal;
const CGFloat MGLMapViewDecelerationRateFast = UIScrollViewDecelerationRateFast;
const CGFloat MGLMapViewDecelerationRateImmediate = 0.0;

@interface MGLMapViewController() <UIGestureRecognizerDelegate>
@property (nonatomic) UIPanGestureRecognizer *pan;
@property (nonatomic) double zoomLevel;
@end

@implementation MGLMapViewController

NSTimeInterval timeSinceLastMapUpdate = 0.0;
MBGLControllerView *_mbglView;
mbgl::Map *_mbglMap;
mbgl::ThreadPool *_mbglThreadPool;

NSUInteger _changeDelimiterSuppressionDepth;

SCNNode *_sceneCameraNode;

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    
    GLKView *view = (GLKView *)self.view;
    view.context = _context;
    view.backgroundColor = [UIColor whiteColor];
    view.drawableStencilFormat = GLKViewDrawableStencilFormat8;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat16;
    
    self.preferredFramesPerSecond = 60;
    
    // load extensions
    //
    mbgl::gl::InitializeExtensions([](const char * name) {
        static CFBundleRef framework = CFBundleGetBundleWithIdentifier(CFSTR("com.apple.opengles"));
        if (!framework) {
            throw std::runtime_error("Failed to load OpenGL framework.");
        }
        
        CFStringRef str = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII);
        void* symbol = CFBundleGetFunctionPointerForName(framework, str);
        CFRelease(str);
        
        return reinterpret_cast<mbgl::gl::glProc>(symbol);
    });
    
    [self commonInit];
    
    _pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
    _pan.delegate = self;
    _pan.maximumNumberOfTouches = 1;
    [self.view addGestureRecognizer:_pan];
    
    _decelerationRate = MGLMapViewDecelerationRateNormal;
}

- (void)viewDidUnload
{

}

- (void)handlePanGesture:(UIPanGestureRecognizer *)pan
{
    _mbglMap->cancelTransitions();
    
    if (pan.state == UIGestureRecognizerStateBegan)
    {
        [self trackGestureEvent:MGLEventGesturePanStart forRecognizer:pan];
        
        self.userTrackingMode = MGLUserTrackingModeNone;
        
        [self notifyGestureDidBegin];
    }
    else if (pan.state == UIGestureRecognizerStateChanged)
    {
        CGPoint delta = [pan translationInView:pan.view];
        _mbglMap->moveBy({ delta.x, delta.y });
        [pan setTranslation:CGPointZero inView:pan.view];
        
        [self notifyMapChange:mbgl::MapChangeRegionIsChanging];
    }
    else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled)
    {
        CGPoint velocity = [pan velocityInView:pan.view];
        if (self.decelerationRate == MGLMapViewDecelerationRateImmediate || sqrtf(velocity.x * velocity.x + velocity.y * velocity.y) < 100)
        {
            // Not enough velocity to overcome friction
            velocity = CGPointZero;
        }
        
        BOOL drift = ! CGPointEqualToPoint(velocity, CGPointZero);
        if (drift)
        {
            CGPoint offset = CGPointMake(velocity.x * self.decelerationRate / 4, velocity.y * self.decelerationRate / 4);
            _mbglMap->moveBy({ offset.x, offset.y }, MGLDurationInSeconds(self.decelerationRate));
        }
        
        [self notifyGestureDidEndWithDrift:drift];
        
        // metrics: pan end
        CGPoint pointInView = CGPointMake([pan locationInView:pan.view].x, [pan locationInView:pan.view].y);
        CLLocationCoordinate2D panCoordinate = [self convertPoint:pointInView toCoordinateFromView:pan.view];
        int zoom = round([self zoomLevel]);
        
        [MGLMapboxEvents pushEvent:MGLEventTypeMapDragEnd withAttributes:@{
                                                                           MGLEventKeyLatitude: @(panCoordinate.latitude),
                                                                           MGLEventKeyLongitude: @(panCoordinate.longitude),
                                                                           MGLEventKeyZoomLevel: @(zoom)
                                                                           }];
    }
}

- (void)trackGestureEvent:(NSString *)gestureID forRecognizer:(UIGestureRecognizer *)recognizer
{
    CGPoint pointInView = CGPointMake([recognizer locationInView:recognizer.view].x, [recognizer locationInView:recognizer.view].y);
    CLLocationCoordinate2D gestureCoordinate = [self convertPoint:pointInView toCoordinateFromView:recognizer.view];
    int zoom = round([self zoomLevel]);
    
    [MGLMapboxEvents pushEvent:MGLEventTypeMapTap withAttributes:@{
                                                                   MGLEventKeyLatitude: @(gestureCoordinate.latitude),
                                                                   MGLEventKeyLongitude: @(gestureCoordinate.longitude),
                                                                   MGLEventKeyZoomLevel: @(zoom),
                                                                   MGLEventKeyGestureID: gestureID
                                                                   }];
}

- (void)notifyGestureDidBegin {
    [self notifyMapChange:mbgl::MapChangeRegionWillChange];
    _mbglMap->setGestureInProgress(true);
    _changeDelimiterSuppressionDepth++;
}

- (void)notifyGestureDidEndWithDrift:(BOOL)drift {
    _changeDelimiterSuppressionDepth--;
    NSAssert(_changeDelimiterSuppressionDepth >= 0,
             @"Unbalanced change delimiter suppression/unsuppression");
    if (_changeDelimiterSuppressionDepth == 0) {
        _mbglMap->setGestureInProgress(false);
    }
    if ( ! drift)
    {
        [self notifyMapChange:mbgl::MapChangeRegionDidChange];
    }
}

- (CLLocationCoordinate2D)convertPoint:(CGPoint)point toCoordinateFromView:(nullable UIView *)view
{
    return MGLLocationCoordinate2DFromLatLng([self convertPoint:point toLatLngFromView:view]);
}

/// Converts a point in the view’s coordinate system to a geographic coordinate.
- (mbgl::LatLng)convertPoint:(CGPoint)point toLatLngFromView:(nullable UIView *)view
{
    CGPoint convertedPoint = [self.view convertPoint:point fromView:view];
    return _mbglMap->latLngForPixel(mbgl::ScreenCoordinate(convertedPoint.x, convertedPoint.y)).wrapped();
}

- (CGPoint)convertCoordinate:(CLLocationCoordinate2D)coordinate toPointToView:(nullable UIView *)view
{
    return [self convertLatLng:MGLLatLngFromLocationCoordinate2D(coordinate) toPointToView:view];
}

/// Converts a geographic coordinate to a point in the view’s coordinate system.
- (CGPoint)convertLatLng:(mbgl::LatLng)latLng toPointToView:(nullable UIView *)view
{
    mbgl::ScreenCoordinate pixel = _mbglMap->pixelForLatLng(latLng);
    return [self.view convertPoint:CGPointMake(pixel.x, pixel.y) toView:view];
}

- (MGLCoordinateBounds)convertRect:(CGRect)rect toCoordinateBoundsFromView:(nullable UIView *)view
{
    return MGLCoordinateBoundsFromLatLngBounds([self convertRect:rect toLatLngBoundsFromView:view]);
}

- (CGRect)convertCoordinateBounds:(MGLCoordinateBounds)bounds toRectToView:(nullable UIView *)view
{
    return [self convertLatLngBounds:MGLLatLngBoundsFromCoordinateBounds(bounds) toRectToView:view];
}

/// Converts a geographic bounding box to a rectangle in the view’s coordinate
/// system.
- (CGRect)convertLatLngBounds:(mbgl::LatLngBounds)bounds toRectToView:(nullable UIView *)view {
    CGRect rect = { [self convertLatLng:bounds.southwest() toPointToView:view], CGSizeZero };
    rect = MGLExtendRect(rect, [self convertLatLng:bounds.northeast() toPointToView:view]);
    return rect;
}

/// Converts a rectangle in the given view’s coordinate system to a geographic
/// bounding box.
- (mbgl::LatLngBounds)convertRect:(CGRect)rect toLatLngBoundsFromView:(nullable UIView *)view
{
    mbgl::LatLngBounds bounds = mbgl::LatLngBounds::empty();
    bounds.extend([self convertPoint:rect.origin toLatLngFromView:view]);
    bounds.extend([self convertPoint:{ CGRectGetMaxX(rect), CGRectGetMinY(rect) } toLatLngFromView:view]);
    bounds.extend([self convertPoint:{ CGRectGetMaxX(rect), CGRectGetMaxY(rect) } toLatLngFromView:view]);
    bounds.extend([self convertPoint:{ CGRectGetMinX(rect), CGRectGetMaxY(rect) } toLatLngFromView:view]);
    
    // The world is wrapping if a point just outside the bounds is also within
    // the rect.
    mbgl::LatLng outsideLatLng;
    if (bounds.west() > -180)
    {
        outsideLatLng = {
            (bounds.south() + bounds.north()) / 2,
            bounds.west() - 1,
        };
    }
    else if (bounds.east() < 180)
    {
        outsideLatLng = {
            (bounds.south() + bounds.north()) / 2,
            bounds.east() + 1,
        };
    }
    
    // If the world is wrapping, extend the bounds to cover all longitudes.
    if (CGRectContainsPoint(rect, [self convertLatLng:outsideLatLng toPointToView:view]))
    {
        bounds.extend(mbgl::LatLng(bounds.south(), -180));
        bounds.extend(mbgl::LatLng(bounds.south(),  180));
    }
    
    return bounds;
}

- (CLLocationDistance)metersPerPointAtLatitude:(CLLocationDegrees)latitude
{
    return _mbglMap->getMetersPerPixelAtLatitude(latitude, self.zoomLevel);
}

- (CLLocationDistance)metersPerPixelAtLatitude:(CLLocationDegrees)latitude
{
    return [self metersPerPointAtLatitude:latitude];
}

// This is the delegate of the GLKView object's display call.
- (void)glkView:(__unused GLKView *)view drawInRect:(__unused CGRect)rect
{
//    if (timeSinceLastMapUpdate > 1.0) {
    _mbglView->updateViewBinding();
    _mbglMap->render(*_mbglView);
//        timeSinceLastMapUpdate = 0.0;
//    }
    
    // GLint currentProgram;
    // glGetIntegerv(GL_CURRENT_PROGRAM, &currentProgram);
    
    [_sceneRenderer renderAtTime:[self timeSinceLastResume]];
    
//    glDisable(GL_CULL_FACE);
//    glDisable(GL_DEPTH_TEST);
    
    //
    //        glDisable(GL_CULL_FACE);
    //        glDisable(GL_DEPTH_TEST);
    //
    //        // glUseProgram(currentProgram);
    //
    //        [self updateUserLocationAnnotationView];
}

- (void) commonInit
{
    MGLinitializeRunLoop();
    
    _mbglView = new MBGLControllerView(self);
    
    // setup mbgl map
    const std::array<uint16_t, 2> size = {{ static_cast<uint16_t>(self.view.bounds.size.width),
        static_cast<uint16_t>(self.view.bounds.size.height) }};
    
    mbgl::DefaultFileSource *mbglFileSource = [MGLOfflineStorage sharedOfflineStorage].mbglFileSource;
    mbglFileSource->setAccessToken("pk.eyJ1IjoidHNoYXJqdS1mdXR1cmVmbHkiLCJhIjoiY2lzbGh5bDU0MDA1eTMycGt1enRpZG1mNCJ9.TT054-OInZKkztKeJMnkmA");
    
    const float scaleFactor = [UIScreen instancesRespondToSelector:@selector(nativeScale)] ? [[UIScreen mainScreen] nativeScale] : [[UIScreen mainScreen] scale];
    _mbglThreadPool = new mbgl::ThreadPool(4);
    
    _mbglMap = new mbgl::Map(*_mbglView, size, scaleFactor, *mbglFileSource, *_mbglThreadPool, mbgl::MapMode::Continuous, mbgl::GLContextMode::Shared, mbgl::ConstrainMode::None, mbgl::ViewportMode::Default);
    
    _mbglMap->setStyleURL("mapbox://styles/mapbox/streets-v10");
    
    self.zoomLevel = 14;
    
    mbgl::CameraOptions options;
    options.center = mbgl::LatLng(60.1711245, 24.94537);
    mbgl::EdgeInsets padding = MGLEdgeInsetsFromNSEdgeInsets(UIEdgeInsetsZero);
    options.padding = padding;
    options.zoom = self.zoomLevel;
    options.pitch = 45.0 * (M_PI / 180.0);
    
    _mbglMap->jumpTo(options);
    
    SCNScene *scene = [SCNScene sceneNamed:@"scene.scn"];
    
    _sceneCameraNode = [[scene rootNode] childNodeWithName:@"camera" recursively:NO];
    
    _sceneRenderer = [SCNRenderer rendererWithContext:_context options:nil];
    _sceneRenderer.scene = scene;
    _sceneRenderer.autoenablesDefaultLighting = NO;
    _sceneRenderer.pointOfView = _sceneCameraNode;
}

- (void)update {
//    if (timeSinceLastZoom > 5.0) {
//        _mbglMap->setZoom(_mbglMap->getZoom() + 1);
//        timeSinceLastZoom = 0.0;
//    }
//    
//    timeSinceLastZoom += [self timeSinceLastUpdate];
    
    timeSinceLastMapUpdate += [self timeSinceLastUpdate];
}

- (void)notifyMapChange:(mbgl::MapChange)change {}

- (void)setNeedsGLDisplay {}

class MBGLControllerView : public mbgl::View, public mbgl::Backend
{
public:
    MBGLControllerView(MGLMapViewController* nativeView_)
    : nativeView(nativeView_) {
    }
    
    mbgl::gl::value::Viewport::Type getViewport() const {
        return { 0, 0, static_cast<uint16_t>(((GLKView *)nativeView.view).drawableWidth),
            static_cast<uint16_t>(((GLKView *)nativeView.view).drawableHeight) };
    }
    
    /// This function is called before we start rendering, when iOS invokes our rendering method.
    /// iOS already sets the correct framebuffer and viewport for us, so we need to update the
    /// context state with the anticipated values.
    void updateViewBinding() {
        // We are using 0 as the placeholder value for the GLKView's framebuffer.
        getContext().bindFramebuffer.setCurrentValue(0);
        getContext().viewport.setCurrentValue(getViewport());
    }
    
    void bind() override {
        if (getContext().bindFramebuffer != 0) {
            // Something modified our state, and we need to bind the original drawable again.
            // Doing this also sets the viewport to the full framebuffer.
            // Note that in reality, iOS does not use the Framebuffer 0 (it's typically 1), and we
            // only use this is a placeholder value.
            [((GLKView *)nativeView.view) bindDrawable];
            updateViewBinding();
        } else {
            // Our framebuffer is still bound, but the viewport might have changed.
            getContext().viewport = getViewport();
        }
    }
    
    void notifyMapChange(mbgl::MapChange change) override
    {
        [nativeView notifyMapChange:change];
    }
    
    void invalidate() override
    {
        [nativeView setNeedsGLDisplay];
    }
    
    void activate() override
    {
        if (activationCount++)
        {
            return;
        }
        
        [EAGLContext setCurrentContext:nativeView.context];
    }
    
    void deactivate() override
    {
        if (--activationCount)
        {
            return;
        }
        
        [EAGLContext setCurrentContext:nil];
    }
    
private:
    __weak MGLMapViewController *nativeView = nullptr;
    
    NSUInteger activationCount = 0;
};

@end
