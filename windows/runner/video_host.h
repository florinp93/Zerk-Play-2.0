#ifndef RUNNER_VIDEO_HOST_H_
#define RUNNER_VIDEO_HOST_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <initializer_list>
#include <memory>
#include <string>

class VideoHost {
 public:
  VideoHost(HWND parent, HWND flutter_view, flutter::BinaryMessenger* messenger);
  ~VideoHost();

  bool visible() const { return hwnd_ != nullptr && IsWindowVisible(hwnd_); }

  void OnParentResized();

  void Focus();

 private:
  void EnsureCreated();
  void Show();
  void Hide();
  void SendInput(std::initializer_list<std::string> args);
  void SendKey(const std::string& name);
  bool HandleMouseMessage(UINT message, WPARAM wparam, LPARAM lparam);
  void ShowCursorNow();

  bool HandleKeyMessage(UINT message, WPARAM wparam);

  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  HWND parent_;
  HWND flutter_view_;
  HWND hwnd_ = nullptr;
  bool suppress_char_ = false;
  bool cursor_hidden_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif
