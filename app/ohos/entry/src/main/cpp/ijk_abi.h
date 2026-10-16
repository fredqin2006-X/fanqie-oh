// Minimal ABI declarations for the pinned @ohos/ijkplayer 2.0.11 shared library.
// AVMessage layout and API declarations derived from ijkPlayer headers:
// Copyright (c) 2013 Bilibili; Copyright (c) 2013 Zhang Rui.
// SPDX-License-Identifier: LGPL-2.1-or-later
// License and upstream notices: app/assets/licenses/ijkplayer/.
#pragma once
#include <cstdint>
extern "C" {
struct IjkMediaPlayer;
struct AVMessage {
    int what, arg1, arg2;
    void *obj;
    void (*free_l)(void *obj);
    AVMessage *next;
};
void ijkmp_global_init();
void ijkmp_global_set_log_level(int);
IjkMediaPlayer *ijkmp_android_create(int (*)(void *));
void ijkmp_android_set_surface(IjkMediaPlayer *, void *, bool);
void *ijkmp_get_weak_thiz(IjkMediaPlayer *);
void *ijkmp_set_weak_thiz(IjkMediaPlayer *, void *);
void ijkmp_set_option(IjkMediaPlayer *, int, const char *, const char *);
void ijkmp_set_option_int(IjkMediaPlayer *, int, const char *, int64_t);
int ijkmp_set_data_source(IjkMediaPlayer *, const char *);
int ijkmp_prepare_async(IjkMediaPlayer *);
int ijkmp_get_msg(IjkMediaPlayer *, AVMessage *, int);
int ijkmp_start(IjkMediaPlayer *);
int ijkmp_pause(IjkMediaPlayer *);
int ijkmp_seek_to(IjkMediaPlayer *, long);
void ijkmp_set_playback_rate(IjkMediaPlayer *, float);
void ijkmp_set_playback_volume(IjkMediaPlayer *, float);
long ijkmp_get_current_position(IjkMediaPlayer *);
long ijkmp_get_duration(IjkMediaPlayer *);
bool ijkmp_is_playing(IjkMediaPlayer *);
void ijkmp_shutdown(IjkMediaPlayer *);
void ijkmp_dec_ref_p(IjkMediaPlayer **);
}
