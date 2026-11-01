#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"
#include "native_window.h"
#include "trailer_texture.h"
#include "video_host.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  VideoHost* video_host;
  NativeWindow* native_window;
  TrailerTextures* trailer_textures;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void release_native(MyApplication* self) {
  delete self->trailer_textures;
  self->trailer_textures = nullptr;
  delete self->native_window;
  self->native_window = nullptr;
  if (self->video_host) self->video_host->Release();
}

static void window_destroy_cb(GtkWidget*, MyApplication* self) { release_native(self); }

static gboolean focus_in_cb(GtkWidget*, GdkEvent*, MyApplication* self) {
  if (self->video_host) self->video_host->Focus();
  return FALSE;
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  gtk_window_set_title(window, "Zerk Play");
  gtk_window_set_icon_name(window, APPLICATION_ID);
  gtk_window_set_default_size(window, 1600, 900);
  GdkGeometry min_size = {};
  min_size.min_width = 960;
  min_size.min_height = 540;
  gtk_window_set_geometry_hints(window, nullptr, &min_size, GDK_HINT_MIN_SIZE);
  gtk_window_set_position(window, GTK_WIN_POS_CENTER);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#0B0B12");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));

  GtkWidget* overlay = gtk_overlay_new();
  gtk_widget_show(overlay);
  gtk_container_add(GTK_CONTAINER(overlay), GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), overlay);

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(view));

  FlPluginRegistry* registry = FL_PLUGIN_REGISTRY(view);
  fl_register_plugins(registry);

  g_autoptr(FlPluginRegistrar) registrar = fl_plugin_registry_get_registrar_for_plugin(registry, "ZerkRunner");
  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);
  self->video_host = new VideoHost(GTK_OVERLAY(overlay), GTK_WIDGET(view), messenger);
  self->native_window = new NativeWindow(window, messenger);
  self->trailer_textures = new TrailerTextures(messenger, fl_plugin_registrar_get_texture_registrar(registrar));
  g_signal_connect(window, "focus-in-event", G_CALLBACK(focus_in_cb), self);
  g_signal_connect(window, "destroy", G_CALLBACK(window_destroy_cb), self);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

static void my_application_shutdown(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  release_native(self);
  delete self->video_host;
  self->video_host = nullptr;
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);
  return MY_APPLICATION(g_object_new(my_application_get_type(), "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
