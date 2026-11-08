// Host behavior checks of real ArkTS implementations, with OS services mocked.
// Run with DevEco's TypeScript in NODE_PATH. This is not a device or HAP test.
'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

function load(name, dependencies = {}, globals = {}) {
  const source = fs.readFileSync(path.join(__dirname, '../ohos/entry/src/main/ets/platform', name + '.ets'), 'utf8');
  const compiled = ts.transpileModule(source, { fileName: name + '.ts', reportDiagnostics: true,
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } });
  assert.deepEqual(compiled.diagnostics, []);
  const exports = {};
  vm.runInNewContext(compiled.outputText, { exports, setTimeout, clearTimeout,
    setInterval, clearInterval, ...globals, require: name => {
      assert.ok(Object.hasOwn(dependencies, name), 'Unexpected dependency: ' + name);
      return dependencies[name];
    } });
  return exports;
}
const tick = () => new Promise(resolve => setImmediate(resolve));
const call = (method, args = {}) => ({ method, args, argument: key => args[key] });
const invoke = (plugin, method, args) => new Promise((resolve, reject) => {
  plugin.onMethodCall(call(method, args), { success: resolve, error: code => reject(new Error(code)),
    notImplemented: () => reject(new Error('NOT_IMPLEMENTED')) });
});
function deferred() { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; }

function pipFixture() {
  const targets = [], actions = [], updates = [], nodes = [], controllers = [];
  const state = { allowed: true };
  const PiPWindow = { isPiPEnabled: () => true,
    PiPTemplateType: { VIDEO_PLAY: 0 }, VideoPlayControlGroup: { VIDEO_PREVIOUS_NEXT: 1 },
    PiPState: { STARTED: 2, STOPPED: 4, ABOUT_TO_RESTORE: 5, ERROR: 6 },
    PiPControlType: { VIDEO_PLAY_PAUSE: 0, VIDEO_PREVIOUS: 1, VIDEO_NEXT: 2 },
    PiPControlStatus: { PLAY: 1, PAUSE: 0 },
    async create(_config, node) {
      const listeners = new Map();
      const controller = { listeners, active: false, auto: false, starts: 0,
        on: (type, fn) => listeners.set(type, fn), off: type => listeners.delete(type),
        getPiPSettingSwitch: async () => state.allowed,
        isPiPActive: async () => controller.active,
        setAutoStartEnabled: enabled => { controller.auto = enabled; },
        async startPiP() { controller.active = true; controller.starts++;
          node.surface.onSurfaceCreated('pip'); listeners.get('stateChange')?.(2); },
        async stopPiP() { controller.active = false; },
        updatePiPControlStatus: (...args) => updates.push(args),
        setPiPControlEnabled: (...args) => updates.push(args), updateContentSize() {} };
      controllers.push(controller); return controller;
    } };
  const dependencies = { '@kit.ArkUI': { PiPWindow,
    window: { getLastWindow: async () => ({ getUIContext: () => ({}) }) },
    typeNode: { createNode: (_ui, _type, options) => {
      const attribute = { width: () => attribute, height: () => attribute };
      const node = { attribute, surface: options.controller, disposed: false, dispose() { this.disposed = true; } };
      nodes.push(node); return node;
    } } } };
  const { FloatingVideo } = load('FloatingVideo', dependencies,
    { XComponentController: class {}, XComponentType: { SURFACE: 0 } });
  const video = new FloatingVideo({}, { invokeMethod: (method, action) => actions.push([method, action]) },
    (id, surface) => targets.push([id, surface]));
  return { video, targets, actions, updates, nodes, controllers, state };
}

