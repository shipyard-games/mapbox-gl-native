//
//  MGLMapSceneRenderer.h
//  ios
//
//  Created by Teemu Harju on 11/02/2017.
//  Copyright © 2017 Mapbox. All rights reserved.
//

#import <SceneKit/SceneKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MGLMapSceneRenderer : NSObject <SCNSceneRendererDelegate>

@property (nonatomic, nonnull) SCNView *view;

- (instancetype)initWithView:(SCNView *)view;

- (void)renderer:(id<SCNSceneRenderer>)renderer updateAtTime:(NSTimeInterval)time;
- (void)renderer:(id<SCNSceneRenderer>)renderer didRenderScene:(SCNScene *)scene atTime:(NSTimeInterval)time;
- (void)renderer:(id<SCNSceneRenderer>)renderer willRenderScene:(SCNScene *)scene atTime:(NSTimeInterval)time;
- (void)renderer:(id<SCNSceneRenderer>)renderer didApplyAnimationsAtTime:(NSTimeInterval)time;
- (void)renderer:(id<SCNSceneRenderer>)renderer didSimulatePhysicsAtTime:(NSTimeInterval)time;

@end

NS_ASSUME_NONNULL_END

