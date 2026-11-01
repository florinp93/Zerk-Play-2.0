#include "trailer_texture.h"

#include <mpv/render.h>

#include <algorithm>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <thread>
#include <vector>

struct Frame {
  std::vector<uint8_t> pixels;
  int width = 0;
  int height = 0;
};

struct FrameStore {
  std::mutex mutex;
  Frame frames[3];
  int latest = -1;
  int reading = -1;
};

G_DECLARE_FINAL_TYPE(ZerkMpvTexture, zerk_mpv_texture, ZERK, MPV_TEXTURE, FlPixelBufferTexture)

struct _ZerkMpvTexture {
  FlPixelBufferTexture parent_instance;
  std::shared_ptr<FrameStore>* store;
};

G_DEFINE_TYPE(ZerkMpvTexture, zerk_mpv_texture, fl_pixel_buffer_texture_get_type())

static gboolean zerk_mpv_texture_copy_pixels(FlPixelBufferTexture* texture, const uint8_t** buffer, uint32_t* width,
                                             uint32_t* height, GError** error);

static void zerk_mpv_texture_finalize(GObject* object) {
  auto* self = ZERK_MPV_TEXTURE(object);
  delete self->store;
  self->store = nullptr;
  G_OBJECT_CLASS(zerk_mpv_texture_parent_class)->finalize(object);
}

static void zerk_mpv_texture_class_init(ZerkMpvTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = zerk_mpv_texture_copy_pixels;
  G_OBJECT_CLASS(klass)->finalize = zerk_mpv_texture_finalize;
}

static void zerk_mpv_texture_init(ZerkMpvTexture* self) {}

namespace {

int AlignWidth(int w) { return std::max(16, (w + 15) / 16 * 16); }

int64_t ArgInt(FlValue* args, const char* key) {
  FlValue* v = fl_value_lookup_string(args, key);
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_INT ? fl_value_get_int(v) : 0;
}

}

class MpvTexture {
 public:
  explicit MpvTexture(FlTextureRegistrar* registrar)
      : registrar_(registrar), store_(std::make_shared<FrameStore>()) {}

  ~MpvTexture() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      quit_ = true;
    }
    cv_.notify_all();
    if (thread_.joinable()) thread_.join();
    if (ctx_) {
      mpv_render_context_set_update_callback(ctx_, nullptr, nullptr);
      mpv_render_context_free(ctx_);
      ctx_ = nullptr;
    }
    if (texture_) {
      fl_texture_registrar_unregister_texture(registrar_, FL_TEXTURE(texture_));
      g_object_unref(texture_);
    }
  }

  bool Start(mpv_handle* mpv, int width, int height) {
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(MPV_RENDER_API_TYPE_SW)},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    if (mpv_render_context_create(&ctx_, mpv, params) < 0) {
      ctx_ = nullptr;
      return false;
    }
    SetSize(width, height);

    texture_ = ZERK_MPV_TEXTURE(g_object_new(zerk_mpv_texture_get_type(), nullptr));
    texture_->store = new std::shared_ptr<FrameStore>(store_);
    if (!fl_texture_registrar_register_texture(registrar_, FL_TEXTURE(texture_))) {
      g_clear_object(&texture_);
      return false;
    }
    id_ = fl_texture_get_id(FL_TEXTURE(texture_));

    thread_ = std::thread([this] { RenderLoop(); });
    mpv_render_context_set_update_callback(ctx_, [](void* self) { static_cast<MpvTexture*>(self)->Wake(false); }, this);
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

 private:
  void Wake(bool force) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      pending_ = true;
      if (force) force_ = true;
    }
    cv_.notify_one();
  }

  void RenderLoop() {
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
      const bool frame = (mpv_render_context_update(ctx_) & MPV_RENDER_UPDATE_FRAME) != 0;
      if (!frame && !(force && has_frame_)) continue;

      int slot, w, h;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        w = width_;
        h = height_;
      }
      {
        std::lock_guard<std::mutex> lock(store_->mutex);
        slot = 0;
        while (slot == store_->latest || slot == store_->reading) slot++;
      }
      Frame& f = store_->frames[slot];
      if (f.width != w || f.height != h) {
        f.pixels.assign(static_cast<size_t>(w) * h * 4, 0);
        f.width = w;
        f.height = h;
      }
      int size[2] = {w, h};
      size_t stride = static_cast<size_t>(w) * 4;
      char format[] = "rgba";
      mpv_render_param params[] = {
          {MPV_RENDER_PARAM_SW_SIZE, size},
          {MPV_RENDER_PARAM_SW_FORMAT, format},
          {MPV_RENDER_PARAM_SW_STRIDE, &stride},
          {MPV_RENDER_PARAM_SW_POINTER, f.pixels.data()},
          {MPV_RENDER_PARAM_INVALID, nullptr},
      };
      if (mpv_render_context_render(ctx_, params) < 0) continue;
      has_frame_ = true;
      {
        std::lock_guard<std::mutex> lock(store_->mutex);
        store_->latest = slot;
      }
      fl_texture_registrar_mark_texture_frame_available(registrar_, FL_TEXTURE(texture_));
    }
  }

  FlTextureRegistrar* registrar_;
  std::shared_ptr<FrameStore> store_;
  ZerkMpvTexture* texture_ = nullptr;
  mpv_render_context* ctx_ = nullptr;
  int64_t id_ = -1;
  std::thread thread_;

  std::mutex mutex_;
  std::condition_variable cv_;
  bool pending_ = false;
  bool force_ = false;
  bool quit_ = false;
  int width_ = 0;
  int height_ = 0;
  bool has_frame_ = false;
};

