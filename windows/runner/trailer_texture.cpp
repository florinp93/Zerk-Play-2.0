#include "trailer_texture.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <algorithm>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <vector>

namespace {

struct mpv_render_param {
  int type;
  void* data;
};
constexpr int kParamInvalid = 0;
constexpr int kParamApiType = 1;
constexpr int kParamSwSize = 17;
constexpr int kParamSwFormat = 18;
constexpr int kParamSwStride = 19;
constexpr int kParamSwPointer = 20;
constexpr uint64_t kUpdateFrame = 1;

using RenderUpdateFn = void (*)(void*);

struct MpvRenderApi {
  int (*create)(void** ctx, void* mpv, mpv_render_param* params) = nullptr;
  void (*set_update_callback)(void* ctx, RenderUpdateFn cb, void* data) = nullptr;
  uint64_t (*update)(void* ctx) = nullptr;
  int (*render)(void* ctx, mpv_render_param* params) = nullptr;
  void (*free)(void* ctx) = nullptr;

  bool ok() const { return create && set_update_callback && update && render && free; }

  static const MpvRenderApi& Get() {
    static const MpvRenderApi api = [] {
      MpvRenderApi a;
      HMODULE lib = GetModuleHandleW(L"libmpv-2.dll");
      if (!lib) lib = LoadLibraryW(L"libmpv-2.dll");
      if (!lib) return a;
      a.create = reinterpret_cast<decltype(a.create)>(GetProcAddress(lib, "mpv_render_context_create"));
      a.set_update_callback = reinterpret_cast<decltype(a.set_update_callback)>(
          GetProcAddress(lib, "mpv_render_context_set_update_callback"));
      a.update = reinterpret_cast<decltype(a.update)>(GetProcAddress(lib, "mpv_render_context_update"));
      a.render = reinterpret_cast<decltype(a.render)>(GetProcAddress(lib, "mpv_render_context_render"));
      a.free = reinterpret_cast<decltype(a.free)>(GetProcAddress(lib, "mpv_render_context_free"));
      return a;
    }();
    return api;
  }
};

int AlignWidth(int w) { return std::max(16, (w + 15) / 16 * 16); }

const flutter::EncodableValue* Arg(const flutter::EncodableMap& m, const char* key) {
  auto it = m.find(flutter::EncodableValue(key));
  return it == m.end() ? nullptr : &it->second;
}

int64_t ArgInt(const flutter::EncodableMap& m, const char* key) {
  const auto* v = Arg(m, key);
  return v ? v->LongValue() : 0;
}

}

class MpvTexture {
 public:
  explicit MpvTexture(FlutterDesktopTextureRegistrarRef registrar) : registrar_(registrar) {}

  bool Start(void* mpv, int width, int height) {
    const auto& api = MpvRenderApi::Get();
    if (!api.ok()) return false;
    char api_type[] = "sw";
    mpv_render_param params[] = {{kParamApiType, api_type}, {kParamInvalid, nullptr}};
    if (api.create(&ctx_, mpv, params) < 0) {
      ctx_ = nullptr;
      return false;
    }
    SetSize(width, height);

    FlutterDesktopTextureInfo info = {};
    info.type = kFlutterDesktopPixelBufferTexture;
    info.pixel_buffer_config.callback = [](size_t, size_t, void* self) {
      return static_cast<MpvTexture*>(self)->CopyPixelBuffer();
    };
    info.pixel_buffer_config.user_data = this;
    id_ = FlutterDesktopTextureRegistrarRegisterExternalTexture(registrar_, &info);

    thread_ = std::thread([this] { RenderLoop(); });
    api.set_update_callback(ctx_, [](void* self) { static_cast<MpvTexture*>(self)->Wake(false); }, this);
    return true;
  }

  int64_t id() const { return id_; }

