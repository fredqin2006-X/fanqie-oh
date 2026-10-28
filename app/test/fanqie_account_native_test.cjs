'use strict';
// Exercise the actual ArkTS service with SDK substitutes. Does not sign in to
// an account or establish native WebView/device acceptance.
const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

function fixture() {
  const source = fs.readFileSync(path.join(__dirname,
    '../ohos/entry/src/main/ets/platform/FanqieAccountPlugin.ets'), 'utf8');
  const compiled = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
  }});
  const state = { routes: [], clear: 0, storage: 0, failOpen: false };
  const dependencies = {
    '@ohos/flutter_ohos': {}, '@kit.AbilityKit': {},
    '@kit.ArkUI': { window: { getLastWindow: async () => ({ getUIContext: () => ({
      getRouter: () => ({ pushUrl: async route => {
        if (state.failOpen) throw Error('closed'); state.routes.push(route.url);
      }}),
    }) }) } },
    '@kit.ArkWeb': { webview: {
      WebCookieManager: { clearAllCookies: async () => { state.clear++; } },
      WebStorage: { deleteAllData: () => { state.storage++; } },
    } },
  };
  const exports = {};
  vm.runInNewContext(compiled.outputText, { exports, require: name => dependencies[name] });
  const plugin = new exports.FanqieAccountPlugin({});
  const call = (method, args = {}) => new Promise((resolve, reject) => {
    plugin.onMethodCall({ method, argument: key => args[key] }, {
      success: resolve, error: code => reject(Error(code)), notImplemented: () => reject(Error('unsupported')),
    });
  });
  return { state, plugin, call, session: exports.FanqieLoginSession };
}
const tick = () => new Promise(resolve => setImmediate(resolve));

test('official login allowlist rejects HTTP, userinfo and suffix impersonation', () => {
  const { session } = fixture();
  for (const value of ['https://fanqienovel.com/', 'https://sso.snssdk.com/login', 'https://a.bytedance.com:443/path']) {
    assert.equal(session.allowed(value), true, value);
  }
  for (const value of ['http://fanqienovel.com/', 'file:///data/login', 'https://fanqienovel.com.evil.test/',
    'https://name@fanqienovel.com/', 'https://fanqienovel.com@evil.test', 'https://fanqienovel.com:444/', 'javascript:alert(1)']) {
    assert.equal(session.allowed(value), false, value);
  }
});
test('only bounded cookies with a nonempty official session can be returned', () => {
  const { session } = fixture();
  assert.equal(session.sessionCookie('a=b; sessionid=value'), 'a=b; sessionid=value');
  for (const value of ['', 'sessionid=', 'a=sessionid=value', 'token=value', 'sessionid=' + 'x'.repeat(13000)]) {
    assert.equal(session.sessionCookie(value), null);
  }
});
test('cancel resolves once and a previous page cannot complete the next login', async () => {
  const f = fixture();
  const old = f.call('login', { dark: true }); const id = f.session.id;
  await tick(); assert.deepEqual(f.state.routes, ['pages/FanqieLogin']);
  await assert.rejects(f.call('login'), /LOGIN_BUSY/);
  await assert.rejects(f.call('clearSession'), /LOGIN_BUSY/);
  await f.call('cancelLogin'); assert.equal(await old, null);
  const next = f.call('login');
  f.session.finish(id, 'old'); assert.notEqual(f.session.pending, null);
  f.session.finish(f.session.id, 'sessionid=new'); assert.equal(await next, 'sessionid=new');
});
test('failed route clears pending request and allows logout/retry', async () => {
  const f = fixture(); f.state.failOpen = true;
  await assert.rejects(f.call('login'), /LOGIN_UNAVAILABLE/);
  assert.equal(f.session.pending, null);
  await f.call('clearSession'); assert.equal(f.state.clear, 1); assert.equal(f.state.storage, 1);
});
test('engine detach cancels a pending login without clearing the saved official session', async () => {
  const f = fixture(); const pending = f.call('login'); await tick();
  f.plugin.onDetachedFromEngine({}); assert.equal(await pending, null); assert.equal(f.state.clear, 0);
});
