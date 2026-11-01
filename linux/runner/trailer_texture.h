#ifndef RUNNER_TRAILER_TEXTURE_H_
#define RUNNER_TRAILER_TEXTURE_H_

#include <flutter_linux/flutter_linux.h>

#include <cstdint>
#include <map>
#include <memory>

class MpvTexture;

class TrailerTextures {
 public:
  TrailerTextures(FlBinaryMessenger* messenger, FlTextureRegistrar* registrar);
  ~TrailerTextures();

 private:
  static void OnMethodCall(FlMethodChannel* channel, FlMethodCall* call, gpointer user_data);

  FlTextureRegistrar* registrar_;
  std::map<int64_t, std::unique_ptr<MpvTexture>> textures_;
  FlMethodChannel* channel_;
};

#endif
