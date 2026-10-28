import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult,
  EventChannel, StreamHandler, EventSink } from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { settings } from '@kit.BasicServicesKit';

// Physical pixels, relative to the current window. Flutter converts using its
// own view density so split-window and rotation updates use the same units.
export class DisplayPlugin implements FlutterPlugin, MethodCallHandler, StreamHandler {
  private context: common.UIAbilityContext;
  private method: MethodChannel | null = null;
  private channel: EventChannel | null = null;
  private sink: EventSink | null = null;
  private win: window.Window | null = null;
  private originalOrientation: window.Orientation | null = null;
  private active: boolean = true;
  private brightnessSession: string = '';
  private brightnessWindow: window.Window | null = null;
  private originalBrightness: number | null = null;
  private brightnessQueue: Promise<void> = Promise.resolve();
  private windowChanged = (event: window.WindowEventType): void => {
    if (event !== window.WindowEventType.WINDOW_HIDDEN) { return; }
    const session = this.brightnessSession;
    this.brightnessQueue = this.brightnessQueue.then(async () => {
      if (session === this.brightnessSession) { await this.finishBrightness(); }
    }).catch(() => {});
  };
  private avoided = (_event: window.AvoidAreaOptions): void => { this.publish(); };
  private resized = (_size: window.Size): void => { this.publish(); };
  constructor(context: common.UIAbilityContext) { this.context = context; }
  getUniqueClassName(): string { return 'FqDisplayPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.method = new MethodChannel(binding.getBinaryMessenger(), 'fqapp/display');
    this.method.setMethodCallHandler(this);
    this.channel = new EventChannel(binding.getBinaryMessenger(), 'fqapp/display/events');
    this.channel.setStreamHandler(this);
  }
  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.active = false; this.stop();
    this.brightnessQueue = this.brightnessQueue.then(() => this.finishBrightness(true)).catch(() => {});
    this.method?.setMethodCallHandler(null); this.channel?.setStreamHandler(null);
  }
  onListen(_args: Object, sink: EventSink): void {
    this.sink = sink;
    this.connect().then(() => this.publish()).catch(() => {});
  }
  onCancel(_args: Object): void { this.stop(); }
  private stop(): void {
    this.sink = null;
    this.win?.off('avoidAreaChange', this.avoided);
    this.win?.off('windowSizeChange', this.resized);
    this.win = null;
  }
  private async connect(): Promise<void> {
    if (this.win) { return; }
    const win = await window.getLastWindow(this.context);
    if (!this.active || this.win) { return; }
    this.win = win;
    win.on('avoidAreaChange', this.avoided);
    win.on('windowSizeChange', this.resized);
  }
  private metrics(): Map<string, Object> {
    const reply = new Map<string, Object>();
    const win = this.win;
    if (!win) { return reply; }
    const bounds = win.getWindowProperties().windowRect;
    // Native avoid areas are authoritative after rotation. Flutter's cached
    // portrait viewPadding/displayFeature can otherwise leave an extra top gap.
    const areas = [win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT),
      win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM),
      win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)];
    let topInset = 0; let bottomInset = 0; let leftInset = 0; let rightInset = 0;
    for (const area of areas) {
      const top = area.topRect; const bottom = area.bottomRect;
      const left = area.leftRect; const right = area.rightRect;
      if (top.width > 0 && top.height > 0) { topInset = Math.max(topInset, top.top + top.height); }
      if (bottom.width > 0 && bottom.height > 0) { bottomInset = Math.max(bottomInset, bounds.height - bottom.top); }
      if (left.width > 0 && left.height > 0) { leftInset = Math.max(leftInset, left.left + left.width); }
      if (right.width > 0 && right.height > 0) { rightInset = Math.max(rightInset, bounds.width - right.left); }
    }
    reply.set('top', topInset); reply.set('bottom', bottomInset);
    reply.set('left', leftInset); reply.set('right', rightInset);
    reply.set('width', bounds.width); reply.set('height', bounds.height);
    return reply;
  }
  private publish(): void { if (this.win && this.sink) { this.sink.success(this.metrics()); } }
  private async setOrientation(direction: string): Promise<void> {
    hilog.info(0x0000, 'FqDisplay', 'orientation request %{public}s', direction);
    if (direction !== 'portrait' && direction !== 'landscape' && direction !== 'restore') {
      throw new Error('ORIENTATION');
    }
    await this.connect();
    const win = this.win;
    if (!win) { throw new Error('WINDOW'); }
    const before = win.getWindowProperties();
    hilog.info(0x0000, 'FqDisplay', 'window %{public}d type %{public}d preferred %{public}d size %{public}dx%{public}d',
      before.id, before.type, win.getPreferredOrientation(), before.windowRect.width, before.windowRect.height);
    if (direction === 'restore') {
      if (this.originalOrientation !== null) {
        await win.setPreferredOrientation(this.originalOrientation);
        this.originalOrientation = null;
      }
      return;
    }
    const original = this.originalOrientation ?? win.getPreferredOrientation();
    await win.setPreferredOrientation(direction === 'landscape' ? window.Orientation.LANDSCAPE : window.Orientation.PORTRAIT);
    hilog.info(0x0000, 'FqDisplay', 'orientation accepted %{public}d', win.getPreferredOrientation());
    this.originalOrientation = original;
  }
  private async beginBrightness(session: string): Promise<number> {
    if (!this.active) { throw new Error('DETACHED'); }
    if (session !== this.brightnessSession) {
      await this.finishBrightness();
      const win = await window.getLastWindow(this.context);
      this.originalBrightness = win.getWindowProperties().brightness;
      this.brightnessWindow = win;
      this.brightnessSession = session;
      win.on('windowEvent', this.windowChanged);
    }
    const level = this.brightnessWindow?.getWindowProperties().brightness ?? -1;
    if (level >= 0) { return Math.max(0.02, Math.min(1, level)); }
    // The window reports -1 while following the system. Read, but never write,
    // the system setting to avoid jumping from a hard-coded level on first drag.
    try {
      const raw = await settings.getValue(this.context, settings.display.SCREEN_BRIGHTNESS_STATUS);
      if (raw && raw.trim().length > 0) {
        const value = Number(raw);
        if (Number.isFinite(value) && value >= 0 && value <= 255) {
          return Math.max(0.02, value / 255);
        }
      }
    } catch (_) {}
    return 0.5;
  }
  private async finishBrightness(detaching: boolean = false): Promise<void> {
    const win = this.brightnessWindow;
    try {
      if (win && this.originalBrightness !== null) {
        await win.setWindowBrightness(this.originalBrightness);
      }
    } catch (error) {
      // Retry restoration on the next end/begin while the engine is attached.
      if (!detaching) { throw error as Error; }
    }
    try {
      win?.off('windowEvent', this.windowChanged);
    } finally {
      this.brightnessSession = '';
      this.brightnessWindow = null;
      this.originalBrightness = null;
    }
  }
  private brightnessCall(call: MethodCall, result: MethodResult): void {
    this.brightnessQueue = this.brightnessQueue.then(async () => {
      try {
        const session = call.argument('session') as string;
        if (typeof session !== 'string' || !session || session.length > 128) { throw new Error('SESSION'); }
        if (call.method === 'beginPlayerBrightness') {
          result.success(await this.beginBrightness(session)); return;
        }
        if (session !== this.brightnessSession || !this.brightnessWindow) {
          result.success(call.method === 'setPlayerBrightness' ? false : null); return;
        }
        if (call.method === 'endPlayerBrightness') {
          await this.finishBrightness(); result.success(null); return;
        }
        const value = call.argument('brightness') as number;
        if (!Number.isFinite(value) || value < 0.02 || value > 1) { throw new Error('BRIGHTNESS'); }
        await this.brightnessWindow.setWindowBrightness(value);
        result.success(true);
      } catch (_) { result.error('PLAYER_BRIGHTNESS_FAILED', '播放亮度设置未能完成', null); }
    });
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'beginPlayerBrightness' || call.method === 'setPlayerBrightness' ||
      call.method === 'endPlayerBrightness') {
      this.brightnessCall(call, result); return;
    }
    if (call.method === 'setOrientation') {
      this.setOrientation(call.argument('orientation') as string).then(() => result.success(null))
        .catch(() => {
          hilog.error(0x0000, 'FqDisplay', 'orientation failed');
          result.error('ORIENTATION_FAILED', '屏幕方向设置失败', null);
        });
      return;
    }
    if (call.method !== 'cutoutInsets') { result.notImplemented(); return; }
    this.connect().then(() => result.success(this.metrics()))
      .catch(() => result.error('DISPLAY_UNAVAILABLE', '窗口避让区域暂不可用', null));
  }
}
