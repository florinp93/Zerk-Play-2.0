#include "native_window.h"

#include <cstring>

NativeWindow::NativeWindow(GtkWindow* window, FlBinaryMessenger* messenger) : window_(window) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(messenger, "zerk/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, OnMethodCall, this, nullptr);
  state_handler_ = g_signal_connect(window_, "window-state-event", G_CALLBACK(OnWindowState), this);
}

NativeWindow::~NativeWindow() {
  fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr, nullptr);
  g_object_unref(channel_);
  if (state_handler_) g_signal_handler_disconnect(window_, state_handler_);
}

gboolean NativeWindow::OnWindowState(GtkWidget*, GdkEventWindowState* event, gpointer user_data) {
  auto* self = static_cast<NativeWindow*>(user_data);
  self->fullscreen_ = (event->new_window_state & GDK_WINDOW_STATE_FULLSCREEN) != 0;
  return FALSE;
}

void NativeWindow::OnMethodCall(FlMethodChannel*, FlMethodCall* call, gpointer user_data) {
  auto* self = static_cast<NativeWindow*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "isFullScreen") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(self->fullscreen_)));
  } else if (strcmp(method, "setFullScreen") == 0 && args && fl_value_get_type(args) == FL_VALUE_TYPE_BOOL) {
    const bool fullscreen = fl_value_get_bool(args);
    if (fullscreen) {
      gtk_window_fullscreen(self->window_);
    } else {
      gtk_window_unfullscreen(self->window_);
    }
    self->fullscreen_ = fullscreen;
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "hdrStatus") == 0) {
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "supported", fl_value_new_bool(false));
    fl_value_set_string_take(map, "enabled", fl_value_new_bool(false));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
  } else if (strcmp(method, "setHdr") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(false)));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}
