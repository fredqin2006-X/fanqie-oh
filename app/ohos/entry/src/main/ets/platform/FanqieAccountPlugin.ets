import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';

// The official page owns login and verification. No JS bridge reads form fields,
// cookies or challenge answers. Credentials are returned only on the user's tap.
export class FanqieLoginSession {
  static readonly home: string = 'https://fanqienovel.com/';
  static readonly loginUrl: string = 'https://fanqienovel.com/main/writer/login';
  static id: number = 0;
  static dark: boolean = false;
  static eink: boolean = false;
  static pending: MethodResult | null = null;
  static closePage: (() => void) | null = null;

  static allowed(value: string): boolean {
    return /^https:\/\/(?:[a-z0-9-]+\.)*(?:fanqienovel\.com|snssdk\.com|bytedance\.com|zijieapi\.com)(?::443)?(?:[/?#]|$)/i.test(value);
  }
  static sessionCookie(cookie: string): string | null {
    if (cookie.length > 12 * 1024 || /[\r\n\u0000]/.test(cookie)) { return null; }
    return cookie.split(';').some(part => /^(?:sessionid|sessionid_ss|sid_tt)=[^\s;]+$/.test(part.trim())) ? cookie : null;
  }
  static finish(id: number, cookie: string | null): void {
    if (id !== FanqieLoginSession.id) { return; }
    const result = FanqieLoginSession.pending;
    const close = FanqieLoginSession.closePage;
    FanqieLoginSession.pending = null; FanqieLoginSession.closePage = null;
    try { if (close) { close(); } }
    catch (_) { /* A closing window must not strand the pending Flutter call. */ }
    finally { if (result) { result.success(cookie); } }
  }
}

export class FanqieAccountPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private clearing: boolean = false;
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  getUniqueClassName(): string { return 'FqFanqieAccountPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'fqapp/fanqie_account');
    this.channel.setMethodCallHandler(this);
  }
  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    FanqieLoginSession.finish(FanqieLoginSession.id, null);
    this.channel?.setMethodCallHandler(null); this.channel = null;
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'cancelLogin') {
      FanqieLoginSession.finish(FanqieLoginSession.id, null); result.success(null); return;
    }
    if (call.method !== 'login' && call.method !== 'clearSession') { result.notImplemented(); return; }
    if (FanqieLoginSession.pending || this.clearing) { result.error('LOGIN_BUSY', '登录窗口正在处理', null); return; }
    if (call.method === 'clearSession') {
      this.clearing = true;
      webview.WebCookieManager.clearAllCookies().then(() => {
        webview.WebStorage.deleteAllData(); result.success(null);
      }).catch(() => result.error('LOGOUT_FAILED', '清除登录状态失败，请重试', null))
        .finally(() => { this.clearing = false; });
      return;
    }
    const id = ++FanqieLoginSession.id;
    FanqieLoginSession.dark = call.argument('dark') === true;
    FanqieLoginSession.eink = call.argument('eink') === true;
    FanqieLoginSession.pending = result;
    window.getLastWindow(this.context).then(async win => {
      if (FanqieLoginSession.id !== id || !FanqieLoginSession.pending) { return; }
      await win.getUIContext().getRouter().pushUrl({ url: 'pages/FanqieLogin', params: { session: id } });
    }).catch(() => {
      if (FanqieLoginSession.id === id && FanqieLoginSession.pending === result) {
        FanqieLoginSession.pending = null;
        result.error('LOGIN_UNAVAILABLE', '无法打开官方登录窗口，请重试', null);
      }
    });
  }
}
