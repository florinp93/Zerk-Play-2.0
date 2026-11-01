#include "video_host.h"

#include <epoxy/gl.h>
#include <gdk/gdk.h>
#include <gdk/gdkkeysyms.h>

#include "gl_platform.h"

#include <cmath>
#include <cstring>

namespace {

constexpr guint kCursorHideMs = 1500;

const char* SpecialKeyName(guint keyval) {
  switch (keyval) {
    case GDK_KEY_Left: return "LEFT";
    case GDK_KEY_Right: return "RIGHT";
    case GDK_KEY_Up: return "UP";
    case GDK_KEY_Down: return "DOWN";
    case GDK_KEY_Return:
    case GDK_KEY_KP_Enter:
    case GDK_KEY_ISO_Enter: return "ENTER";
    case GDK_KEY_Escape: return "ESC";
    case GDK_KEY_BackSpace: return "BS";
    case GDK_KEY_space: return "SPACE";
    case GDK_KEY_Tab:
    case GDK_KEY_ISO_Left_Tab: return "TAB";
    case GDK_KEY_Home: return "HOME";
    case GDK_KEY_End: return "END";
    case GDK_KEY_Page_Up: return "PGUP";
    case GDK_KEY_Page_Down: return "PGDWN";
    case GDK_KEY_Delete: return "DEL";
    case GDK_KEY_Insert: return "INS";
    case GDK_KEY_AudioPlay:
    case GDK_KEY_AudioPause: return "PLAYPAUSE";
    case GDK_KEY_AudioStop: return "STOP";
    case GDK_KEY_AudioNext: return "NEXT";
    case GDK_KEY_AudioPrev: return "PREV";
    case GDK_KEY_AudioMute: return "MUTE";
    case GDK_KEY_AudioLowerVolume: return "VOLUME_DOWN";
    case GDK_KEY_AudioRaiseVolume: return "VOLUME_UP";
    case GDK_KEY_Back: return "ESC";
    case GDK_KEY_KP_0: return "KP0";
    case GDK_KEY_KP_1: return "KP1";
    case GDK_KEY_KP_2: return "KP2";
    case GDK_KEY_KP_3: return "KP3";
    case GDK_KEY_KP_4: return "KP4";
    case GDK_KEY_KP_5: return "KP5";
    case GDK_KEY_KP_6: return "KP6";
    case GDK_KEY_KP_7: return "KP7";
    case GDK_KEY_KP_8: return "KP8";
    case GDK_KEY_KP_9: return "KP9";
  }
  return nullptr;
}

std::string Modifiers(guint state, bool include_shift) {
  std::string m;
  if (state & GDK_CONTROL_MASK) m += "ctrl+";
  if (state & GDK_MOD1_MASK) m += "alt+";
  if (include_shift && (state & GDK_SHIFT_MASK)) m += "shift+";
  return m;
}

bool IsModifierKey(guint keyval) {
  switch (keyval) {
    case GDK_KEY_Shift_L:
    case GDK_KEY_Shift_R:
    case GDK_KEY_Control_L:
    case GDK_KEY_Control_R:
    case GDK_KEY_Alt_L:
    case GDK_KEY_Alt_R:
    case GDK_KEY_Meta_L:
    case GDK_KEY_Meta_R:
    case GDK_KEY_Super_L:
    case GDK_KEY_Super_R:
    case GDK_KEY_Caps_Lock:
    case GDK_KEY_Num_Lock:
    case GDK_KEY_ISO_Level3_Shift:
      return true;
  }
  return false;
}

}

