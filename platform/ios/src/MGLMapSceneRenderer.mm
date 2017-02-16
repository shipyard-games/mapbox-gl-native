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

#import "MGLMapSceneRenderer.h"
#import "MGLOfflineStorage_Private.h"
#import "MGLGeometry_Private.h"

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

- (instancetype)initWithView:(SCNView *)view
{
    self = [super init];
    
    if (self) {
        self.view = view;
        
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
        const std::array<uint16_t, 2> size = { {1242, 2208} };
        
        mbgl::DefaultFileSource *mbglFileSource = [MGLOfflineStorage sharedOfflineStorage].mbglFileSource;
        mbglFileSource->setAccessToken("pk.eyJ1IjoidHNoYXJqdS1mdXR1cmVmbHkiLCJhIjoiY2lzbGh5bDU0MDA1eTMycGt1enRpZG1mNCJ9.TT054-OInZKkztKeJMnkmA");
        
        const float scaleFactor = [UIScreen instancesRespondToSelector:@selector(nativeScale)] ? [[UIScreen mainScreen] nativeScale] : [[UIScreen mainScreen] scale];
        _mbglThreadPool = new mbgl::ThreadPool(4);
        _mbglMap = new mbgl::Map(*_mbglView, size, scaleFactor, *mbglFileSource, *_mbglThreadPool, mbgl::MapMode::Continuous, mbgl::GLContextMode::Unique, mbgl::ConstrainMode::None, mbgl::ViewportMode::Default);
        
        mbgl::CameraOptions options;
        options.center = mbgl::LatLng(0, 0);
        options.zoom = 0;
        mbgl::EdgeInsets padding = MGLEdgeInsetsFromNSEdgeInsets(self.view.layoutMargins);
        options.padding = padding;
        
        _mbglMap->jumpTo(options);
        _mbglMap->setStyleURL("mapbox://styles/mapbox/streets-v10");
    }
    
    return self;
}

- (void)notifyMapChange:(mbgl::MapChange)change
{
    NSLog(@"notifyMapChange: change=%d", change);
    
    switch(change) {
        case mbgl::MapChange::MapChangeDidFinishLoadingStyle:
            //_mbglView->updateViewBinding();
            _mbglMap->render(*_mbglView);
        default:
            break;
    }
}

#pragma mark - SCNSceneRendererDelegate -

- (void)renderer:(id<SCNSceneRenderer>)renderer updateAtTime:(NSTimeInterval)time
{
    if (_mbglMap->isFullyLoaded()) {
        //_mbglView->updateViewBinding();
        _mbglMap->render(*_mbglView);
    }
    
}

- (void)renderer:(id<SCNSceneRenderer>)renderer willRenderScene:(SCNScene *)scene atTime:(NSTimeInterval)time
{

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

#pragma mark - MBGLSceneView -

class MBGLSceneView : public mbgl::View, public mbgl::Backend
{
public:
    MBGLSceneView(MGLMapSceneRenderer* nativeRenderer_)
    : nativeRenderer(nativeRenderer_) {
    }
    
    mbgl::gl::value::Viewport::Type getViewport() const {
        return { 0, 0, 1242, 2208 };
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
            // [nativeView.glView bindDrawable];
            updateViewBinding();
        } else {
            // Our framebuffer is still bound, but the viewport might have changed.
            getContext().viewport = getViewport();
        }
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
        if (activationCount++)
        {
            return;
        }
        
       [EAGLContext setCurrentContext:nativeRenderer.view.eaglContext];
    }
    
    void deactivate() override
    {
        if (--activationCount)
        {
            return;
        }
        
        [EAGLContext setCurrentContext:nil];
    }
    
    void renderScene(__unused mbgl::mat4 projMatrix) override
    {}
    
private:
    __weak MGLMapSceneRenderer *nativeRenderer = nullptr;
    
    NSUInteger activationCount = 0;
};

@end
