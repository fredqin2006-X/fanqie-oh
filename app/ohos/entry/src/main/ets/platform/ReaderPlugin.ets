import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult,
  EventChannel, StreamHandler, EventSink } from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { batteryInfo } from '@kit.BasicServicesKit';
import { DocumentPlugin } from './DocumentPlugin';

// Reader and media hold independent wake leases, so closing an old reader cannot
// turn off a newer player's keep-awake request. All changes are window-scoped.
export class WindowPolicy {
  private wake: Set<string> = new Set();
  private baselineWake: boolean | null = null;
  private queue: Promise<void> = Promise.resolve();
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  keep(owner: string, on: boolean): Promise<void> {
    const task = this.queue.then(async () => {
      const win = await window.getLastWindow(this.context);
      if (!on && !this.wake.has(owner) && this.baselineWake === null) { return; }
      if (on) {
        if (this.baselineWake === null) { this.baselineWake = win.getWindowProperties().isKeepScreenOn; }
        this.wake.add(owner);
      } else { this.wake.delete(owner); }
      await win.setWindowKeepScreenOn(this.wake.size > 0 || this.baselineWake === true);
      if (this.wake.size === 0) { this.baselineWake = null; }
    });
    this.queue = task.catch(() => {}); return task;
  }
}

export class ReaderPlugin implements FlutterPlugin, MethodCallHandler, StreamHandler {
  private channel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private sink: EventSink | null = null;
  private session: string = '';
  private brightness: number | null = null;
  private bars: Array<'status' | 'navigation'> | null = null;
  private timer: number = -1;
  private queue: Promise<void> = Promise.resolve();
  private context: common.UIAbilityContext;
  private documents: DocumentPlugin;
  private policy: WindowPolicy;
  constructor(context: common.UIAbilityContext, documents: DocumentPlugin, policy: WindowPolicy) {
    this.context = context; this.documents = documents; this.policy = policy;
  }
  getUniqueClassName(): string { return 'FqReaderPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'fqapp/reader'); this.channel.setMethodCallHandler(this);
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), 'fqapp/reader/events'); this.eventChannel.setStreamHandler(this);
    this.timer = setInterval(() => { if (this.session) { this.status().then(value => this.sink?.success(value)).catch(() => {}); } }, 30000);
  }
  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null); this.eventChannel?.setStreamHandler(null); clearInterval(this.timer);
    this.sink = null; this.queue = this.queue.then(() => this.finish()).catch(() => {});
  }
  onListen(_args: Object, events: EventSink): void { this.sink = events; }
  onCancel(_args: Object): void { this.sink = null; }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.queue = this.queue.then(async () => {
      try {
        if (call.method === 'pickFont') { result.success(await this.documents.pickFont()); return; }
        const session = call.argument('session') as string;
        if (call.method === 'start') {
          if (typeof session !== 'string' || session.length > 128) { throw new Error('SESSION'); }
          if (this.session && this.session !== session) { await this.finish(); }
          const win = await window.getLastWindow(this.context);
          if (this.brightness === null) { this.brightness = win.getWindowProperties().brightness; }
          this.session = session; await this.setBrightness(call.argument('brightness') as number);
          result.success(await this.status()); return;
        }
        if (session !== this.session || !this.session) { result.success(call.method === 'setBrightness' ? false : null); return; }
        switch (call.method) {
          case 'setBrightness': await this.setBrightness(call.argument('brightness') as number); result.success(true); break;
          case 'keepScreenOn': await this.policy.keep('reader:' + this.session, call.argument('on') === true); result.success(null); break;
          case 'setImmersive': {
            const win = await window.getLastWindow(this.context);
            if (this.bars === null) {
              const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
              const nav = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
              this.bars = [];
              if (area.topRect.height > 0) { this.bars.push('status'); }
              if (area.bottomRect.height > 0 || nav.bottomRect.height > 0) { this.bars.push('navigation'); }
            }
            await win.setWindowSystemBarEnable(call.argument('enabled') === true ? [] : this.bars); result.success(null); break;
          }
          case 'suspend': case 'stop': await this.finish(); result.success(null); break;
          default: result.notImplemented();
        }
      } catch (_) { result.error('READER_DEVICE_FAILED', '阅读设备设置未能完成', null); }
    });
  }
  private async setBrightness(value: number): Promise<void> {
    if (!Number.isFinite(value) || (value !== -1 && (value < 0.02 || value > 1))) { throw new Error('BRIGHTNESS'); }
    await (await window.getLastWindow(this.context)).setWindowBrightness(value);
  }
  private async status(): Promise<Map<string, Object>> {
    const win = await window.getLastWindow(this.context); const reply = new Map<string, Object>();
    reply.set('session', this.session); reply.set('timestamp', Date.now()); reply.set('battery', batteryInfo.batterySOC);
    reply.set('charging', batteryInfo.chargingStatus === batteryInfo.BatteryChargeState.ENABLE || batteryInfo.chargingStatus === batteryInfo.BatteryChargeState.FULL);
    const current = win.getWindowProperties().brightness;
    if (current >= 0) { reply.set('systemBrightness', current); } return reply;
  }
  private async finish(): Promise<void> {
    const owner = this.session; this.session = '';
    const win = await window.getLastWindow(this.context);
    try { if (this.brightness !== null) { await win.setWindowBrightness(this.brightness); } }
    finally {
      this.brightness = null;
      try { if (this.bars !== null) { await win.setWindowSystemBarEnable(this.bars); } }
      finally { this.bars = null; if (owner) { await this.policy.keep('reader:' + owner, false); } }
    }
  }
}
