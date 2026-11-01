#ifndef RUNNER_NATIVE_WINDOW_H_
#define RUNNER_NATIVE_WINDOW_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

class NativeWindow {
 public:
  NativeWindow(GtkWindow* window, FlBinaryMessenger* messenger);
  ~NativeWindow();

 private:
  static void OnMethodCall(FlMethodChannel* channel, FlMethodCall* call, gpointer user_data);
  static gboolean OnWindowState(GtkWidget* widget, GdkEventWindowState* event, gpointer user_data);

  GtkWindow* window_;
  FlMethodChannel* channel_;
  gulong state_handler_ = 0;
  bool fullscreen_ = false;
};

#endif