test('PiP prepares without moving video, shows once, swaps and restores surfaces', async () => {
  const f = pipFixture();
  await f.video.prepare(call('startFloating', { playing: true, hasNext: true, hasPrev: false }), 7);
  assert.deepEqual(f.targets, []);
  assert.equal(f.controllers[0].auto, true);
  await f.video.show(); await f.video.show();
  assert.equal(f.controllers[0].starts, 1);
  assert.equal(f.video.owns(7), true);
  f.video.swap(7); assert.deepEqual(f.targets, [[7, 'pip']]);
  f.video.swap(8);
  assert.deepEqual(f.targets, [[7, 'pip'], [8, 'pip'], [7, null]]);
  await f.video.stop();
  assert.deepEqual(f.targets.at(-1), [8, null]);
  assert.equal(f.controllers[0].auto, false);
  assert.equal(f.nodes[0].disposed, true);
});
test('PiP system controls and restoration use existing Dart remote actions', async () => {
  const f = pipFixture(); await f.video.prepare(call('startFloating', { owner: 41 }), 7); await f.video.show();
  const listeners = f.controllers[0].listeners;
  listeners.get('controlEvent')({ controlType: 0 });
  listeners.get('controlEvent')({ controlType: 2 });
  listeners.get('stateChange')(5); listeners.get('stateChange')(4);
  assert.deepEqual(f.actions.map(x => [x[0], Object.fromEntries(x[1])]), [
    ['onFloatingAction', { owner: 41, action: 'playPause' }],
    ['onFloatingAction', { owner: 41, action: 'next' }],
    ['onFloatingAction', { owner: 41, action: 'fullscreen' }],
  ]);
  assert.deepEqual(f.targets.at(-1), [7, null]);
  await f.video.stop();
});
test('PiP disabled setting fails and releases node instead of reporting success', async () => {
  const f = pipFixture(); f.state.allowed = false;
  await assert.rejects(f.video.prepare(call('startFloating'), 7), /PIP_DISABLED/);
  assert.equal(f.nodes[0].disposed, true); assert.equal(f.controllers[0].auto, false);
  await assert.rejects(f.video.show(), /PIP_NOT_PREPARED/);
});

function pcmFixture() {
  const renderers = [], events = [];
  const state = { createGate: null, drainGate: null, maxWrite: Infinity };
  const audio = { AudioSamplingRate: { SAMPLE_RATE_16000: 16000 }, AudioChannel: { CHANNEL_1: 1, CHANNEL_2: 2 },
    AudioSampleFormat: { SAMPLE_FORMAT_S16LE: 1 }, AudioEncodingType: { ENCODING_TYPE_RAW: 0 },
    StreamUsage: { STREAM_USAGE_AUDIOBOOK: 12 }, InterruptHint: { INTERRUPT_HINT_PAUSE: 2, INTERRUPT_HINT_STOP: 3 },
    async createAudioRenderer(options) {
      if (state.createGate) await state.createGate.promise;
      const renderer = { options, writes: [], releases: 0, started: false, speed: 0,
        setSpeed(rate) { this.speed = rate; }, on() {}, async start() { this.started = true; },
        async write(buffer) { const size = Math.min(buffer.byteLength, state.maxWrite);
          this.writes.push(...new Uint8Array(buffer).slice(0, size)); return size; },
        async drain() { if (state.drainGate) await state.drainGate.promise; },
        async release() { this.releases++; } };
      renderers.push(renderer); return renderer;
    } };
  const { PcmSpeechPlayback } = load('PcmSpeechPlayback', { '@kit.AudioKit': { audio } });
  const player = new PcmSpeechPlayback(3, event => events.push(event));
  player.start({ audioType: 'pcm', sampleRate: 16000, sampleBit: 16, audioChannel: 1 });
  return { player, events, state, renderers, PcmSpeechPlayback };
}
test('3x PCM sorts IPC chunks, handles partial writes and completes after drain', async () => {
  const f = pcmFixture(); f.state.maxWrite = 2; f.state.drainGate = deferred();
  f.player.append(new Uint8Array([3, 4]).buffer, { sequence: 1, audioType: 'pcm' });
  f.player.append(new Uint8Array([1, 2]).buffer, { sequence: 0, audioType: 'pcm' });
  const finish = f.player.finish(); await tick();
  assert.deepEqual(f.events, ['start']); assert.equal(f.renderers[0].speed, 3);
  assert.deepEqual(f.renderers[0].writes, [1, 2, 3, 4]);
  f.state.drainGate.resolve(); await finish;
  assert.deepEqual(f.events, ['start', 'done']); assert.equal(f.renderers[0].releases, 1);
});
test('PCM rejects missing sequence and emits no false completion', async () => {
  const f = pcmFixture(); f.player.append(new Uint8Array([3, 4]).buffer, { sequence: 1, audioType: 'pcm' });
  await f.player.finish(); assert.deepEqual(f.events, ['error']); assert.equal(f.renderers.length, 0);
});
test('PCM cancellation during renderer creation releases late renderer without playback', async () => {
  const f = pcmFixture(); f.state.createGate = deferred();
  f.player.append(new Uint8Array([1, 2]).buffer, { sequence: 0, audioType: 'pcm' });
  const finish = f.player.finish(); await f.player.stop(); f.state.createGate.resolve(); await finish;
  assert.deepEqual(f.events, []); assert.equal(f.renderers[0].started, false); assert.equal(f.renderers[0].releases, 1);
});
test('PCM cancellation during drain does not emit done or release twice', async () => {
  const f = pcmFixture(); f.state.drainGate = deferred();
  f.player.append(new Uint8Array([1, 2]).buffer, { sequence: 0, audioType: 'pcm' });
  const finish = f.player.finish(); await tick(); await f.player.stop(); f.state.drainGate.resolve(); await finish;
  assert.deepEqual(f.events, ['start']); assert.equal(f.renderers[0].releases, 1);
});

