// SDL_Vout ABI from @ohos/ijkplayer 2.0.11 (Bilibili / Zhang Rui).
// SPDX-License-Identifier: LGPL-2.1-or-later
// Keep only the latest decoded RGBA frame. Neither IJK EGL nor the emulator's
// external native-image importer participates in this software fallback.
#include "software_video_output.h"
#include <hilog/log.h>
#include <cstdlib>
#include <cstring>
#include <mutex>

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
SDL_VoutOverlay *SDL_VoutFFmpeg_CreateOverlay(int, int, int, SDL_Vout *);
}

namespace {
struct Output {
    std::mutex mutex;
    FqVideoFrame frame;
};
int factories = 0; // SDL factory/player creation occur on the ArkTS thread
Output *lastOutput = nullptr;
constexpr uint32_t Rv32 = 'R' | ('V' << 8) | ('3' << 16) | ('2' << 24);

int Display(SDL_Vout *vout, SDL_VoutOverlay *overlay) {
    if (!overlay || overlay->format != Rv32 || overlay->planes != 1 ||
        overlay->w <= 0 || overlay->h <= 0 || !overlay->pixels || !overlay->pitches ||
        overlay->pitches[0] < overlay->w * 4) return -1;
    auto &out = *static_cast<Output *>(vout->opaque);
    std::lock_guard<std::mutex> lock(out.mutex);
    auto &frame = out.frame;
    frame.width = overlay->w; frame.height = overlay->h;
    frame.pixels.resize(static_cast<size_t>(frame.width) * frame.height * 4);
    for (int y = 0; y < frame.height; ++y) {
        auto *dst = frame.pixels.data() + static_cast<size_t>(y) * frame.width * 4;
        std::memcpy(dst, overlay->pixels[0] + y * overlay->pitches[0], frame.width * 4);
        // FFmpeg AV_PIX_FMT_RGB0 padding is not an alpha channel.
        for (int x = 0; x < frame.width; ++x) dst[x * 4 + 3] = 255;
    }
    if (++frame.serial == 1) {
        OH_LOG_Print(LOG_APP, LOG_INFO, 0, "FqPlayer", "cpu frame width=%{public}d height=%{public}d", frame.width, frame.height);
    }
    return 0;
}

void Free(SDL_Vout *vout) {
    SDL_DestroyMutex(vout->mutex);
    delete static_cast<Output *>(vout->opaque);
    std::free(vout);
}
}

// These are dynamically imported SDL entrypoints of the pinned player. A
// factory-count guard rejects a vendor update that stops selecting our vout.
extern "C" SDL_Vout *SDL_VoutAndroid_CreateForAndroidSurface() {
    auto *vout = static_cast<SDL_Vout *>(std::calloc(1, sizeof(SDL_Vout)));
    if (!vout) return nullptr;
    vout->mutex = SDL_CreateMutex();
    if (!vout->mutex) { std::free(vout); return nullptr; }
    vout->opaque = lastOutput = new Output();
    vout->create_overlay = SDL_VoutFFmpeg_CreateOverlay;
    vout->display_overlay = Display;
    vout->free_l = Free;
    ++factories;
    return vout;
}

extern "C" void SDL_VoutAndroid_SetAndroidSurface(SDL_Vout *, void *) {
    // No native window or process-wide EGLDisplay belongs to this producer.
}
extern "C" int fq_cpu_video_factories() { return factories; }
void *fq_cpu_last_output() { return lastOutput; }
bool fq_cpu_copy_frame(void *output, int previousSerial, FqVideoFrame &frame) {
    if (!output) return false;
    auto &out = *static_cast<Output *>(output);
    std::lock_guard<std::mutex> lock(out.mutex);
    if (!out.frame.serial || out.frame.serial == previousSerial) return false;
    frame = out.frame;
    return true;
}
