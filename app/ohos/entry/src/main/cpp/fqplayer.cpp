#include "ijk_abi.h"
#include <napi/native_api.h>
#include <native_window/external_window.h>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace {
struct Event { int what, a, b; };
struct Session {
    IjkMediaPlayer *player = nullptr;
    OHNativeWindow *window = nullptr;
    std::mutex mutex;
    std::condition_variable exited;
    bool loopDone = false;
    bool preparedAttempted = false;
    std::vector<Event> events;
};
std::unordered_map<int, std::shared_ptr<Session>> sessions; // JS thread only
int nextId = 1;
std::once_flag initialized;

int MessageLoop(void *arg) {
    auto *player = static_cast<IjkMediaPlayer *>(arg);
    auto *session = static_cast<Session *>(ijkmp_get_weak_thiz(player));
    AVMessage msg{};
    while (ijkmp_get_msg(player, &msg, 1) > 0) {
        if (msg.what == 100 || msg.what == 200 || msg.what == 300 || msg.what == 400 ||
            msg.what == 402 || msg.what == 412 || msg.what == 500 || msg.what == 501 || msg.what == 600) {
            std::lock_guard<std::mutex> lock(session->mutex);
            // Bound storage while the ArkTS event loop is paused/backgrounded.
            if (session->events.size() < 128) session->events.push_back({msg.what, msg.arg1, msg.arg2});
        }
        if (msg.obj && msg.free_l) msg.free_l(msg.obj);
        msg = {};
    }
    ijkmp_dec_ref_p(&player); // prepare_async acquired the message-thread reference
    {
        std::lock_guard<std::mutex> lock(session->mutex);
        session->loopDone = true;
        session->exited.notify_one();
    }
    return 0;
}

void Close(Session &s) {
    if (s.player) {
        ijkmp_shutdown(s.player); // blocking: called by an async worker
        if (s.preparedAttempted) {
            std::unique_lock<std::mutex> lock(s.mutex);
            s.exited.wait(lock, [&s] { return s.loopDone; });
        }
        ijkmp_android_set_surface(s.player, nullptr, false);
        ijkmp_dec_ref_p(&s.player);
    }
    if (s.window) OH_NativeWindow_DestroyNativeWindow(s.window);
    s.window = nullptr;
}

napi_value Number(napi_env env, double n) { napi_value v; napi_create_double(env, n, &v); return v; }
void Set(napi_env env, napi_value object, const char *name, double n) {
    napi_set_named_property(env, object, name, Number(env, n));
}
std::string String(napi_env env, napi_value value) {
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) return {};
    std::string text(length + 1, '\0');
    napi_get_value_string_utf8(env, value, text.data(), text.size(), &length);
    text.resize(length);
    return text;
}
int Id(napi_env env, napi_value value) { int32_t id = 0; napi_get_value_int32(env, value, &id); return id; }

napi_value Create(napi_env env, napi_callback_info info) {
    size_t argc = 2; napi_value argv[2]{};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc != 2 || sessions.size() >= 8) return Number(env, -1);
    auto surface = String(env, argv[0]);
    auto url = String(env, argv[1]);
    if (surface.empty() || url.empty()) return Number(env, -1);
    char *end = nullptr;
    uint64_t surfaceId = strtoull(surface.c_str(), &end, 10);
    if (!end || *end || !surfaceId) return Number(env, -1);
    auto s = std::make_shared<Session>();
    if (OH_NativeWindow_CreateNativeWindowFromSurfaceId(surfaceId, &s->window) != 0) return Number(env, -1);
    std::call_once(initialized, [] { ijkmp_global_init(); ijkmp_global_set_log_level(16); });
    s->player = ijkmp_android_create(MessageLoop);
    if (!s->player) { Close(*s); return Number(env, -1); }
    ijkmp_set_weak_thiz(s->player, s.get());
    ijkmp_android_set_surface(s->player, s->window, false);
    // Force FFmpeg software decoding: the fallback must not retry the failed codec.
    ijkmp_set_option_int(s->player, 4, "mediacodec", 0);
    ijkmp_set_option_int(s->player, 4, "start-on-prepared", 0);
    ijkmp_set_option_int(s->player, 4, "soundtouch", 1);
    ijkmp_set_option_int(s->player, 4, "enable-accurate-seek", 1);
    ijkmp_set_option_int(s->player, 1, "rw_timeout", 15000000);
    ijkmp_set_option_int(s->player, 1, "timeout", 15000000);
    ijkmp_set_option_int(s->player, 2, "threads", 4);
    if (ijkmp_set_data_source(s->player, url.c_str()) < 0) { Close(*s); return Number(env, -1); }
    const int id = nextId++;
    sessions.emplace(id, s);
    s->preparedAttempted = true;
    // Errors are delivered by the message loop; no source/URL is logged here.
    if (ijkmp_prepare_async(s->player) < 0) {
        std::lock_guard<std::mutex> lock(s->mutex);
        s->events.push_back({100, -1, 0});
    }
    return Number(env, id);
}