function ttsFixture() {
  const spoken = [], events = [];
  let listener;
  const engine = { setListener(value) { listener = value; }, shutdown() {}, stop() {},
    speak(text, options) { spoken.push({ text, options }); } };
  const pcm = pcmFixture();
  const { SystemTtsPlugin } = load('SystemTtsPlugin', {
    '@ohos/flutter_ohos': {},
    '@kit.CoreSpeechKit': { textToSpeech: { createEngine: async () => engine } },
    './PcmSpeechPlayback': { PcmSpeechPlayback: pcm.PcmSpeechPlayback } });
  const plugin = new SystemTtsPlugin(); plugin.onListen(null, { success: event => events.push(Object.fromEntries(event)) });
  return { plugin, spoken, events, pcm, get listener() { return listener; } };
}
test('regular TTS preserves both queued utterances and synthesis does not complete playback', async () => {
  const f = ttsFixture(); await invoke(f.plugin, 'initialize', { rate: 1 });
  await invoke(f.plugin, 'speak', { text: '第一句。', id: 'a' });
  await invoke(f.plugin, 'speak', { text: '第二句。', id: 'b', queue: true });
  const first = f.spoken[0].options, second = f.spoken[1].options;
  assert.equal(first.extraParams.queueMode, 0); assert.equal(second.extraParams.queueMode, 1);
  f.listener.onStart(first.requestId, {}); f.listener.onComplete(first.requestId, { type: 0 });
  assert.deepEqual(f.events, [{ id: 'a', type: 'start' }]);
  f.listener.onComplete(first.requestId, { type: 1 }); f.listener.onStart(second.requestId, {});
  f.listener.onComplete(second.requestId, { type: 1 });
  assert.deepEqual(f.events.map(e => e.id + ':' + e.type), ['a:start', 'a:done', 'b:start', 'b:done']);
});
test('3x TTS pre-synthesizes queued sentences but plays them sequentially', async () => {
  const f = ttsFixture(); f.pcm.state.drainGate = deferred();
  await invoke(f.plugin, 'initialize', { rate: 3 });
  await invoke(f.plugin, 'speak', { text: '第一句。', id: 'a' });
  await invoke(f.plugin, 'speak', { text: '第二句。', id: 'b', queue: true });
  for (const { options } of f.spoken) {
    assert.equal(options.extraParams.speed, 1); assert.equal(options.extraParams.playType, 0);
    f.listener.onStart(options.requestId, { audioType: 'pcm', sampleRate: 16000, sampleBit: 16, audioChannel: 1 });
    f.listener.onData(options.requestId, new Uint8Array([1, 2]).buffer, { sequence: 0, audioType: 'pcm' });
    f.listener.onComplete(options.requestId, { type: 0 });
  }
  await tick(); assert.equal(f.pcm.renderers.length, 1); assert.deepEqual(f.events, [{ id: 'a', type: 'start' }]);
  f.pcm.state.drainGate.resolve(); await tick(); await tick();
  assert.deepEqual(f.events.map(e => e.id + ':' + e.type), ['a:start', 'a:done', 'b:start', 'b:done']);
});
test('flushing TTS retires late callbacks from previous positions', async () => {
  const f = ttsFixture(); await invoke(f.plugin, 'initialize', { rate: 1 });
  await invoke(f.plugin, 'speak', { text: '旧句。', id: 'a' });
  await invoke(f.plugin, 'speak', { text: '新句。', id: 'b' });
  f.listener.onComplete(f.spoken[0].options.requestId, { type: 1 });
  assert.deepEqual(f.events, []);
  await invoke(f.plugin, 'stop'); f.listener.onStart(f.spoken[1].options.requestId, {});
  assert.deepEqual(f.events, []);
});

test('volume key bridge debounces holds, yields while inactive, and restores on focus', async () => {
  const actions = [], listeners = new Map();
  class MethodChannel { setMethodCallHandler() {} invokeMethod(...args) { actions.push(args); } }
  const { VolumeKeyPlugin } = load('VolumeKeyPlugin', {
    '@ohos/flutter_ohos': { MethodChannel }, '@kit.InputKit': { KeyCode: { KEYCODE_VOLUME_UP: 16, KEYCODE_VOLUME_DOWN: 17 } },
    '@kit.ArkUI': { window: { WindowEventType: { WINDOW_HIDDEN: 4, WINDOW_INACTIVE: 3, WINDOW_ACTIVE: 2 },
      getLastWindow: async () => ({ on: (type, fn) => listeners.set(type, fn), off: type => listeners.delete(type) }) } } },
  { KeyType: { Down: 0, Up: 1 } });
  const plugin = new VolumeKeyPlugin({}); plugin.onAttachedToEngine({ getBinaryMessenger() {} }); await tick();
  await invoke(plugin, 'setEnabled', true);
  const down = { keyCode: 17, type: 0 }, up = { keyCode: 17, type: 1 };
  assert.equal(VolumeKeyPlugin.dispatch(down), true); VolumeKeyPlugin.dispatch(down); VolumeKeyPlugin.dispatch(up);
  assert.deepEqual(actions, [['volumeKey', 1]]);
  listeners.get('windowEvent')(3); await invoke(plugin, 'setEnabled', true);
  assert.equal(VolumeKeyPlugin.dispatch(down), false);
  listeners.get('windowEvent')(2); assert.equal(VolumeKeyPlugin.dispatch(down), true);
  plugin.onDetachedFromEngine({}); assert.equal(VolumeKeyPlugin.dispatch(down), false);
});

