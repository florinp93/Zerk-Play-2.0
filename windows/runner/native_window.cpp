#include "native_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <vector>

namespace {

constexpr int kGetAdvancedColorInfo = 9;
constexpr int kSetAdvancedColorState = 10;
constexpr int kGetAdvancedColorInfo2 = 15;
constexpr int kSetHdrState = 16;

struct AdvancedColorInfo {
  DISPLAYCONFIG_DEVICE_INFO_HEADER header;
  UINT32 flags;
  UINT32 color_encoding;
  UINT32 bits_per_color_channel;
};

struct AdvancedColorInfo2 {
  DISPLAYCONFIG_DEVICE_INFO_HEADER header;
  UINT32 flags;
  UINT32 color_encoding;
  UINT32 bits_per_color_channel;
  UINT32 active_color_mode;
};

struct SetColorState {
  DISPLAYCONFIG_DEVICE_INFO_HEADER header;
  UINT32 flags;
};

struct Target {
  LUID adapter;
  UINT32 id;
};

std::optional<Target> TargetFor(HWND window) {
  MONITORINFOEXW mi = {};
  mi.cbSize = sizeof(mi);
  if (!GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &mi)) return std::nullopt;

  UINT32 path_count = 0, mode_count = 0;
  if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &path_count, &mode_count) != ERROR_SUCCESS) {
    return std::nullopt;
  }
  std::vector<DISPLAYCONFIG_PATH_INFO> paths(path_count);
  std::vector<DISPLAYCONFIG_MODE_INFO> modes(mode_count);
  if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &path_count, paths.data(), &mode_count, modes.data(),
                         nullptr) != ERROR_SUCCESS) {
    return std::nullopt;
  }
  for (UINT32 i = 0; i < path_count; i++) {
    const auto& path = paths[i];
    DISPLAYCONFIG_SOURCE_DEVICE_NAME source = {};
    source.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
    source.header.size = sizeof(source);
    source.header.adapterId = path.sourceInfo.adapterId;
    source.header.id = path.sourceInfo.id;
    if (DisplayConfigGetDeviceInfo(&source.header) != ERROR_SUCCESS) continue;
    if (wcscmp(source.viewGdiDeviceName, mi.szDevice) == 0) {
      return Target{path.targetInfo.adapterId, path.targetInfo.id};
    }
  }
  return std::nullopt;
}

template <typename T>
void InitHeader(T& info, int type, const Target& target) {
  info.header.type = static_cast<DISPLAYCONFIG_DEVICE_INFO_TYPE>(type);
  info.header.size = sizeof(T);
  info.header.adapterId = target.adapter;
  info.header.id = target.id;
}

}

NativeWindow::NativeWindow(HWND window, flutter::BinaryMessenger* messenger) : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "zerk/window", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto& method = call.method_name();
    const auto* arg = std::get_if<bool>(call.arguments());
    if (method == "isFullScreen") {
      result->Success(flutter::EncodableValue(fullscreen_));
    } else if (method == "setFullScreen" && arg) {
      SetFullScreen(*arg);
      result->Success();
    } else if (method == "hdrStatus") {
      const auto status = GetHdrStatus();
      result->Success(flutter::EncodableValue(flutter::EncodableMap{
          {flutter::EncodableValue("supported"), flutter::EncodableValue(status.supported)},
          {flutter::EncodableValue("enabled"), flutter::EncodableValue(status.enabled)},
      }));
    } else if (method == "setHdr" && arg) {
      result->Success(flutter::EncodableValue(SetHdr(*arg)));
    } else {
      result->NotImplemented();
    }
  });
}

NativeWindow::~NativeWindow() {
  channel_->SetMethodCallHandler(nullptr);
  if (hdr_enabled_by_app_) SetHdr(false);
}

void NativeWindow::SetFullScreen(bool fullscreen) {
  if (fullscreen == fullscreen_) return;
  if (fullscreen) {
    MONITORINFO mi = {sizeof(mi)};
    if (!GetMonitorInfo(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST), &mi)) return;
    saved_placement_.length = sizeof(saved_placement_);
    GetWindowPlacement(window_, &saved_placement_);
    saved_style_ = GetWindowLongPtr(window_, GWL_STYLE);
    SetWindowLongPtr(window_, GWL_STYLE, saved_style_ & ~(WS_OVERLAPPEDWINDOW | WS_MAXIMIZE));
    const RECT& rc = mi.rcMonitor;
    SetWindowPos(window_, HWND_TOP, rc.left, rc.top, rc.right - rc.left, rc.bottom - rc.top,
                 SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  } else {
    SetWindowLongPtr(window_, GWL_STYLE, (saved_style_ | WS_OVERLAPPEDWINDOW) & ~WS_MAXIMIZE);
    SetWindowPlacement(window_, &saved_placement_);
    SetWindowPos(window_, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  }
  fullscreen_ = fullscreen;
}

NativeWindow::HdrStatus NativeWindow::GetHdrStatus() const {
  HdrStatus status;
  const auto target = TargetFor(window_);
  if (!target) return status;

  AdvancedColorInfo2 info2 = {};
  InitHeader(info2, kGetAdvancedColorInfo2, *target);
  if (DisplayConfigGetDeviceInfo(&info2.header) == ERROR_SUCCESS) {
    status.supported = (info2.flags & (1u << 4)) != 0;
    status.enabled = info2.active_color_mode == 2;
    return status;
  }
  AdvancedColorInfo info = {};
  InitHeader(info, kGetAdvancedColorInfo, *target);
  if (DisplayConfigGetDeviceInfo(&info.header) == ERROR_SUCCESS) {
    const bool wide_color_only = (info.flags & (1u << 2)) != 0;
    status.supported = (info.flags & 1u) != 0 && !wide_color_only;
    status.enabled = (info.flags & (1u << 1)) != 0 && !wide_color_only;
  }
  return status;
}

bool NativeWindow::SetHdr(bool enabled) {
  const auto target = TargetFor(window_);
  if (!target) return false;
  const auto before = GetHdrStatus();
  if (!before.supported) return false;
  if (before.enabled == enabled) {
    if (!enabled) hdr_enabled_by_app_ = false;
    return true;
  }

  SetColorState state = {};
  InitHeader(state, kSetHdrState, *target);
  state.flags = enabled ? 1u : 0u;
  LONG rc = DisplayConfigSetDeviceInfo(&state.header);
  if (rc != ERROR_SUCCESS) {
    InitHeader(state, kSetAdvancedColorState, *target);
    rc = DisplayConfigSetDeviceInfo(&state.header);
  }
  if (rc != ERROR_SUCCESS) return false;
  hdr_enabled_by_app_ = enabled;
  return true;
}
