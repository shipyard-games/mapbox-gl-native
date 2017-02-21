//
//  MGLMapSceneRenderer.m
//  ios
//
//  Created by Teemu Harju on 11/02/2017.
//  Copyright © 2017 Mapbox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <SceneKit/SceneKit.h>
#import <GLKit/GLKit.h>
#import <OpenGLES/EAGL.h>
#import <SceneKit/SceneKit.h>

#import "MGLMapSceneRenderer.h"
#import "MGLOfflineStorage_Private.h"
#import "MGLGeometry_Private.h"
#import "NSDate+MGLAdditions.h"

#include <mbgl/gl/extension.hpp>
#include <mbgl/gl/context.hpp>

#include <mbgl/mbgl.hpp>
#include <mbgl/annotation/annotation.hpp>
#include <mbgl/sprite/sprite_image.hpp>
#include <mbgl/map/camera.hpp>
#include <mbgl/map/mode.hpp>
#include <mbgl/platform/platform.hpp>
#include <mbgl/platform/darwin/reachability.h>
#include <mbgl/platform/default/thread_pool.hpp>
#include <mbgl/storage/default_file_source.hpp>
#include <mbgl/storage/network_status.hpp>
#include <mbgl/style/transition_options.hpp>
#include <mbgl/style/layers/custom_layer.hpp>
#include <mbgl/map/backend.hpp>
#include <mbgl/math/wrap.hpp>
#include <mbgl/util/geo.hpp>
#include <mbgl/util/constants.hpp>
#include <mbgl/util/image.hpp>
#include <mbgl/util/projection.hpp>
#include <mbgl/util/default_styles.hpp>
#include <mbgl/util/chrono.hpp>
#include <mbgl/util/run_loop.hpp>

class MBGLSceneView;
void MGLinitializeRunLoop();

@implementation MGLMapSceneRenderer

mbgl::Map *_mbglMap;
MBGLSceneView *_mbglView;
mbgl::ThreadPool *_mbglThreadPool;
BOOL _initialized = NO;
GLint renderProgram;

- (instancetype)initWithView:(SCNView *)view
{
    self = [super init];
    
    if (self) {
        self.view = view;
        
        [self initialize];
    }
    
    return self;
}

- (void)notifyMapChange:(mbgl::MapChange)change
{
    NSLog(@"notifyMapChange: change=%d", change);
}

- (void)initialize
{
    MGLinitializeRunLoop();
    
    _mbglView = new MBGLSceneView(self);
    
    _mbglThreadPool = new mbgl::ThreadPool(4);
    
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
    
    // setup mbgl map
    const std::array<uint16_t, 2> size = { {static_cast<uint16_t>(self.view.bounds.size.width), static_cast<uint16_t>(self.view.bounds.size.height)} };
    
    NSLog(@"size w=%d h=%d", size[0], size[1]);
    
    // mbgl::DefaultFileSource *mbglFileSource = [MGLOfflineStorage sharedOfflineStorage].mbglFileSource;
    // mbglFileSource->setAccessToken("pk.eyJ1IjoidHNoYXJqdS1mdXR1cmVmbHkiLCJhIjoiY2lzbGh5bDU0MDA1eTMycGt1enRpZG1mNCJ9.TT054-OInZKkztKeJMnkmA");
    
    NSURL *cacheURL = [self cacheURL];
    
    mbgl::DefaultFileSource *fileSource = new mbgl::DefaultFileSource(cacheURL.path.UTF8String, [NSBundle mainBundle].resourceURL.path.UTF8String);
    fileSource->setAccessToken("pk.eyJ1IjoidHNoYXJqdS1mdXR1cmVmbHkiLCJhIjoiY2lzbGh5bDU0MDA1eTMycGt1enRpZG1mNCJ9.TT054-OInZKkztKeJMnkmA");
    
    const float scaleFactor = [UIScreen instancesRespondToSelector:@selector(nativeScale)] ? [[UIScreen mainScreen] nativeScale] : [[UIScreen mainScreen] scale];
    _mbglThreadPool = new mbgl::ThreadPool(4);
    _mbglMap = new mbgl::Map(*_mbglView, size, scaleFactor, *fileSource, *_mbglThreadPool, mbgl::MapMode::Continuous, mbgl::GLContextMode::Unique, mbgl::ConstrainMode::None, mbgl::ViewportMode::Default);
    
    mbgl::CameraOptions options;
    options.center = mbgl::LatLng(60.1641013, 24.9001869);
    options.zoom = 5;
    options.pitch = 45 * (M_PI / 180.0);
    
    _mbglMap->jumpTo(options);
    _mbglMap->setStyleURL("mapbox://styles/mapbox/streets-v10"); // starts loading the style and map
    
    _initialized = YES;
}