function nativePlayerFixture() {
  const players = [], softwares = [], events = [], pipCalls = [], seeks = [];
  const state = { prepareGate: null };
  class Channel { setMethodCallHandler() {} setStreamHandler() {} invokeMethod() {} }
  const dependencies = {
    '@ohos/flutter_ohos': { MethodChannel: Channel, EventChannel: Channel },
    '@kit.MediaKit': { media: { SeekMode: { SEEK_CLOSEST: 0 }, createAVPlayer: async () => {
      const listeners = new Map();
      const player = { listeners, on: (event, fn) => listeners.set(event, fn),
        duration: 10000, width: 1920, height: 1080,
        async release() {}, async prepare() {}, setVolume() {}, setPlaybackRate() {},
        seek(position) { seeks.push(position); } };
      players.push(player); return player;
    } } },
    '@kit.AudioKit': { audio: {} }, '@kit.NetworkKit': { http: {} },
    '@kit.PerformanceAnalysisKit': { hilog: { info() {}, error() {} } },
    './BackgroundMedia': { BackgroundMedia: class { async stop() {} async update() {} } },
    './FloatingVideo': { FloatingVideo: class {
      static supported() { return true; }
      owns() { return false; }
      async prepare(call, id) { pipCalls.push(['prepare', call.argument('owner'), id]);
        if (state.prepareGate) await state.prepareGate.promise; }
      async stop() { pipCalls.push(['stop']); }
      async show() { pipCalls.push(['show']); }
      swap(id) { pipCalls.push(['swap', id]); }
      update() { pipCalls.push(['update']); }
    } },
    './SoftwareVideoView': { SoftwareVideoViewFactory: class {} },
    'libfqplayer.so': { create(url) { softwares.push(url); return 101; }, async release() {} },
  };
  const { NativePlayerPlugin } = load('NativePlayerPlugin', dependencies);
  const textures = { getTextureId: () => 5, registerTexture: () => ({ getTextureId: () => 5, getSurfaceId: () => 55 }),
    unregisterTexture() {}, setTextureBufferSize() {} };
  const plugin = new NativePlayerPlugin({}, { keep: async () => {} });
  plugin.onAttachedToEngine({ getPlatformViewRegistry: () => ({ registerViewFactory() {} }),
    getTextureRegistry: () => textures, getBinaryMessenger() {} });
  plugin.onListen(null, { success: event => events.push(Object.fromEntries(event)) });
  return { plugin, players, softwares, events, pipCalls, seeks, state };
}
async function readyNativePlayer(f, startPositionMs = 0) {
  const reply = await invoke(f.plugin, 'create', {
    cdnUrl: 'https://example.invalid/a.mp4', keyHex: '', videoDecoder: 'hardware', startPositionMs,
  });
  await tick();
  f.players.at(-1).listeners.get('stateChange')('prepared');
  return reply.get('playerId');
}
test('native player applies resume position before publishing readiness and rejects a past-end resume', async () => {
  const f = nativePlayerFixture();
  const first = await readyNativePlayer(f, 4200);
  assert.deepEqual(f.seeks, [4200]);
  await invoke(f.plugin, 'dispose', { id: first });
  const second = await readyNativePlayer(f, 11000);
  assert.deepEqual(f.seeks, [4200, 0]);
  await invoke(f.plugin, 'dispose', { id: second });
});
test('PiP owner retirement fences delayed starts and old commands cannot stop the current owner', async () => {
  const f = nativePlayerFixture(), id = await readyNativePlayer(f);
  const old = await invoke(f.plugin, 'allocateFloatingOwner');
  f.state.prepareGate = deferred();
  const start = invoke(f.plugin, 'startFloating', { owner: old, playerId: id });
  const rejected = assert.rejects(start, /PIP_UNAVAILABLE/);
  await tick();
  const stop = invoke(f.plugin, 'stopFloating', { owner: old });
  f.state.prepareGate.resolve();
  await rejected; await stop;
  f.state.prepareGate = null;
  const owner = await invoke(f.plugin, 'allocateFloatingOwner');
  await invoke(f.plugin, 'startFloating', { owner, playerId: id });
  const before = f.pipCalls.length;
  await invoke(f.plugin, 'stopFloating', { owner: old });
  assert.equal(f.pipCalls.length, before);
  await assert.rejects(invoke(f.plugin, 'updateFloating', { owner: old }), /PIP_RETIRED/);
  await invoke(f.plugin, 'showFloating', { owner });
  assert.deepEqual(f.pipCalls.at(-1), ['show']);
  await invoke(f.plugin, 'stopFloating', { owner });
  await invoke(f.plugin, 'dispose', { id });
});
test('explicit software decoder bypasses AVPlayer; hardware does not silently fall back', async () => {
  const f = nativePlayerFixture();
  await invoke(f.plugin, 'create', { cdnUrl: 'https://example.invalid/a.mp4', keyHex: '', videoDecoder: 'software' });
  await tick(); assert.equal(f.players.length, 0); assert.equal(f.softwares.length, 1);
  await invoke(f.plugin, 'dispose', { id: 1 });
  await invoke(f.plugin, 'create', { cdnUrl: 'https://example.invalid/a.mp4', keyHex: '', videoDecoder: 'hardware' });
  await tick(); const player = f.players[0];
  player.listeners.get('stateChange')('initialized');
  player.listeners.get('error')({ code: 5400106 });
  await tick(); assert.equal(f.softwares.length, 1);
  assert.equal(f.events.some(e => e.type === 'error'), true);
  await invoke(f.plugin, 'dispose', { id: 2 });
});
test('native audio creation rejects unimplemented engine preference', async () => {
  const f = nativePlayerFixture();
  await assert.rejects(invoke(f.plugin, 'create', { cdnUrl: 'https://example.invalid/a.mp3', keyHex: '',
    audioOnly: true, audioRateEngine: 'wsola' }), /UNSUPPORTED_AUDIO_ENGINE/);
  assert.equal(f.players.length, 0); assert.equal(f.softwares.length, 0);
});

