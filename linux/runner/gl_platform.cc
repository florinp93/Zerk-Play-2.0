#include "gl_platform.h"

#ifdef GDK_WINDOWING_X11
#include <epoxy/glx.h>
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <epoxy/egl.h>
#include <gdk/gdkwayland.h>
#endif

namespace {

bool g_use_egl = false;

}

void* GlGetProcAddress(void*, const char* name) {
#ifdef GDK_WINDOWING_WAYLAND
  if (g_use_egl) return reinterpret_cast<void*>(eglGetProcAddress(name));
#endif
#ifdef GDK_WINDOWING_X11
  return reinterpret_cast<void*>(glXGetProcAddressARB(reinterpret_cast<const GLubyte*>(name)));
#else
  return nullptr;
#endif
}

mpv_render_param GlDisplayParam(GdkDisplay* display) {
  g_use_egl = false;
#ifdef GDK_WINDOWING_WAYLAND
  if (GDK_IS_WAYLAND_DISPLAY(display)) {
    g_use_egl = true;
    return {MPV_RENDER_PARAM_WL_DISPLAY, gdk_wayland_display_get_wl_display(display)};
  }
#endif
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_DISPLAY(display)) return {MPV_RENDER_PARAM_X11_DISPLAY, gdk_x11_display_get_xdisplay(display)};
#endif
  return {MPV_RENDER_PARAM_INVALID, nullptr};
}