VideoHost::VideoHost(GtkOverlay* overlay, GtkWidget* flutter_view, FlBinaryMessenger* messenger)
    : flutter_view_(flutter_view) {
  area_ = gtk_gl_area_new();
  g_object_ref_sink(area_);
  gtk_gl_area_set_has_alpha(GTK_GL_AREA(area_), FALSE);
  gtk_gl_area_set_auto_render(GTK_GL_AREA(area_), FALSE);
  gtk_widget_set_can_focus(area_, TRUE);
  gtk_widget_set_hexpand(area_, TRUE);
  gtk_widget_set_vexpand(area_, TRUE);
  gtk_widget_add_events(area_, GDK_KEY_PRESS_MASK | GDK_BUTTON_PRESS_MASK | GDK_POINTER_MOTION_MASK |
                                   GDK_SCROLL_MASK | GDK_SMOOTH_SCROLL_MASK);
  g_signal_connect(area_, "render", G_CALLBACK(OnRender), this);
  g_signal_connect(area_, "unrealize", G_CALLBACK(OnUnrealize), this);
  g_signal_connect(area_, "key-press-event", G_CALLBACK(OnKeyPress), this);
  g_signal_connect(area_, "button-press-event", G_CALLBACK(OnButtonPress), this);
  g_signal_connect(area_, "motion-notify-event", G_CALLBACK(OnMotion), this);
  g_signal_connect(area_, "scroll-event", G_CALLBACK(OnScroll), this);
  gtk_overlay_add_overlay(overlay, area_);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(messenger, "zerk/video_host", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, OnMethodCall, this, nullptr);
}

VideoHost::~VideoHost() {
  Release();
  fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr, nullptr);
  g_object_unref(channel_);
  g_object_unref(area_);
}

void VideoHost::Release() {
  if (cursor_timer_) {
    g_source_remove(cursor_timer_);
    cursor_timer_ = 0;
  }
  Detach();
  g_signal_handlers_disconnect_by_data(area_, this);
}

void VideoHost::OnMethodCall(FlMethodChannel*, FlMethodCall* call, gpointer user_data) {
  auto* self = static_cast<VideoHost*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "attach") == 0 && args && fl_value_get_type(args) == FL_VALUE_TYPE_INT) {
    auto* mpv = reinterpret_cast<mpv_handle*>(static_cast<intptr_t>(fl_value_get_int(args)));
    if (self->Attach(mpv)) {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
      response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("render", "could not create an mpv render context", nullptr));
    }
  } else if (strcmp(method, "detach") == 0) {
    self->Detach();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "show") == 0) {
    self->Show();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "hide") == 0) {
    self->Hide();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "focus") == 0) {
    self->Focus();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

bool VideoHost::Attach(mpv_handle* mpv) {
  Detach();
  if (!mpv) return false;
  gtk_widget_realize(area_);
  gtk_gl_area_make_current(GTK_GL_AREA(area_));
  if (GError* error = gtk_gl_area_get_error(GTK_GL_AREA(area_))) {
    g_warning("video host: no GL context: %s", error->message);
    return false;
  }

  mpv_opengl_init_params gl_init = {GlGetProcAddress, nullptr};
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(MPV_RENDER_API_TYPE_OPENGL)},
      {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl_init},
      GlDisplayParam(gtk_widget_get_display(area_)),
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  if (mpv_render_context_create(&ctx_, mpv, params) < 0) {
    ctx_ = nullptr;
    return false;
  }
  mpv_render_context_set_update_callback(ctx_, OnMpvUpdate, this);
  ConnectFrameClock();
  return true;
}

void VideoHost::Detach() {
  if (!ctx_) return;
  mpv_render_context_set_update_callback(ctx_, nullptr, nullptr);
  gtk_gl_area_make_current(GTK_GL_AREA(area_));
  mpv_render_context_free(ctx_);
  ctx_ = nullptr;
  rendered_ = false;
  if (after_paint_handler_) {
    g_signal_handler_disconnect(frame_clock_, after_paint_handler_);
    after_paint_handler_ = 0;
    frame_clock_ = nullptr;
  }
}

void VideoHost::OnUnrealize(GtkWidget*, gpointer user_data) { static_cast<VideoHost*>(user_data)->Detach(); }

void VideoHost::ConnectFrameClock() {
  if (after_paint_handler_) return;
  frame_clock_ = gtk_widget_get_frame_clock(area_);
  if (!frame_clock_) return;
  after_paint_handler_ = g_signal_connect(frame_clock_, "after-paint", G_CALLBACK(OnAfterPaint), this);
}

