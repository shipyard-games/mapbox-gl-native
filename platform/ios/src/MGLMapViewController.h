//
//  MGLMapViewController.h
//  ios
//
//  Created by Teemu Harju on 08/03/2017.
//  Copyright © 2017 Mapbox. All rights reserved.
//

#import <GLKit/GLKit.h>
#import <SceneKit/SceneKit.h>

#import "MGLTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface MGLMapViewController : GLKViewController

@property (nonatomic) EAGLContext *context;
@property (nonatomic) SCNRenderer *sceneRenderer;
@property (nonatomic) MGLUserTrackingMode userTrackingMode;
@property (nonatomic) CGFloat decelerationRate;

@end

NS_ASSUME_NONNULL_END
