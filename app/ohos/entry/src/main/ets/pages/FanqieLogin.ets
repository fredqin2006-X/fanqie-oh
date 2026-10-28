import { webview } from '@kit.ArkWeb';
import { FanqieLoginSession } from '../platform/FanqieAccountPlugin';

interface ViewportMetrics { fit: boolean; editing: boolean; factor: number; }
interface LoginRouteParams { session: number; }

// Presentation-only metrics, matching Android's explicit verification fit.
const VIEWPORT_SCRIPT: string = `(() => {
  if (!window.__fqViewport) {
    window.__fqViewport = { sent: 0, seen: 0 };
    const editable = el => el instanceof Element && (el.matches('input,textarea') || el.isContentEditable);
    document.addEventListener('focusin', event => {
      if (editable(event.target)) window.__fqViewport.seen = window.__fqViewport.sent;
    }, true);
    document.addEventListener('click', event => {
      if (editable(event.target)) return;
      const path = event.composedPath ? event.composedPath() : [event.target];
      if (!path.some(el => el instanceof Element && /^(发送验证码|获取验证码|重新发送)$/.test((el.textContent || '').replace(/\\s+/g, '')))) return;
      if (editable(document.activeElement)) document.activeElement.blur();
      window.__fqViewport.sent++;
    }, true);
  }
  const state = window.__fqViewport;
  const rects = [...document.querySelectorAll('[id*="captcha"],[class*="captcha"],iframe[src*="captcha"],iframe[src*="verify"],[id*="verify-bar"]')]
    .map(el => el.getBoundingClientRect()).filter(r => r.width > 100 && r.height > 80 && r.bottom > 0 && r.right > 0);
  const width = Math.max(document.documentElement.scrollWidth, document.body ? document.body.scrollWidth : 0, ...rects.map(r => r.right + Math.max(0, -r.left)));
  const height = rects.length ? Math.max(...rects.map(r => r.height)) : 0;
  const vp = window.visualViewport;
  const vw = vp ? vp.width : innerWidth, vh = vp ? vp.height : innerHeight;
  const el = document.activeElement;
  const editing = el instanceof Element && (el.matches('input,textarea') || el.isContentEditable);
  const fit = state.sent !== state.seen && !editing;
  state.seen = state.sent;
  return {fit, editing, factor: Math.min(1, vw / (width + 16), height > 0 ? vh / (height + 24) : 1)};
})()`;

