//
//  scene.hpp
//  mbgl
//
//  Created by Teemu Harju on 02/03/2017.
//
//
#include <mbgl/util/noncopyable.hpp>
#include <mbgl/actor/scheduler.hpp>
#include <mbgl/storage/file_source.hpp>
#include <mbgl/renderer/render_item.hpp>

#include <memory>

namespace mbgl {

class Scene : private util::noncopyable {
public:
    explicit Scene(float pixelRatio,
                   FileSource& fileSource,
                   Scheduler& scheduler);
    ~Scene();
    
    void setStyleURL(const std::string& url);
    RenderData render();

private:
    class Impl;
    const std::unique_ptr<Impl> impl;
};

} // namespace mbgl