static gboolean zerk_mpv_texture_copy_pixels(FlPixelBufferTexture* texture, const uint8_t** buffer, uint32_t* width,
                                             uint32_t* height, GError**) {
  static const uint8_t kTransparent[4] = {0, 0, 0, 0};
  auto* self = ZERK_MPV_TEXTURE(texture);
  if (self->store) {
    FrameStore& store = **self->store;
    std::lock_guard<std::mutex> lock(store.mutex);
    if (store.latest >= 0) {
      store.reading = store.latest;
      const Frame& f = store.frames[store.reading];
      *buffer = f.pixels.data();
      *width = static_cast<uint32_t>(f.width);
      *height = static_cast<uint32_t>(f.height);
      return TRUE;
    }
  }
  *buffer = kTransparent;
  *width = 1;
  *height = 1;
  return TRUE;
}

TrailerTextures::TrailerTextures(FlBinaryMessenger* messenger, FlTextureRegistrar* registrar)
    : registrar_(registrar) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(messenger, "zerk/trailer", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, OnMethodCall, this, nullptr);
}

TrailerTextures::~TrailerTextures() {
  fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr, nullptr);
  g_object_unref(channel_);
  textures_.clear();
}

void TrailerTextures::OnMethodCall(FlMethodChannel*, FlMethodCall* call, gpointer user_data) {
  auto* self = static_cast<TrailerTextures*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new("args", "expected a map", nullptr));
  } else if (strcmp(method, "create") == 0) {
    auto texture = std::make_unique<MpvTexture>(self->registrar_);
    auto* mpv = reinterpret_cast<mpv_handle*>(static_cast<intptr_t>(ArgInt(args, "handle")));
    const int width = static_cast<int>(ArgInt(args, "width"));
    const int height = static_cast<int>(ArgInt(args, "height"));
    if (!mpv || !texture->Start(mpv, width, height)) {
      response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("render", "could not create an mpv render context", nullptr));
    } else {
      const int64_t id = texture->id();
      self->textures_[id] = std::move(texture);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_int(id)));
    }
  } else if (strcmp(method, "resize") == 0) {
    auto it = self->textures_.find(ArgInt(args, "id"));
    if (it != self->textures_.end()) {
      it->second->SetSize(static_cast<int>(ArgInt(args, "width")), static_cast<int>(ArgInt(args, "height")));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "dispose") == 0) {
    self->textures_.erase(ArgInt(args, "id"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}
