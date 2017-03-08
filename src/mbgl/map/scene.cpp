//
//  scene.cpp
//  mbgl
//
//  Created by Teemu Harju on 02/03/2017.
//
//

#include <mbgl/map/scene.hpp>

#include <mbgl/annotation/annotation_manager.hpp>
#include <mbgl/util/async_task.hpp>
#include <mbgl/actor/scheduler.hpp>
#include <mbgl/style/observer.hpp>
#include <mbgl/storage/file_source.hpp>
#include <mbgl/style/style.hpp>
#include <mbgl/style/update_parameters.hpp>
#include <mbgl/platform/log.hpp>
#include <mbgl/map/mode.hpp>
#include <mbgl/map/transform.hpp>
#include <mbgl/renderer/render_item.hpp>

namespace mbgl {

using namespace style;
    
class Scene::Impl : public style::Observer {
public:
    Impl(float pixelRatio,
         FileSource& fileSource,
         Scheduler& scheduler);
    
    FileSource& fileSource;
    Scheduler& scheduler;
    
    Transform transform;
    
    std::unique_ptr<AnnotationManager> annotationManager;
    std::unique_ptr<Style> style;
    
    std::unique_ptr<AsyncRequest> styleRequest;
    
    const float pixelRatio;
    
    std::string styleURL;
    std::string styleJSON;
    
    util::AsyncTask asyncUpdate;
    
    TimePoint timePoint;
    
    void loadStyleJSON(const std::string& json);
    void onUpdate(Update flags);
    void update();
    RenderData render();
};
    
Scene::Scene(float pixelRatio,
             FileSource& fileSource,
             Scheduler& scheduler)
    : impl(std::make_unique<Impl>(pixelRatio,
                                  fileSource,
                                  scheduler)) {
}
    
RenderData Scene::render() {
    return impl->render();
}
    
Scene::Impl::Impl(float pixelRatio_,
                FileSource& fileSource_,
                Scheduler& scheduler_)
    : fileSource(fileSource_),
      scheduler(scheduler_),
      transform([this](__unused MapChange change) {
      
      }),
      annotationManager(std::make_unique<AnnotationManager>(pixelRatio_)),
      pixelRatio(pixelRatio_),
      asyncUpdate([this] { update(); }) {
          transform.resize({ {1000, 1000} });
}

Scene::~Scene() {
    impl->style.reset();
}
    
void Scene::setStyleURL(const std::string& url) {
    if (impl->styleURL == url) {
        return;
    }
    
    impl->styleRequest = nullptr;
    impl->styleURL = url;
    impl->style = std::make_unique<Style>(impl->fileSource, impl->pixelRatio);
    
    impl->styleRequest = impl->fileSource.request(Resource::style(impl->styleURL), [this] (Response res) {
    
        if (res.isFresh()) {
            impl->styleRequest.reset();
        }
        
        if (res.error) {
            Log::Error(Event::Setup, "loading style failed: %s", res.error->message.c_str());
        } else if (res.notModified || res.noContent) {
            return;
        } else {
            impl->loadStyleJSON(*res.data);
        }
    });
}

RenderData Scene::Impl::render() {
    return style->getRenderData(MapDebugOptions::NoDebug);
}
    
void Scene::Impl::onUpdate(__unused Update flags) {
    asyncUpdate.send();
}
    
void Scene::Impl::loadStyleJSON(const std::string& json) {
    style->setObserver(this);
    style->setJSON(json);
    styleJSON = json;
    
    asyncUpdate.send();
}
    
void Scene::Impl::update() {
    if (!style) {
        return;
    }
    
    timePoint = Clock::now();
    
    style->cascade(timePoint, MapMode::Continuous);
    style->recalculate(transform.getZoom(), timePoint, MapMode::Still);
    
    style::UpdateParameters parameters(pixelRatio,
                                       MapDebugOptions::NoDebug,
                                       transform.getState(),
                                       scheduler,
                                       fileSource,
                                       MapMode::Still,
                                       *annotationManager,
                                       *style);
    style->updateTiles(parameters);
}
    
} // namespace mbgl
