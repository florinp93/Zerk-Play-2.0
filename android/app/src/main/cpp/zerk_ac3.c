#include <jni.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "aften.h"

#define FRAME_SAMPLES 1536
#define OUT_CHANNELS 6

typedef struct {
    AftenContext ctx;
    float pcm[FRAME_SAMPLES * OUT_CHANNELS];
} ZerkAc3;

static float clampf(float v) { return v > 1.0f ? 1.0f : (v < -1.0f ? -1.0f : v); }

JNIEXPORT jlong JNICALL
Java_cloud_zerk_play_Ac3Encoder_nativeOpen(JNIEnv *env, jclass cls, jint sampleRate, jint bitrateKbps) {
    ZerkAc3 *z = calloc(1, sizeof(ZerkAc3));
    if (!z) return 0;
    aften_set_defaults(&z->ctx);
    z->ctx.verbose = 0;
    z->ctx.channels = OUT_CHANNELS;
    z->ctx.acmod = 7;
    z->ctx.lfe = 1;
    z->ctx.samplerate = sampleRate;
    z->ctx.sample_format = A52_SAMPLE_FMT_FLT;
    z->ctx.params.bitrate = bitrateKbps;
    z->ctx.system.n_threads = 1;
    if (aften_encode_init(&z->ctx) != 0) {
        free(z);
        return 0;
    }
    return (jlong) (intptr_t) z;
}

JNIEXPORT jint JNICALL
Java_cloud_zerk_play_Ac3Encoder_nativeEncode(JNIEnv *env, jclass cls, jlong handle, jobject pcm, jint channels,
                                             jboolean isFloat, jobject out) {
    ZerkAc3 *z = (ZerkAc3 *) (intptr_t) handle;
    const void *src = (*env)->GetDirectBufferAddress(env, pcm);
    uint8_t *dst = (*env)->GetDirectBufferAddress(env, out);
    if (!z || !src || !dst || (channels != 6 && channels != 8)) return -1;

    const float k = 0.70710678f;
    for (int i = 0; i < FRAME_SAMPLES; i++) {
        float in[8];
        for (int c = 0; c < channels; c++) {
            in[c] = isFloat ? ((const float *) src)[i * channels + c]
                            : ((const int16_t *) src)[i * channels + c] / 32768.0f;
        }
        float ls = in[4], rs = in[5];
        if (channels == 8) {
            ls = clampf((in[4] + in[6]) * k);
            rs = clampf((in[5] + in[7]) * k);
        }
        float *o = &z->pcm[i * OUT_CHANNELS];
        o[0] = in[0];
        o[1] = in[2];
        o[2] = in[1];
        o[3] = ls;
        o[4] = rs;
        o[5] = in[3];
    }
    return aften_encode_frame(&z->ctx, dst, z->pcm);
}

JNIEXPORT void JNICALL
Java_cloud_zerk_play_Ac3Encoder_nativeClose(JNIEnv *env, jclass cls, jlong handle) {
    ZerkAc3 *z = (ZerkAc3 *) (intptr_t) handle;
    if (!z) return;
    aften_encode_close(&z->ctx);
    free(z);
}