  void SetSize(int width, int height) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      width_ = AlignWidth(std::clamp(width, 16, 3840));
      height_ = std::clamp(height, 16, 2160);
    }
    Wake(true);
  }

  static void Dispose(std::shared_ptr<MpvTexture> self) {
    {
      std::lock_guard<std::mutex> lock(self->mutex_);
      self->quit_ = true;
    }
    self->cv_.notify_all();
    if (self->thread_.joinable()) self->thread_.join();
    if (self->ctx_) {
      const auto& api = MpvRenderApi::Get();
      api.set_update_callback(self->ctx_, nullptr, nullptr);
      api.free(self->ctx_);
      self->ctx_ = nullptr;
    }
    if (self->id_ >= 0) {
      auto* keep = new std::shared_ptr<MpvTexture>(self);
      FlutterDesktopTextureRegistrarUnregisterExternalTexture(
          self->registrar_, self->id_, [](void* p) { delete static_cast<std::shared_ptr<MpvTexture>*>(p); }, keep);
    }
  }

 private:
  struct Frame {
    std::vector<uint8_t> pixels;
    int width = 0;
    int height = 0;
  };

  void Wake(bool force) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      pending_ = true;
      if (force) force_ = true;
    }
    cv_.notify_one();
  }

  void RenderLoop() {
    const auto& api = MpvRenderApi::Get();
    while (true) {
      bool force;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        cv_.wait(lock, [this] { return pending_ || quit_; });
        if (quit_) return;
        pending_ = false;
        force = force_;
        force_ = false;
      }
      const bool frame = (api.update(ctx_) & kUpdateFrame) != 0;
      if (!frame && !(force && has_frame_)) continue;

      int slot, w, h;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        slot = 0;
        while (slot == latest_ || slot == reading_) slot++;
        w = width_;
        h = height_;
      }
      Frame& f = frames_[slot];
      if (f.width != w || f.height != h) {
        f.pixels.assign(static_cast<size_t>(w) * h * 4, 0);
        f.width = w;
        f.height = h;
      }
      int size[2] = {w, h};
      size_t stride = static_cast<size_t>(w) * 4;
      char format[] = "rgba";
      mpv_render_param params[] = {
          {kParamSwSize, size},
          {kParamSwFormat, format},
          {kParamSwStride, &stride},
          {kParamSwPointer, f.pixels.data()},
          {kParamInvalid, nullptr},
      };
      if (api.render(ctx_, params) < 0) continue;
      has_frame_ = true;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        latest_ = slot;
      }
      FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(registrar_, id_);
    }
  }

  const FlutterDesktopPixelBuffer* CopyPixelBuffer() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (latest_ < 0) return nullptr;
    reading_ = latest_;
    const Frame& f = frames_[reading_];
    out_.buffer = f.pixels.data();
    out_.width = f.width;
    out_.height = f.height;
    out_.release_context = this;
    out_.release_callback = [](void* self) {
      auto* t = static_cast<MpvTexture*>(self);
      std::lock_guard<std::mutex> lock(t->mutex_);
      t->reading_ = -1;
    };
    return &out_;
  }

  FlutterDesktopTextureRegistrarRef registrar_;
  void* ctx_ = nullptr;
  int64_t id_ = -1;
  std::thread thread_;

  std::mutex mutex_;
  std::condition_variable cv_;
  bool pending_ = false;
  bool force_ = false;
  bool quit_ = false;
  int width_ = 0;
  int height_ = 0;
  int latest_ = -1;
  int reading_ = -1;

  bool has_frame_ = false;
  Frame frames_[3];
  FlutterDesktopPixelBuffer out_ = {};
};

TrailerTextures::TrailerTextures(flutter::BinaryMessenger* messenger, FlutterDesktopTextureRegistrarRef registrar)
    : registrar_(registrar) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "zerk/trailer", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) {
      result->Error("args", "expected a map");
      return;
    }
    const auto& method = call.method_name();
    if (method == "create") {
      auto texture = std::make_shared<MpvTexture>(registrar_);
      void* mpv = reinterpret_cast<void*>(ArgInt(*args, "handle"));
      if (!mpv || !texture->Start(mpv, static_cast<int>(ArgInt(*args, "width")),
                                  static_cast<int>(ArgInt(*args, "height")))) {
        result->Error("render", "could not create an mpv render context");
        return;
      }
      textures_[texture->id()] = texture;
      result->Success(flutter::EncodableValue(texture->id()));
    } else if (method == "resize") {
      auto it = textures_.find(ArgInt(*args, "id"));
      if (it != textures_.end()) {
        it->second->SetSize(static_cast<int>(ArgInt(*args, "width")), static_cast<int>(ArgInt(*args, "height")));
      }
      result->Success();
    } else if (method == "dispose") {
      auto it = textures_.find(ArgInt(*args, "id"));
      if (it != textures_.end()) {
        auto texture = it->second;
        textures_.erase(it);
        MpvTexture::Dispose(texture);
      }
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
}

TrailerTextures::~TrailerTextures() {
  channel_->SetMethodCallHandler(nullptr);
  for (auto& [id, texture] : textures_) MpvTexture::Dispose(texture);
}