- (void)zoomIn:(CGPoint)location
{
    _mbglMap->cancelTransitions();
    
    mbgl::LatLng loc = _mbglMap->latLngForPixel(mbgl::ScreenCoordinate(location.x, location.y)).wrapped();
    
    _mbglMap->setLatLng(loc);
    _mbglMap->setZoom(_mbglMap->getZoom() + 1,
                      MGLEdgeInsetsFromNSEdgeInsets(UIEdgeInsets()),
                      MGLDurationInSeconds(2));
}

#pragma mark - SCNSceneRendererDelegate -

- (void)renderer:(id<SCNSceneRenderer>)renderer updateAtTime:(NSTimeInterval)time
{
    /*if (!_initialized) {
        [self initialize];
    } else {
        mbgl::util::RunLoop::Get()->runOnce();
    }*/
}

- (void)renderer:(id<SCNSceneRenderer>)renderer willRenderScene:(SCNScene *)scene atTime:(NSTimeInterval)time
{
    glDisable(GL_CULL_FACE);
    glDisable(GL_DEPTH_TEST);
    
    glClearColor(0.901960849, 0.894117712, 0.878431439, 1.0); // default background color
    glClear(GL_COLOR_BUFFER_BIT);
    
    if (renderProgram != 0) {
        glUseProgram(renderProgram);
    }
    
    _mbglMap->render(*_mbglView);
    
    glGetIntegerv(GL_CURRENT_PROGRAM, &renderProgram);
    
    glEnable(GL_CULL_FACE);
    glEnable(GL_DEPTH_TEST);
    
    glClear(GL_DEPTH_BUFFER_BIT);
}

- (void)renderer:(id<SCNSceneRenderer>)renderer didRenderScene:(SCNScene *)scene atTime:(NSTimeInterval)time
{

}

- (void)renderer:(id<SCNSceneRenderer>)renderer didSimulatePhysicsAtTime:(NSTimeInterval)time
{

}

- (void)renderer:(id<SCNSceneRenderer>)renderer didApplyAnimationsAtTime:(NSTimeInterval)time
{

}

- (NSURL *)cacheURL
{
    NSURL *cacheDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                                      inDomain:NSUserDomainMask
                                                             appropriateForURL:nil
                                                                        create:YES
                                                                         error:nil];
    NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
    if (!bundleIdentifier) {
        // There’s no main bundle identifier when running in a unit test bundle.
        bundleIdentifier = [NSBundle bundleForClass:self].bundleIdentifier;
    }
    cacheDirectoryURL = [cacheDirectoryURL URLByAppendingPathComponent:bundleIdentifier];
    cacheDirectoryURL = [cacheDirectoryURL URLByAppendingPathComponent:@".mapbox"];
    
    [[NSFileManager defaultManager] createDirectoryAtURL:cacheDirectoryURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    
    // Avoid backing up the offline cache onto iCloud, because it can be
    // redownloaded. Ideally, we’d even put the ambient cache in Caches, so
    // it can be reclaimed by the system when disk space runs low. But
    // unfortunately it has to live in the same file as offline resources.
    [cacheDirectoryURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:NULL];
    
    return [cacheDirectoryURL URLByAppendingPathComponent:@"cache.db"];
}

#pragma mark - MBGLSceneView -

class MBGLSceneView : public mbgl::View, public mbgl::Backend
{
public:
    MBGLSceneView(MGLMapSceneRenderer* nativeRenderer_)
    : nativeRenderer(nativeRenderer_) {
    }
    
    mbgl::gl::value::Viewport::Type getViewport() const {
        GLint viewport[4];
        glGetIntegerv(GL_VIEWPORT, viewport);
        
        return { 0, 0, static_cast<uint16_t>(viewport[2]), static_cast<uint16_t>(viewport[3]) };
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
        //if (getContext().bindFramebuffer != 0) {
            // Something modified our state, and we need to bind the original drawable again.
            // Doing this also sets the viewport to the full framebuffer.
            // Note that in reality, iOS does not use the Framebuffer 0 (it's typically 1), and we
            // only use this is a placeholder value.
            // [nativeView.glView bindDrawable];
         //   updateViewBinding();
        //} else {
            // Our framebuffer is still bound, but the viewport might have changed.
        //getContext().viewport = getViewport();
        //}
    }
    
    void notifyMapChange(mbgl::MapChange change) override
    {
        [nativeRenderer notifyMapChange:change];
    }
    
    void invalidate() override
    {
        // [nativeView setNeedsGLDisplay];
    }
    
    void activate() override
    {
        /*if (activationCount++)
        {
            return;
        }
        
       [EAGLContext setCurrentContext:nativeRenderer.view.eaglContext];
        */
    }
    
    void deactivate() override
    {
        /*if (--activationCount)
        {
            return;
        }
        
        [EAGLContext setCurrentContext:nil];
        */
    }
    
private:
    __weak MGLMapSceneRenderer *nativeRenderer = nullptr;
    
    // NSUInteger activationCount = 0;
};

@end
