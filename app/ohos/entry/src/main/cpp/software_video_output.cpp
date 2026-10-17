// SDL_Vout ABI from @ohos/ijkplayer 2.0.11 (Bilibili / Zhang Rui).
// SPDX-License-Identifier: LGPL-2.1-or-later
// A CPU producer avoids IJK's process-wide EGLDisplay teardown and lets Flutter
// compose the decoded frames using its ordinary texture path.
#include <native_window/external_window.h>
#include <native_buffer/native_buffer.h>
#include <hilog/log.h>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <poll.h>
#include <unistd.h>

extern "C" {
struct SDL_mutex;
struct SDL_Vout;
struct SDL_VoutOverlay {
    int w, h;
    uint32_t format;
    int planes;
    uint16_t *pitches;
    uint8_t **pixels;
};
struct SDL_Vout {
    SDL_mutex *mutex;
    void *opaque_class;
    void *opaque;
    SDL_VoutOverlay *(*create_overlay)(int, int, int, SDL_Vout *);
    void (*free_l)(SDL_Vout *);
    int (*display_overlay)(SDL_Vout *, SDL_VoutOverlay *);
    uint32_t overlay_format;
};
SDL_mutex *SDL_CreateMutex();
void SDL_DestroyMutex(SDL_mutex *);
int SDL_LockMutex(SDL_mutex *);
int SDL_UnlockMutex(SDL_mutex *);
SDL_VoutOverlay *SDL_VoutFFmpeg_CreateOverlay(int, int, int, SDL_Vout *);
}

namespace {
struct Output {
    OHNativeWindow *window = nullptr; // borrowed while vout->mutex is held
    int width = 0, height = 0;
    bool logged = false;
};
int factories = 0; // factory/create are called on the ArkTS thread
constexpr uint32_t Rv32 = 'R' | ('V' << 8) | ('3' << 16) | ('2' << 24);

SDL_VoutOverlay *CreateOverlay(int w, int h, int fmt, SDL_Vout *vout) {
    SDL_LockMutex(vout->mutex);
    auto *overlay = SDL_VoutFFmpeg_CreateOverlay(w, h, fmt, vout);
    SDL_UnlockMutex(vout->mutex);
    return overlay;
}

int Display(SDL_Vout *vout, SDL_VoutOverlay *overlay) {
    SDL_LockMutex(vout->mutex);
    auto &out = *static_cast<Output *>(vout->opaque);
    int result = -1;
    auto *window = out.window;
    if (window && overlay && overlay->format == Rv32 && overlay->planes == 1 &&
        overlay->w > 0 && overlay->h > 0 && overlay->pixels && overlay->pitches &&
        overlay->pitches[0] >= overlay->w * 4) {
        if (out.width != overlay->w || out.height != overlay->h) {
            result = OH_NativeWindow_NativeWindowHandleOpt(window, SET_BUFFER_GEOMETRY, overlay->w, overlay->h);
            if (result == 0) { out.width = overlay->w; out.height = overlay->h; }
        } else { result = 0; }
        OHNativeWindowBuffer *buffer = nullptr;
        int fence = -1;
        if (result == 0) result = OH_NativeWindow_NativeWindowRequestBuffer(window, &buffer, &fence);
        if (result == 0) {
            if (fence >= 0) {
                pollfd wait{fence, POLLIN, 0};
                result = poll(&wait, 1, 1000) > 0 ? 0 : -1;
                close(fence);
            }
            OH_NativeBuffer *native = nullptr;
            void *pixels = nullptr;
            if (result == 0) result = OH_NativeBuffer_FromNativeWindowBuffer(buffer, &native);
            if (result == 0) result = OH_NativeBuffer_Map(native, &pixels);
            if (result == 0) {
                OH_NativeBuffer_Config config{};
                OH_NativeBuffer_GetConfig(native, &config);
                if (pixels && config.width >= overlay->w && config.height >= overlay->h && config.stride >= overlay->w * 4) {
                    for (int y = 0; y < overlay->h; ++y) {
                        auto *dst = static_cast<uint8_t *>(pixels) + y * config.stride;
                        const auto *src = overlay->pixels[0] + y * overlay->pitches[0];
                        std::memcpy(dst, src, overlay->w * 4);
                        // FFmpeg AV_PIX_FMT_RGB0 padding is not an alpha channel.
                        for (int x = 0; x < overlay->w; ++x) dst[x * 4 + 3] = 255;
                    }
                } else { result = -1; }
                OH_NativeBuffer_Unmap(native);
            }
            if (result == 0) result = OH_NativeWindow_NativeWindowFlushBuffer(window, buffer, -1, Region{nullptr, 0});
            if (result != 0) OH_NativeWindow_NativeWindowAbortBuffer(window, buffer);
            if (!out.logged) {
                OH_LOG_Print(LOG_APP, LOG_INFO, 0, "FqPlayer", "cpu video output result=%{public}d width=%{public}d height=%{public}d", result, overlay->w, overlay->h);
                out.logged = true;
            }
        }
    }
    SDL_UnlockMutex(vout->mutex);
    return result;
}

void Free(SDL_Vout *vout) {
    SDL_DestroyMutex(vout->mutex);
    delete static_cast<Output *>(vout->opaque);
    std::free(vout);
}
}

// The pinned player imports these SDL factory/surface entrypoints dynamically.
// Providing them here selects our producer without modifying vendor binaries.
extern "C" SDL_Vout *SDL_VoutAndroid_CreateForAndroidSurface() {
    auto *vout = static_cast<SDL_Vout *>(std::calloc(1, sizeof(SDL_Vout)));
    if (!vout) return nullptr;
    vout->mutex = SDL_CreateMutex();
    if (!vout->mutex) { std::free(vout); return nullptr; }
    vout->opaque = new Output();
    vout->create_overlay = CreateOverlay;
    vout->display_overlay = Display;
    vout->free_l = Free;
    ++factories;
    return vout;
}

extern "C" void SDL_VoutAndroid_SetAndroidSurface(SDL_Vout *vout, void *surface) {
    SDL_LockMutex(vout->mutex);
    auto &out = *static_cast<Output *>(vout->opaque);
    out.window = static_cast<OHNativeWindow *>(surface);
    out.width = out.height = 0;
    if (out.window) {
        OH_NativeWindow_NativeWindowHandleOpt(out.window, SET_FORMAT, NATIVEBUFFER_PIXEL_FMT_RGBA_8888);
        uint64_t usage = NATIVEBUFFER_USAGE_CPU_WRITE | NATIVEBUFFER_USAGE_CPU_READ | NATIVEBUFFER_USAGE_HW_TEXTURE;
        OH_NativeWindow_NativeWindowHandleOpt(out.window, SET_USAGE, usage);
        OH_NativeWindow_NativeWindowHandleOpt(out.window, SET_TIMEOUT, static_cast<int64_t>(1000000000));
    }
    SDL_UnlockMutex(vout->mutex);
}

extern "C" int fq_cpu_video_factories() { return factories; }