@Entry
@Component
struct FanqieLogin {
  private controller: webview.WebviewController = new webview.WebviewController();
  private session: number = 0;
  private poll: number = -1;
  private alive: boolean = false;
  private fitting: boolean = false;
  @State private dark: boolean = false;
  @State private eink: boolean = false;
  @State private progress: number = 0;
  @State private hint: string = '登录状态会在本机保留。验证时自动缩放，也可双指放大。';
  @State private completing: boolean = false;

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as LoginRouteParams;
    this.session = params.session;
    if (this.session !== FanqieLoginSession.id || !FanqieLoginSession.pending) {
      this.getUIContext().getRouter().back(); return;
    }
    this.alive = true;
    this.dark = FanqieLoginSession.dark; this.eink = FanqieLoginSession.eink;
    FanqieLoginSession.closePage = () => {
      if (this.alive) { this.getUIContext().getRouter().back(); }
    };
    webview.WebCookieManager.fetchCookie(FanqieLoginSession.home).then(cookie => {
      if (this.alive && FanqieLoginSession.sessionCookie(cookie)) { this.hint = '已保留上次登录，可直接读取书架。验证时会自动缩放。'; }
    }).catch(() => {});
  }
  aboutToDisappear(): void {
    this.alive = false; this.stopPolling();
    // A router back or engine detach resolves the original call exactly once.
    FanqieLoginSession.finish(this.session, null);
  }
  onBackPress(): boolean { FanqieLoginSession.finish(this.session, null); return true; }
  private stopPolling(): void { if (this.poll >= 0) { clearInterval(this.poll); this.poll = -1; } }
  private async fit(force: boolean): Promise<void> {
    if (!this.alive || this.fitting) { return; }
    this.fitting = true;
    try {
      if (!FanqieLoginSession.allowed(this.controller.getUrl())) { return; }
      const metrics = JSON.parse(await this.controller.runJavaScript(VIEWPORT_SCRIPT)) as ViewportMetrics;
      if (!this.alive || (!force && (!metrics.fit || metrics.editing))) { return; }
      if (Number.isFinite(metrics.factor) && metrics.factor < 0.98) { this.controller.zoom(Math.max(0.1, metrics.factor)); }
    } catch (_) {} finally { this.fitting = false; }
  }
  private async complete(): Promise<void> {
    if (this.completing) { return; } this.completing = true;
    try {
      const cookie = FanqieLoginSession.sessionCookie(await webview.WebCookieManager.fetchCookie(FanqieLoginSession.home));
      if (!this.alive) { return; }
      if (cookie) { FanqieLoginSession.finish(this.session, cookie); }
      else { this.hint = '请先完成手机号登录和验证，再点击下方按钮。'; }
    } catch (_) { if (this.alive) { this.hint = '登录状态读取失败，请重试。'; } }
    finally { this.completing = false; }
  }
  build() {
    Column() {
      Row() {
        Button('返回', { type: ButtonType.Normal }).backgroundColor(Color.Transparent)
          .fontColor(this.dark ? '#f4f4f4' : '#202020').height(48)
          .onClick(() => FanqieLoginSession.finish(this.session, null))
        Text('番茄官方登录').fontSize(17).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
          .fontColor(this.dark ? '#f4f4f4' : '#202020')
        Button('适应全页', { type: ButtonType.Normal }).backgroundColor(Color.Transparent)
          .fontColor(this.dark ? '#f4f4f4' : '#202020').fontSize(13).height(48).onClick(() => { this.fit(true); })
      }.width('100%').padding({ left: 8, right: 8 })
      Text(this.hint).fontSize(12).fontColor(this.dark ? '#b6b6b6' : '#666666')
        .width('100%').padding({ left: 16, right: 16, top: 4, bottom: 12 })
      Progress({ value: this.progress, total: 100, type: ProgressType.Linear }).height(2)
        .color(this.eink ? (this.dark ? '#ffffff' : '#000000') : '#e95036')
      Web({ src: FanqieLoginSession.loginUrl, controller: this.controller })
        .layoutWeight(1).width('100%').javaScriptAccess(true).domStorageAccess(true)
        .fileAccess(false).mixedMode(MixedMode.None).zoomAccess(true).multiWindowAccess(false)
        .onLoadIntercept(event => !FanqieLoginSession.allowed(event.data.getRequestUrl()))
        .onProgressChange(event => { this.progress = event.newProgress; })
        .onPageBegin(() => { this.stopPolling(); })
        .onPageEnd(() => { this.stopPolling(); this.poll = setInterval(() => { this.fit(false); }, 650); })
        .onSslErrorEventReceive(event => { event.handler.handleCancel(); this.hint = '官方页面安全连接失败，请返回后重试。'; })
      Column() {
        Button('完成登录，读取书架', { type: ButtonType.Normal }).width('100%').height(50).borderRadius(14)
          .fontSize(15).fontColor(Color.White).backgroundColor(this.eink ? '#202020' : '#e95036')
          .enabled(!this.completing).onClick(() => { this.complete(); })
        Text('登录与人机验证请在官方页面内完成').fontSize(11).fontColor(this.dark ? '#b6b6b6' : '#666666')
          .margin({ top: 8 })
      }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 12 })
    }.width('100%').height('100%').backgroundColor(this.dark ? '#151515' : '#ffffff')
  }
}