napi_value Poll(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1]{}; napi_value result;
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    napi_create_object(env, &result);
    if (!argc) return result;
    auto found = sessions.find(Id(env, argv[0]));
    if (found == sessions.end()) return result;
    auto s = found->second;
    std::vector<Event> events;
    { std::lock_guard<std::mutex> lock(s->mutex); events.swap(s->events); }
    napi_value array;
    napi_create_array_with_length(env, events.size(), &array);
    for (size_t i = 0; i < events.size(); ++i) {
        napi_value event; napi_create_object(env, &event);
        Set(env, event, "what", events[i].what); Set(env, event, "a", events[i].a); Set(env, event, "b", events[i].b);
        napi_set_element(env, array, i, event);
    }
    napi_set_named_property(env, result, "events", array);
    Set(env, result, "position", ijkmp_get_current_position(s->player));
    Set(env, result, "duration", ijkmp_get_duration(s->player));
    napi_value playing; napi_get_boolean(env, ijkmp_is_playing(s->player), &playing);
    napi_set_named_property(env, result, "playing", playing);
    return result;
}

napi_value Command(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3]{};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc != 3) return Number(env, -1);
    auto found = sessions.find(Id(env, argv[0]));
    if (found == sessions.end()) return Number(env, -1);
    auto *p = found->second->player;
    auto name = String(env, argv[1]);
    double value = 0; napi_get_value_double(env, argv[2], &value);
    int rc = 0;
    if (name == "play") rc = ijkmp_start(p);
    else if (name == "pause") rc = ijkmp_pause(p);
    else if (name == "seek") rc = ijkmp_seek_to(p, static_cast<long>(value));
    else if (name == "rate") ijkmp_set_playback_rate(p, value);
    else if (name == "volume") ijkmp_set_playback_volume(p, value);
    else rc = -1;
    return Number(env, rc);
}

struct ReleaseWork { std::shared_ptr<Session> session; napi_async_work work; napi_deferred deferred; };
napi_value Release(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1]{}, promise, name;
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    auto *work = new ReleaseWork{};
    napi_create_promise(env, &work->deferred, &promise);
    auto found = sessions.find(argc ? Id(env, argv[0]) : 0);
    if (found != sessions.end()) { work->session = found->second; sessions.erase(found); }
    napi_create_string_utf8(env, "fqplayer.release", NAPI_AUTO_LENGTH, &name);
    napi_create_async_work(env, nullptr, name,
        [](napi_env, void *data) { auto *w = static_cast<ReleaseWork *>(data); if (w->session) Close(*w->session); },
        [](napi_env env, napi_status, void *data) {
            auto *w = static_cast<ReleaseWork *>(data); napi_value undefined; napi_get_undefined(env, &undefined);
            napi_resolve_deferred(env, w->deferred, undefined); napi_delete_async_work(env, w->work); delete w;
        }, work, &work->work);
    napi_queue_async_work(env, work->work);
    return promise;
}

napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor methods[] = {
        {"create", nullptr, Create, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"poll", nullptr, Poll, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"command", nullptr, Command, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"release", nullptr, Release, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(methods) / sizeof(methods[0]), methods);
    return exports;
}
}
static napi_module module = {1, 0, nullptr, Init, "fqplayer", nullptr, {0}};
extern "C" __attribute__((constructor)) void RegisterFqPlayer() { napi_module_register(&module); }