void VideoHost::OnMpvUpdate(void* user_data) {
  auto* self = static_cast<VideoHost*>(user_data);
  if (self->update_pending_.exchange(true)) return;
  g_idle_add_full(G_PRIORITY_HIGH_IDLE, OnUpdateIdle, self, nullptr);
}

gboolean VideoHost::OnUpdateIdle(gpointer user_data) {
  auto* self = static_cast<VideoHost*>(user_data);
  self->update_pending_ = false;
  if (!self->ctx_) return G_SOURCE_REMOVE;
  if ((mpv_render_context_update(self->ctx_) & MPV_RENDER_UPDATE_FRAME) == 0) return G_SOURCE_REMOVE;
  if (gtk_widget_get_mapped(self->area_)) {
    gtk_gl_area_queue_render(GTK_GL_AREA(self->area_));
  } else {
    gtk_gl_area_make_current(GTK_GL_AREA(self->area_));
    int skip = 1;
    mpv_render_param params[] = {{MPV_RENDER_PARAM_SKIP_RENDERING, &skip}, {MPV_RENDER_PARAM_INVALID, nullptr}};
    mpv_render_context_render(self->ctx_, params);
  }
  return G_SOURCE_REMOVE;
}

gboolean VideoHost::OnRender(GtkGLArea* area, GdkGLContext*, gpointer user_data) {
  auto* self = static_cast<VideoHost*>(user_data);
  if (!self->ctx_) {
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    return TRUE;
  }
  GLint fbo = 0;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &fbo);
  const int scale = gtk_widget_get_scale_factor(GTK_WIDGET(area));
  mpv_opengl_fbo target = {fbo, gtk_widget_get_allocated_width(GTK_WIDGET(area)) * scale,
                           gtk_widget_get_allocated_height(GTK_WIDGET(area)) * scale, 0};
  int flip_y = 1;
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_OPENGL_FBO, &target},
      {MPV_RENDER_PARAM_FLIP_Y, &flip_y},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  mpv_render_context_render(self->ctx_, params);
  self->rendered_ = true;
  return TRUE;
}

void VideoHost::OnAfterPaint(GdkFrameClock*, gpointer user_data) {
  auto* self = static_cast<VideoHost*>(user_data);
  if (!self->ctx_ || !self->rendered_) return;
  self->rendered_ = false;
  mpv_render_context_report_swap(self->ctx_);
}

void VideoHost::Show() {
  gtk_widget_show(area_);
  ConnectFrameClock();
  gtk_gl_area_queue_render(GTK_GL_AREA(area_));
  Focus();
  ShowCursorNow();
}

void VideoHost::Hide() {
  if (cursor_timer_) {
    g_source_remove(cursor_timer_);
    cursor_timer_ = 0;
  }
  SetCursorHidden(false);
  gtk_widget_hide(area_);
  gtk_widget_grab_focus(flutter_view_);
}

void VideoHost::Focus() {
  if (visible()) gtk_widget_grab_focus(area_);
}

void VideoHost::SendInput(std::initializer_list<std::string> args) {
  g_autoptr(FlValue) list = fl_value_new_list();
  for (const auto& a : args) fl_value_append_take(list, fl_value_new_string(a.c_str()));
  fl_method_channel_invoke_method(channel_, "input", list, nullptr, nullptr, nullptr);
}

void VideoHost::SendKey(const std::string& name) { SendInput({"keypress", name}); }

void VideoHost::SetCursorHidden(bool hidden) {
  cursor_hidden_ = hidden;
  GdkWindow* window = gtk_widget_get_window(area_);
  if (!window) return;
  if (hidden) {
    g_autoptr(GdkCursor) cursor = gdk_cursor_new_from_name(gtk_widget_get_display(area_), "none");
    gdk_window_set_cursor(window, cursor);
  } else {
    gdk_window_set_cursor(window, nullptr);
  }
}

void VideoHost::ShowCursorNow() {
  if (cursor_hidden_) SetCursorHidden(false);
  if (cursor_timer_) g_source_remove(cursor_timer_);
  cursor_timer_ = g_timeout_add(kCursorHideMs, OnCursorTimer, this);
}

