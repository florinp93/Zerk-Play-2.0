#ifndef RUNNER_TRAILER_TEXTURE_H_
#define RUNNER_TRAILER_TEXTURE_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter_plugin_registrar.h>
#include <flutter_texture_registrar.h>

#include <cstdint>
#include <map>
#include <memory>

class MpvTexture;

class TrailerTextures {
 public:
  TrailerTextures(flutter::BinaryMessenger* messenger, FlutterDesktopTextureRegistrarRef registrar);
  ~TrailerTextures();

 private:
  FlutterDesktopTextureRegistrarRef registrar_;
  std::map<int64_t, std::shared_ptr<MpvTexture>> textures_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif
