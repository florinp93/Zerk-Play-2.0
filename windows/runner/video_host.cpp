#include "video_host.h"

#include <flutter/standard_method_codec.h>

#include <string>
#include <vector>
#include <windowsx.h>

namespace {

constexpr wchar_t kClassName[] = L"ZERK_VIDEO_HOST";
constexpr UINT_PTR kCursorTimer = 1;
constexpr UINT kCursorHideMs = 1500;

const char* SpecialKeyName(WPARAM vk) {
  switch (vk) {
    case VK_LEFT: return "LEFT";
    case VK_RIGHT: return "RIGHT";
    case VK_UP: return "UP";
    case VK_DOWN: return "DOWN";
    case VK_RETURN: return "ENTER";
    case VK_ESCAPE: return "ESC";
    case VK_BACK: return "BS";
    case VK_SPACE: return "SPACE";
    case VK_TAB: return "TAB";
    case VK_HOME: return "HOME";
    case VK_END: return "END";
    case VK_PRIOR: return "PGUP";
    case VK_NEXT: return "PGDWN";
    case VK_DELETE: return "DEL";
    case VK_INSERT: return "INS";
    case VK_MEDIA_PLAY_PAUSE: return "PLAYPAUSE";
    case VK_MEDIA_STOP: return "STOP";
    case VK_MEDIA_NEXT_TRACK: return "NEXT";
    case VK_MEDIA_PREV_TRACK: return "PREV";
    case VK_VOLUME_MUTE: return "MUTE";
    case VK_VOLUME_DOWN: return "VOLUME_DOWN";
    case VK_VOLUME_UP: return "VOLUME_UP";
    case VK_BROWSER_BACK: return "ESC";
    case VK_NUMPAD0: return "KP0";
    case VK_NUMPAD1: return "KP1";
    case VK_NUMPAD2: return "KP2";
    case VK_NUMPAD3: return "KP3";
    case VK_NUMPAD4: return "KP4";
    case VK_NUMPAD5: return "KP5";
    case VK_NUMPAD6: return "KP6";
    case VK_NUMPAD7: return "KP7";
    case VK_NUMPAD8: return "KP8";
    case VK_NUMPAD9: return "KP9";
  }
  return nullptr;
}

std::string Modifiers(bool include_shift) {
  std::string m;
  if (GetKeyState(VK_CONTROL) & 0x8000) m += "ctrl+";
  if (GetKeyState(VK_MENU) & 0x8000) m += "alt+";
  if (include_shift && (GetKeyState(VK_SHIFT) & 0x8000)) m += "shift+";
  return m;
}

std::string Utf8(wchar_t c) {
  char buf[8] = {};
  int n = WideCharToMultiByte(CP_UTF8, 0, &c, 1, buf, sizeof(buf), nullptr, nullptr);
  return std::string(buf, n > 0 ? n : 0);
}

}

VideoHost::VideoHost(HWND parent, HWND flutter_view, flutter::BinaryMessenger* messenger)
    : parent_(parent), flutter_view_(flutter_view) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "zerk/video_host", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method == "create") {
      EnsureCreated();
      result->Success(flutter::EncodableValue(reinterpret_cast<int64_t>(hwnd_)));
    } else if (method == "show") {
      Show();
      result->Success();
    } else if (method == "hide") {
      Hide();
      result->Success();
    } else if (method == "focus") {
      Focus();
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
}

VideoHost::~VideoHost() {
  channel_->SetMethodCallHandler(nullptr);
  if (hwnd_) DestroyWindow(hwnd_);
}

void VideoHost::EnsureCreated() {
  if (hwnd_) return;
  static bool registered = false;
  if (!registered) {
    WNDCLASSEX wc = {};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
    wc.lpfnWndProc = VideoHost::WndProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    wc.lpszClassName = kClassName;
    RegisterClassEx(&wc);
    registered = true;
  }
  RECT rc;
  GetClientRect(parent_, &rc);
  hwnd_ = CreateWindowEx(0, kClassName, L"", WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
                         0, 0, rc.right - rc.left, rc.bottom - rc.top, parent_, nullptr,
                         GetModuleHandle(nullptr), this);
  SetWindowLongPtr(hwnd_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
}

void VideoHost::Show() {
  EnsureCreated();
  OnParentResized();
  SetWindowPos(hwnd_, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  Focus();
}

void VideoHost::Hide() {
  if (!hwnd_) return;
  ShowWindow(hwnd_, SW_HIDE);
  SetFocus(flutter_view_);
}

void VideoHost::OnParentResized() {
  if (!hwnd_) return;
  RECT rc;
  GetClientRect(parent_, &rc);
  MoveWindow(hwnd_, 0, 0, rc.right - rc.left, rc.bottom - rc.top, TRUE);
  if (HWND child = GetWindow(hwnd_, GW_CHILD)) {
    MoveWindow(child, 0, 0, rc.right - rc.left, rc.bottom - rc.top, TRUE);
  }
}

void VideoHost::Focus() {
  if (visible()) SetFocus(hwnd_);
}

void VideoHost::SendInput(std::initializer_list<std::string> args) {
  flutter::EncodableList list;
  for (const auto& a : args) list.emplace_back(a);
  channel_->InvokeMethod("input", std::make_unique<flutter::EncodableValue>(list));
}

void VideoHost::SendKey(const std::string& name) { SendInput({"keypress", name}); }

bool VideoHost::HandleMouseMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  const std::string x = std::to_string(GET_X_LPARAM(lparam));
  const std::string y = std::to_string(GET_Y_LPARAM(lparam));
  switch (message) {
    case WM_MOUSEMOVE:
      ShowCursorNow();
      SendInput({"mouse", x, y});
      return true;
    case WM_LBUTTONDOWN:
      SetFocus(hwnd_);
      SendInput({"mouse", x, y, "0", "single"});
      return true;
    case WM_LBUTTONDBLCLK:
      SendInput({"mouse", x, y, "0", "double"});
      return true;
    case WM_RBUTTONDOWN:
      SendInput({"mouse", x, y, "2", "single"});
      return true;
    case WM_MOUSEWHEEL:
      SendKey(GET_WHEEL_DELTA_WPARAM(wparam) > 0 ? "WHEEL_UP" : "WHEEL_DOWN");
      return true;
    case WM_XBUTTONDOWN:
      SendKey(GET_XBUTTON_WPARAM(wparam) == XBUTTON1 ? "MBTN_BACK" : "MBTN_FORWARD");
      return true;
    case WM_LBUTTONUP:
    case WM_RBUTTONUP:
    case WM_XBUTTONUP:
      return true;
  }
  return false;
}

void VideoHost::ShowCursorNow() {
  cursor_hidden_ = false;
  SetCursor(LoadCursor(nullptr, IDC_ARROW));
  SetTimer(hwnd_, kCursorTimer, kCursorHideMs, nullptr);
}

bool VideoHost::HandleKeyMessage(UINT message, WPARAM wparam) {
  switch (message) {
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN: {
      if (const char* special = SpecialKeyName(wparam)) {
        SendKey(Modifiers(true) + special);
        suppress_char_ = true;
        return true;
      }
      std::string mods = Modifiers(false);
      if (!mods.empty() && ((wparam >= 'A' && wparam <= 'Z') || (wparam >= '0' && wparam <= '9'))) {
        SendKey(mods + static_cast<char>(wparam >= 'A' && wparam <= 'Z' ? wparam - 'A' + 'a' : wparam));
        suppress_char_ = true;
        return true;
      }
      if (wparam >= VK_F1 && wparam <= VK_F24) {
        SendKey(Modifiers(true) + "F" + std::to_string(wparam - VK_F1 + 1));
        return true;
      }
      suppress_char_ = false;
      return message == WM_KEYDOWN;
    }
    case WM_CHAR:
    case WM_SYSCHAR: {
      if (suppress_char_) {
        suppress_char_ = false;
        return true;
      }
      wchar_t c = static_cast<wchar_t>(wparam);
      if (c < 0x20) return true;
      SendKey(c == L'#' ? std::string("SHARP") : Utf8(c));
      return true;
    }
    case WM_KEYUP:
    case WM_SYSKEYUP:
      return message == WM_KEYUP;
  }
  return false;
}

LRESULT CALLBACK VideoHost::WndProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<VideoHost*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  switch (message) {
    case WM_KEYDOWN:
    case WM_KEYUP:
    case WM_SYSKEYDOWN:
    case WM_SYSKEYUP:
    case WM_CHAR:
    case WM_SYSCHAR:
      if (self && self->HandleKeyMessage(message, wparam)) return 0;
      break;
    case WM_MOUSEMOVE:
    case WM_LBUTTONDOWN:
    case WM_LBUTTONUP:
    case WM_LBUTTONDBLCLK:
    case WM_RBUTTONDOWN:
    case WM_RBUTTONUP:
    case WM_MOUSEWHEEL:
    case WM_XBUTTONDOWN:
    case WM_XBUTTONUP:
      if (self && self->HandleMouseMessage(message, wparam, lparam)) return 0;
      break;
    case WM_TIMER:
      if (wparam == kCursorTimer && self) {
        KillTimer(hwnd, kCursorTimer);
        self->cursor_hidden_ = true;
        SetCursor(nullptr);
        return 0;
      }
      break;
    case WM_SETCURSOR:
      if (self && self->cursor_hidden_ && LOWORD(lparam) == HTCLIENT) {
        SetCursor(nullptr);
        return TRUE;
      }
      break;
    case WM_GETDLGCODE:
      return DLGC_WANTALLKEYS;
    case WM_ERASEBKGND: {
      RECT rc;
      GetClientRect(hwnd, &rc);
      FillRect(reinterpret_cast<HDC>(wparam), &rc, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
      return 1;
    }
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}
