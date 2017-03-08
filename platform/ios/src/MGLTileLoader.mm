//
//  MGLTileLoader.m
//  ios
//
//  Created by Teemu Harju on 01/03/2017.
//  Copyright © 2017 Mapbox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SceneKit/SceneKit.h>

#import "MGLTileLoader.h"
#import "MGLOfflineStorage_Private.h"

#include <mbgl/mbgl.hpp>
#include <mbgl/style/style.hpp>
#include <mbgl/style/layer.hpp>
#include <mbgl/style/update_parameters.hpp>
#include <mbgl/platform/default/thread_pool.hpp>
#include <mbgl/storage/default_file_source.hpp>
#include <mbgl/map/transform_state.hpp>
#include <mbgl/map/mode.hpp>
#include <mbgl/map/scene.hpp>
#include <mbgl/annotation/annotation_manager.hpp>
#include <mbgl/renderer/render_item.hpp>
#include <mbgl/shader/fill_vertex.hpp>
#include <mbgl/renderer/bucket.hpp>
#include <mbgl/renderer/fill_bucket.hpp>


// Forward declarations
void MGLinitializeRunLoop();

@implementation MGLTileLoader

using namespace mbgl;

ThreadPool *_mbglThreadPool;
DefaultFileSource *_mbglFileSource;
Scene *_mbglScene;

float _scaleFactor;

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        MGLinitializeRunLoop();
        
        _mbglThreadPool = new mbgl::ThreadPool(4);
        
        NSURL *cacheURL = [self cacheURL];
        
        NSLog(@"CACHE URL: %@", cacheURL);
        
        _mbglFileSource = new mbgl::DefaultFileSource(cacheURL.path.UTF8String, [NSBundle mainBundle].resourceURL.path.UTF8String);
        _mbglFileSource->setAccessToken("pk.eyJ1IjoidHNoYXJqdS1mdXR1cmVmbHkiLCJhIjoiY2lzbGh5bDU0MDA1eTMycGt1enRpZG1mNCJ9.TT054-OInZKkztKeJMnkmA");
        
        _scaleFactor = [UIScreen instancesRespondToSelector:@selector(nativeScale)] ? [[UIScreen mainScreen] nativeScale] : [[UIScreen mainScreen] scale];
        
        _mbglScene = new Scene(_scaleFactor, *_mbglFileSource, *_mbglThreadPool);
        _mbglScene->setStyleURL("mapbox://styles/tsharju-futurefly/cixcvf5u000jn2qs6syfn7ys4");
    }
    
    return self;
}

- (void)updateTiles
{

}

- (void)render
{
    RenderData renderData = _mbglScene->render();
    NSMutableArray *geometriesArray = [[NSMutableArray alloc] initWithCapacity: 50];
//    const std::vector<RenderItem>& order = renderData.order;
//    const RenderItem& item = order.front();
//    const FillBucket *bucket = reinterpret_cast<FillBucket*>(item.bucket);
//    
//    std::vector<SCNVector3> scnVertices;
//    
//    for (const FillVertex& v : bucket->vertices) {
//        scnVertices.push_back(SCNVector3Make(static_cast<float>(v.a_pos[0]) / 100.0, 0.0, static_cast<float>(v.a_pos[1]) / 100.0));
//    }
//    
//    SCNGeometrySource *vertexSource = [SCNGeometrySource geometrySourceWithVertices:&scnVertices[0] count:scnVertices.size()];
//    
//    SCNGeometryElement *element = [SCNGeometryElement geometryElementWithData:&bucket->indices primitiveType:<#(SCNGeometryPrimitiveType)#> primitiveCount:<#(NSInteger)#> bytesPerIndex:<#(NSInteger)#>
    
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

@end
