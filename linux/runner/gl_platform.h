#ifndef RUNNER_GL_PLATFORM_H_
#define RUNNER_GL_PLATFORM_H_

#include <gdk/gdk.h>
#include <mpv/render_gl.h>

void* GlGetProcAddress(void* ctx, const char* name);

mpv_render_param GlDisplayParam(GdkDisplay* display);

#endif
