import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult,
  EventChannel, StreamHandler, EventSink } from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

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
    const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
    const bounds = win.getWindowProperties().windowRect;
    const top = area.topRect; const bottom = area.bottomRect;
    const left = area.leftRect; const right = area.rightRect;
    reply.set('top', top.width > 0 && top.height > 0 ? Math.max(0, top.top + top.height) : 0);
    reply.set('bottom', bottom.width > 0 && bottom.height > 0 ? Math.max(0, bounds.height - bottom.top) : 0);
    reply.set('left', left.width > 0 && left.height > 0 ? Math.max(0, left.left + left.width) : 0);
    reply.set('right', right.width > 0 && right.height > 0 ? Math.max(0, bounds.width - right.left) : 0);
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
  onMethodCall(call: MethodCall, result: MethodResult): void {
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
