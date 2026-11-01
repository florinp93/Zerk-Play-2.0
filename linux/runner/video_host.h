#ifndef RUNNER_VIDEO_HOST_H_
#define RUNNER_VIDEO_HOST_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <mpv/render_gl.h>

#include <atomic>
#include <initializer_list>
#include <string>

class VideoHost {
 public:
  VideoHost(GtkOverlay* overlay, GtkWidget* flutter_view, FlBinaryMessenger* messenger);
  ~VideoHost();

  bool visible() const { return gtk_widget_get_visible(area_); }

  void Focus();

  void Release();

 private:
  bool Attach(mpv_handle* mpv);
  void Detach();
  void Show();
  void Hide();
  void SendInput(std::initializer_list<std::string> args);
  void SendKey(const std::string& name);
  void ShowCursorNow();
  void SetCursorHidden(bool hidden);
  void ConnectFrameClock();

  static void OnMethodCall(FlMethodChannel* channel, FlMethodCall* call, gpointer user_data);
  static gboolean OnRender(GtkGLArea* area, GdkGLContext* context, gpointer user_data);
  static void OnUnrealize(GtkWidget* widget, gpointer user_data);
  static void OnMpvUpdate(void* user_data);
  static gboolean OnUpdateIdle(gpointer user_data);
  static void OnAfterPaint(GdkFrameClock* clock, gpointer user_data);
  static gboolean OnKeyPress(GtkWidget* widget, GdkEventKey* event, gpointer user_data);
  static gboolean OnButtonPress(GtkWidget* widget, GdkEventButton* event, gpointer user_data);
  static gboolean OnMotion(GtkWidget* widget, GdkEventMotion* event, gpointer user_data);
  static gboolean OnScroll(GtkWidget* widget, GdkEventScroll* event, gpointer user_data);
  static gboolean OnCursorTimer(gpointer user_data);

  GtkWidget* area_;
  GtkWidget* flutter_view_;
  FlMethodChannel* channel_;
  mpv_render_context* ctx_ = nullptr;
  std::atomic<bool> update_pending_{false};
  GdkFrameClock* frame_clock_ = nullptr;
  gulong after_paint_handler_ = 0;
  bool rendered_ = false;
  guint cursor_timer_ = 0;
  bool cursor_hidden_ = false;
  double scroll_accum_ = 0;
};

#endif
