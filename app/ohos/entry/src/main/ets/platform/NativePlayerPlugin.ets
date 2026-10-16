import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult,
  EventChannel, StreamHandler, EventSink, TextureRegistry, SurfaceTextureEntry } from '@ohos/flutter_ohos';
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WindowPolicy } from './ReaderPlugin';
import { BackgroundMedia } from './BackgroundMedia';

class PlayerSession {
  id: number = 0;
  texture: SurfaceTextureEntry | null;
  player: media.AVPlayer | null = null;
  disposed: boolean = false;
  failed: boolean = false;
  ready: boolean = false;
  playWhenReady: boolean = false;
  volume: number = 1;
  rate: number = 1;
  sourceId: string = '';
  base: string = '';
  file: number = -1;
  queue: Promise<void> = Promise.resolve();
  stage: string = 'create';
  constructor(id: number, texture: SurfaceTextureEntry | null) { this.id = id; this.texture = texture; }
}
interface MediaSourceReply { id: string; url: string; }

export class NativePlayerPlugin implements FlutterPlugin, MethodCallHandler, StreamHandler {
  private method: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private events: EventSink | null = null;
  private textures: TextureRegistry | null = null;
  private sessions: Map<number, PlayerSession> = new Map();
  private nextId: number = 1;
  private background: BackgroundMedia | null = null;
  private context: common.UIAbilityContext;
  private windowPolicy: WindowPolicy;
  constructor(context: common.UIAbilityContext, windowPolicy: WindowPolicy) { this.context = context; this.windowPolicy = windowPolicy; }
  getUniqueClassName(): string { return 'FqNativePlayerPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.textures = binding.getTextureRegistry();
    this.method = new MethodChannel(binding.getBinaryMessenger(), 'fqapp/native_player');
    this.method.setMethodCallHandler(this);
    this.background = new BackgroundMedia(this.context, this.method);
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), 'fqapp/native_player/events');
    this.eventChannel.setStreamHandler(this);
  }
  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.method?.setMethodCallHandler(null); this.eventChannel?.setStreamHandler(null);
    this.events = null;
    this.background?.stop().catch(() => {}); this.background = null;
    this.windowPolicy.keep('media', false).catch(() => {});
    for (const item of this.sessions.values()) { this.dispose(item); }
    this.sessions.clear(); this.textures = null; this.method = null; this.eventChannel = null;
  }
  onListen(_args: Object, events: EventSink): void { this.events = events; }
  onCancel(_args: Object): void { this.events = null; }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'create') {
      const textures = this.textures;
      if (!textures || this.sessions.size >= 8) { result.error('PLAYER_LIMIT', '播放器资源暂不可用', null); return; }
      const url = call.argument('cdnUrl') as string;
      const key = call.argument('keyHex') as string;
      const base = call.argument('loopbackBase') as string;
      if (typeof url !== 'string' || typeof key !== 'string') { result.error('INVALID_SOURCE', '播放地址无效', null); return; }
      const item = new PlayerSession(this.nextId++, call.argument('audioOnly') === true ? null : textures.registerTexture(textures.getTextureId()));
      item.base = typeof base === 'string' ? base : '';
      this.sessions.set(item.id, item);
      const reply = new Map<string, Object>(); reply.set('playerId', item.id); result.success(reply);
      this.prepare(item, url, key).catch((error: Error) => this.fail(item, error));
      return;
    }
    if (call.method === 'setKeepScreenOn') {
      this.windowPolicy.keep('media', call.argument('on') === true).then(() => {
        result.success(null);
      }).catch(() => result.error('WINDOW_UNAVAILABLE', '无法设置屏幕常亮', null));
      return;
    }
    if (call.method === 'startListenForeground' || call.method === 'stopListenForeground') {
      const task = call.method === 'startListenForeground' ? this.background?.update(call) : this.background?.stop();
      if (!task) { result.error('MEDIA_SESSION_DETACHED', '媒体会话已关闭', null); return; }
      task.then(() => result.success(null)).catch(() => result.error('MEDIA_SESSION_FAILED', '系统后台媒体会话未能启动', null)); return;
    }
    const id = call.argument('id') as number;
    const item = this.sessions.get(id);
    if (!item) {
      if (call.method === 'dispose') { result.success(null); }
      else { result.error('PLAYER_DISPOSED', '播放器已关闭', null); }
      return;
    }
    if (call.method === 'dispose') { this.sessions.delete(id); this.dispose(item).then(() => result.success(null)); return; }
    item.queue = item.queue.then(async () => {
      if (item.disposed || item.failed || !item.player || !item.ready) { result.error('PLAYER_NOT_READY', '播放器尚未准备好', null); return; }
      try {
        const player = item.player;
        switch (call.method) {
          case 'play':
            item.playWhenReady = true; this.emit(item, 'playWhenReady', true);
            if (player.state !== 'playing') { await player.play(); } break;
          case 'pause':
            item.playWhenReady = false; this.emit(item, 'playWhenReady', false);
            if (player.state === 'playing') { await player.pause(); } break;
          case 'seek': {
            const position = call.argument('positionMs') as number;
            if (!Number.isFinite(position) || position < 0) { throw new Error('INVALID_POSITION'); }
            player.seek(Math.min(position, Math.max(player.duration, 0)), media.SeekMode.SEEK_CLOSEST);
            this.emit(item, 'completed', false); break;
          }
          case 'setVolume': {
            const volume = call.argument('volume') as number;
            if (!Number.isFinite(volume) || volume < 0 || volume > 1) { throw new Error('INVALID_VOLUME'); }
            item.volume = volume; player.setVolume(volume); break;
          }
          case 'setRate': {
            const rate = call.argument('rate') as number;
            if (!Number.isFinite(rate) || rate < 0.125 || rate > 4) { throw new Error('INVALID_RATE'); }
            item.rate = rate; player.setPlaybackRate(rate); break;
          }
          default: result.notImplemented(); return;
        }
        result.success(null);
      } catch (_) { result.error('PLAYER_OPERATION_FAILED', '系统播放器未能完成操作', null); }
    });
  }

  private async prepare(item: PlayerSession, source: string, key: string): Promise<void> {
    item.stage = 'source';
    let playable = source;
    if (key.length > 0) {
      if (!/^[0-9a-fA-F]{32}$/.test(key) || !/^http:\/\/127\.0\.0\.1:\d+\/_session\/[0-9a-f]+$/.test(item.base)) {
        throw new Error('INVALID_ENCRYPTED_SOURCE');
      }
      const request = http.createHttp();
      try {
        const response = await request.request(item.base + '/harmony-media/open', {
          method: http.RequestMethod.POST, header: { 'Content-Type': 'application/json' },
          extraData: JSON.stringify({ cdnUrl: source, keyHex: key }),
          expectDataType: http.HttpDataType.STRING, connectTimeout: 10000, readTimeout: 25000,
          usingCache: false
        });
        if (response.responseCode !== 200) { throw new Error('CENC_SOURCE_REJECTED'); }
        const opened = JSON.parse(response.result as string) as MediaSourceReply;
        if (typeof opened.id !== 'string' || !/^[0-9a-f]{32}$/.test(opened.id) ||
          opened.url !== item.base + '/harmony-media/' + opened.id) { throw new Error('INVALID_MEDIA_REPLY'); }
        item.sourceId = opened.id; playable = opened.url;
      } finally { request.destroy(); }
    }
    if (item.disposed) { await this.releaseSource(item); return; }
    item.stage = 'player';
    const player = await media.createAVPlayer();
    if (item.disposed) { await player.release(); await this.releaseSource(item); return; }
    item.player = player;
    player.on('stateChange', (state: string) => {
      if (item.disposed || item.failed) { return; }
      if (state === 'initialized') {
        item.stage = 'surface';
        if (item.texture) { player.surfaceId = item.texture.getSurfaceId().toString(); }
        item.stage = 'prepare';
        player.prepare().catch((error: Error) => this.fail(item, error));
      } else if (state === 'prepared') {
        item.stage = 'prepared';
        item.ready = true;
        player.setVolume(item.volume); player.setPlaybackRate(item.rate);
        this.emit(item, 'created', item.texture ? item.texture.getTextureId() : 0);
        this.emit(item, 'duration', player.duration);
        this.emit(item, 'buffering', false);
        this.videoSize(item, player.width, player.height);
        hilog.info(0x0000, 'FqPlayer', 'prepared player=%{public}d duration=%{public}d', item.id, player.duration);
        if (item.playWhenReady) { player.play().catch((error: Error) => this.fail(item, error)); }
      } else if (state === 'playing') {
        this.emit(item, 'playing', true); this.emit(item, 'completed', false);
      } else if (state === 'paused' || state === 'stopped') {
        this.emit(item, 'playing', false);
      } else if (state === 'completed') {
        this.emit(item, 'playing', false); this.emit(item, 'completed', true);
      }
    });
    player.on('timeUpdate', (position: number) => this.emit(item, 'position', position));
    player.on('durationUpdate', (duration: number) => this.emit(item, 'duration', duration));
    player.on('videoSizeChange', (width: number, height: number) => this.videoSize(item, width, height));
    player.on('startRenderFrame', () => {
      this.emit(item, 'firstFrame', true);
      hilog.info(0x0000, 'FqPlayer', 'firstFrame player=%{public}d', item.id);
    });
    player.on('error', (error: BusinessError) => this.fail(item, error));
    player.on('bufferingUpdate', (type: media.BufferingInfoType, _value: number) => {
      if (type === media.BufferingInfoType.BUFFERING_START) { this.emit(item, 'buffering', true); }
      else if (type === media.BufferingInfoType.BUFFERING_END) { this.emit(item, 'buffering', false); }
    });
    player.on('audioInterrupt', (event: audio.InterruptEvent) => {
      if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE || event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
        item.playWhenReady = false; this.emit(item, 'playWhenReady', false);
        if (player.state === 'playing') { player.pause().catch(() => {}); }
      }
    });
    this.emit(item, 'buffering', true);
    item.stage = 'url';
    player.url = playable;
  }

  private emit(item: PlayerSession, event: string, value: Object): void {
    if (item.disposed || (item.failed && event !== 'error')) { return; }
    const data = new Map<string, Object>(); data.set('playerId', item.id); data.set('type', event); data.set('value', value);
    this.events?.success(data);
  }
  private videoSize(item: PlayerSession, width: number, height: number): void {
    if (item.disposed || item.failed || !item.texture || width <= 0 || height <= 0) { return; }
    this.textures?.setTextureBufferSize(item.texture.getTextureId(), width, height);
    const data = new Map<string, Object>(); data.set('playerId', item.id); data.set('type', 'videoSize');
    data.set('width', width); data.set('height', height); data.set('rotationCorrection', 0);
    this.events?.success(data);
  }
  private fail(item: PlayerSession, error: Error): void {
    // AVPlayer can report the same failure through its event and a rejected
    // prepare/play promise. Preserve the first cause and retire late callbacks.
    if (item.disposed || item.failed) { return; }
    item.failed = true;
    item.ready = false;
    item.playWhenReady = false;
    const code = (error as BusinessError).code;
    const detail = new Map<string, Object>(); detail.set('message', code === 5400106 ? '当前设备不支持此媒体编码' : '鸿蒙播放器无法准备或解码此媒体');
    if (typeof code === 'number') { detail.set('errorCode', code); }
    this.emit(item, 'error', detail);
    hilog.error(0x0000, 'FqPlayer', 'media failed player=%{public}d stage=%{public}s code=%{public}d', item.id, item.stage, typeof code === 'number' ? code : -1);
  }
  private async dispose(item: PlayerSession): Promise<void> {
    if (item.disposed) { return; }
    item.disposed = true;
    const textures = this.textures;
    try { await item.player?.release(); } catch (_) { /* release source and texture regardless */ }
    item.player = null;
    if (item.texture) { textures?.unregisterTexture(item.texture.getTextureId()); }
    // SurfaceTextureRegistryEntry.release() throws in the pinned engine;
    // unregisterTexture owns release of its native window and surface.
    await this.releaseSource(item);
  }
  private async releaseSource(item: PlayerSession): Promise<void> {
    const id = item.sourceId; item.sourceId = '';
    if (!id) { return; }
    const request = http.createHttp();
    try { await request.request(item.base + '/harmony-media/' + id, {
      method: http.RequestMethod.DELETE, connectTimeout: 2000, readTimeout: 2000, usingCache: false
    }); } catch (_) { /* core shutdown also cancels every source */ }
    finally { request.destroy(); }
  }
}
