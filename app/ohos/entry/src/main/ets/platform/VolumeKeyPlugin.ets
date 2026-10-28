import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { KeyCode } from '@kit.InputKit';

export class VolumeKeyPlugin implements FlutterPlugin, MethodCallHandler {
  private static current: VolumeKeyPlugin | null = null;
  private channel: MethodChannel | null = null;
  private enabled: boolean = false;
  private context: common.UIAbilityContext;
  private win: window.Window | null = null;
  private held: Set<number> = new Set();
  private active: boolean = true;
  private focused: boolean = true;
  private changed = (event: window.WindowEventType): void => {
    if (event === window.WindowEventType.WINDOW_HIDDEN || event === window.WindowEventType.WINDOW_INACTIVE) {
      this.focused = false; this.held.clear();
    } else if (event === window.WindowEventType.WINDOW_ACTIVE) {
      this.focused = true;
    }
  };
  constructor(context: common.UIAbilityContext) { this.context = context; }
  getUniqueClassName(): string { return 'FqVolumeKeyPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    VolumeKeyPlugin.current = this;
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'fqapp/volume-key');
    this.channel.setMethodCallHandler(this);
    window.getLastWindow(this.context).then(win => {
      if (!this.active) { return; }
      this.win = win; win.on('windowEvent', this.changed);
    }).catch(() => {});
  }
  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.active = false; this.enabled = false; this.held.clear();
    this.channel?.setMethodCallHandler(null); this.channel = null;
    this.win?.off('windowEvent', this.changed); this.win = null;
    if (VolumeKeyPlugin.current === this) { VolumeKeyPlugin.current = null; }
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'setEnabled') { result.notImplemented(); return; }
    if (typeof call.args !== 'boolean') { result.error('INVALID_ARGUMENT', '音量键设置无效', null); return; }
    this.enabled = call.args; this.held.clear(); result.success(null);
  }
  static dispatch(event: KeyEvent): boolean {
    const owner = VolumeKeyPlugin.current;
    if (!owner || !owner.enabled || !owner.focused || !owner.channel) { return false; }
    const code = event.keyCode;
    if (code !== KeyCode.KEYCODE_VOLUME_UP && code !== KeyCode.KEYCODE_VOLUME_DOWN) { return false; }
    if (event.type === KeyType.Down && !owner.held.has(code)) {
      owner.held.add(code);
      owner.channel.invokeMethod('volumeKey', code === KeyCode.KEYCODE_VOLUME_DOWN ? 1 : -1);
    } else if (event.type === KeyType.Up) { owner.held.delete(code); }
    return true;
  }
}