gboolean VideoHost::OnCursorTimer(gpointer user_data) {
  auto* self = static_cast<VideoHost*>(user_data);
  self->cursor_timer_ = 0;
  self->SetCursorHidden(true);
  return G_SOURCE_REMOVE;
}

gboolean VideoHost::OnKeyPress(GtkWidget*, GdkEventKey* event, gpointer user_data) {
  auto* self = static_cast<VideoHost*>(user_data);
  const guint keyval = event->keyval;
  if (IsModifierKey(keyval)) return TRUE;
  if (const char* special = SpecialKeyName(keyval)) {
    self->SendKey(Modifiers(event->state, true) + special);
    return TRUE;
  }
  if (keyval >= GDK_KEY_F1 && keyval <= GDK_KEY_F24) {
    self->SendKey(Modifiers(event->state, true) + "F" + std::to_string(keyval - GDK_KEY_F1 + 1));
    return TRUE;
  }
  const std::string mods = Modifiers(event->state, false);
  const guint lower = gdk_keyval_to_lower(keyval);
  if (!mods.empty() && ((lower >= GDK_KEY_a && lower <= GDK_KEY_z) || (lower >= GDK_KEY_0 && lower <= GDK_KEY_9))) {
    self->SendKey(mods + static_cast<char>(lower));
    return TRUE;
  }
  const gunichar c = gdk_keyval_to_unicode(keyval);
  if (c < 0x20) return TRUE;
  if (c == '#') {
    self->SendKey("SHARP");
    return TRUE;
  }
  char buf[8] = {};
  const int n = g_unichar_to_utf8(c, buf);
  self->SendKey(std::string(buf, n));
  return TRUE;
}

gboolean VideoHost::OnButtonPress(GtkWidget* widget, GdkEventButton* event, gpointer user_data) {
  auto* self = static_cast<VideoHost*>(user_data);
  const int scale = gtk_widget_get_scale_factor(widget);
  const std::string x = std::to_string(static_cast<int>(event->x * scale));
  const std::string y = std::to_string(static_cast<int>(event->y * scale));
  if (event->type == GDK_2BUTTON_PRESS) {
    if (event->button == 1) self->SendInput({"mouse", x, y, "0", "double"});
    return TRUE;
  }
  if (event->type != GDK_BUTTON_PRESS) return TRUE;
  switch (event->button) {
    case 1:
      gtk_widget_grab_focus(widget);
      self->SendInput({"mouse", x, y, "0", "single"});
      break;
    case 3:
      self->SendInput({"mouse", x, y, "2", "single"});
      break;
    case 8:
      self->SendKey("MBTN_BACK");
      break;
    case 9:
      self->SendKey("MBTN_FORWARD");
      break;
  }
  return TRUE;
}

gboolean VideoHost::OnMotion(GtkWidget* widget, GdkEventMotion* event, gpointer user_data) {
  auto* self = static_cast<VideoHost*>(user_data);
  const int scale = gtk_widget_get_scale_factor(widget);
  self->ShowCursorNow();
  self->SendInput({"mouse", std::to_string(static_cast<int>(event->x * scale)),
                   std::to_string(static_cast<int>(event->y * scale))});
  return TRUE;
}

gboolean VideoHost::OnScroll(GtkWidget*, GdkEventScroll* event, gpointer user_data) {
  auto* self = static_cast<VideoHost*>(user_data);
  switch (event->direction) {
    case GDK_SCROLL_UP:
      self->SendKey("WHEEL_UP");
      break;
    case GDK_SCROLL_DOWN:
      self->SendKey("WHEEL_DOWN");
      break;
    case GDK_SCROLL_SMOOTH:
      self->scroll_accum_ += event->delta_y;
      while (std::fabs(self->scroll_accum_) >= 1.0) {
        self->SendKey(self->scroll_accum_ < 0 ? "WHEEL_UP" : "WHEEL_DOWN");
        self->scroll_accum_ += self->scroll_accum_ < 0 ? 1.0 : -1.0;
      }
      break;
    default:
      break;
  }
  return TRUE;
}