function backgroundFixture() {
  const sessions = [], actions = []; const counts = { starts: 0, stops: 0 };
  const { BackgroundMedia } = load('BackgroundMedia', {
    '@kit.AbilityKit': { wantAgent: { getWantAgent: async () => ({}),
      OperationType: { START_ABILITY: 1 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 1 } } },
    '@kit.AVSessionKit': { avSession: { PlaybackState: { PLAYBACK_STATE_PLAY: 1, PLAYBACK_STATE_PAUSE: 2 },
      async createAVSession() {
        const session = { listeners: new Map(), metadata: [], states: [], destroyed: false,
          on(event, callback) { this.listeners.set(event, callback); }, async activate() {},
          async setAVMetadata(value) { this.metadata.push(value); },
          async setAVPlaybackState(value) { this.states.push(value); }, async destroy() { this.destroyed = true; } };
        sessions.push(session); return session;
      } } },
    '@kit.BackgroundTasksKit': { backgroundTaskManager: { BackgroundMode: { AUDIO_PLAYBACK: 1 },
      async startBackgroundRunning() { counts.starts++; }, async stopBackgroundRunning() { counts.stops++; } } },
  });
  const media = new BackgroundMedia({ abilityInfo: { bundleName: 'test', name: 'EntryAbility' } },
    { invokeMethod: (_method, args) => actions.push(args.get('action')) });
  return { media, sessions, actions, counts };
}
test('PiP media session merges partial fields and preserves background eligibility while paused', async () => {
  const f = backgroundFixture();
  await f.media.update(call('startFloating', { title: '短剧', episode: '第一集', playing: true,
    hasNext: true, hasPrev: false, positionMs: 500, durationMs: 10000, speed: 2 }), 'floating');
  await f.media.update(call('updateFloating', { positionMs: 800, title: null, playing: null }), 'floating', false);
  const session = f.sessions[0];
  assert.equal(session.metadata.at(-1).title, '短剧'); assert.equal(session.metadata.at(-1).artist, '第一集');
  assert.equal(session.states.at(-1).state, 1); assert.equal(session.states.at(-1).speed, 2);
  assert.equal(session.states.at(-1).position.elapsedTime, 800);
  session.listeners.get('playNext')(); session.listeners.get('playPrevious')();
  assert.deepEqual(f.actions, ['next']);
  await f.media.update(call('updateFloating', { playing: false }), 'floating', false);
  assert.equal(f.counts.starts, 1); assert.equal(f.counts.stops, 0);
  await f.media.stop('floating'); assert.equal(f.counts.stops, 1); assert.equal(session.destroyed, true);
});
test('late PiP updates, stops, and old media callbacks cannot disturb a newer listening session', async () => {
  const f = backgroundFixture();
  await f.media.update(call('startFloating', { title: '短剧', playing: true, hasNext: true }), 'floating');
  const retired = f.sessions[0];
  await f.media.update(call('startListenForeground', { title: '听书', playing: true, hasNext: true,
    coverUrl: 'https://example.invalid/cover.png' }));
  await f.media.update(call('updateFloating', { title: '迟到的标题', playing: false }), 'floating', false);
  await f.media.stop('floating'); retired.listeners.get('playNext')();
  const current = f.sessions[1];
  assert.equal(current.destroyed, false); assert.equal(current.metadata.at(-1).title, '听书');
  assert.equal(current.metadata.at(-1).mediaImage, 'https://example.invalid/cover.png');
  assert.equal(f.counts.stops, 1); assert.deepEqual(f.actions, []);
  await f.media.stop('listen'); assert.equal(current.destroyed, true); assert.equal(f.counts.stops, 2);
});
