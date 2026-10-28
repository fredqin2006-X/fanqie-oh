// Host-only behavior tests of the real ArkTS plugin after TypeScript transpilation.
// Use DevEco's TypeScript package through NODE_PATH; this is not an ArkTS build.
'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

const source = fs.readFileSync(path.join(__dirname,
  '../ohos/entry/src/main/ets/platform/DisplayPlugin.ets'), 'utf8');
const compiled = ts.transpileModule(source, {
  fileName: 'DisplayPlugin.ts', reportDiagnostics: true,
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
});
assert.deepEqual(compiled.diagnostics, []);

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

function fixture(initial = -1, system = '128') {
  const writes = [];
  const listeners = new Map();
  let brightness = initial;
  const state = { beforeSet: async () => {}, settingReads: 0, failSetting: false };
  const window = {
    getWindowProperties: () => ({ brightness }),
    async setWindowBrightness(value) {
      await state.beforeSet(value);
      brightness = value;
      writes.push(value);
    },
    on: (event, callback) => listeners.set(event, callback),
    off: (event, callback) => {
      if (listeners.get(event) === callback) listeners.delete(event);
    },
  };
  const dependencies = {
    '@ohos/flutter_ohos': {},
    '@kit.AbilityKit': {},
    '@kit.ArkUI': { window: {
      getLastWindow: async () => window,
      WindowEventType: { WINDOW_HIDDEN: 4 },
    } },
    '@kit.PerformanceAnalysisKit': { hilog: { info() {}, error() {} } },
    '@kit.BasicServicesKit': { settings: {
      display: { SCREEN_BRIGHTNESS_STATUS: 'screen_brightness' },
      async getValue(_context, key) {
        assert.equal(key, 'screen_brightness');
        state.settingReads++;
        if (state.failSetting) throw new Error('settings unavailable');
        return system;
      },
    } },
  };
  const exports = {};
  vm.runInNewContext(compiled.outputText, {
    exports,
    require: name => {
      assert.ok(Object.hasOwn(dependencies, name), `Unexpected dependency: ${name}`);
      return dependencies[name];
    },
  });
  const plugin = new exports.DisplayPlugin({});
  function call(method, session, value) {
    return new Promise((resolve, reject) => plugin.onMethodCall({
      method,
      argument: key => key === 'session' ? session : value,
    }, {
      success: resolve,
      error: code => reject(new Error(code)),
      notImplemented: () => reject(new Error('not implemented')),
    }));
  }
  return {
    ...state, state, writes, listeners, plugin,
    get brightness() { return brightness; },
    begin: session => call('beginPlayerBrightness', session),
    set: (session, value) => call('setPlayerBrightness', session, value),
    end: session => call('endPlayerBrightness', session),
    async hide() {
      listeners.get('windowEvent')?.(4);
      await plugin.brightnessQueue;
    },
    async detach() {
      plugin.onDetachedFromEngine({});
      await plugin.brightnessQueue;
    },
  };
}

test('system-following brightness restores -1 and removes its listener', async () => {
  const f = fixture();
  assert.equal(await f.begin('first'), 128 / 255);
  assert.equal(f.brightness, -1);
  assert.equal(await f.set('first', 0.75), true);
  await f.end('first');
  assert.deepEqual(f.writes, [0.75, -1]);
  assert.equal(f.listeners.size, 0);
});

test('an old end or write cannot alter a replacement session', async () => {
  const f = fixture(0.3);
  await f.begin('old');
  await f.set('old', 0.8);
  assert.equal(await f.begin('new'), 0.3);
  await f.set('new', 0.6);
  await f.end('old');
  assert.equal(await f.set('old', 1), false);
  assert.equal(f.brightness, 0.6);
  assert.equal(f.state.settingReads, 0);
  await f.end('new');
  assert.equal(f.brightness, 0.3);
});

test('end waits for a pending brightness write and restores last', async () => {
  const f = fixture();
  await f.begin('serial');
  const gate = deferred();
  f.state.beforeSet = value => value === 0.8 ? gate.promise : Promise.resolve();
  const write = f.set('serial', 0.8);
  const end = f.end('serial');
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.writes.length, 0);
  gate.resolve();
  await Promise.all([write, end]);
  assert.deepEqual(f.writes, [0.8, -1]);
});

test('window hiding retires the lease and a new session can resume', async () => {
  const f = fixture();
  await f.begin('foreground');
  await f.set('foreground', 0.9);
  await f.hide();
  assert.equal(f.brightness, -1);
  assert.equal(await f.set('foreground', 0.8), false);
  await f.begin('resumed');
  assert.equal(await f.set('resumed', 0.4), true);
  await f.end('resumed');
  assert.equal(f.brightness, -1);
});

test('a failed restore is retried before capturing a new baseline', async () => {
  const f = fixture();
  await f.begin('old');
  await f.set('old', 0.8);
  f.state.beforeSet = async () => { throw new Error('temporary window error'); };
  await assert.rejects(f.end('old'), /PLAYER_BRIGHTNESS_FAILED/);
  f.state.beforeSet = async () => {};
  await f.begin('new');
  await f.set('new', 0.6);
  await f.end('new');
  assert.deepEqual(f.writes, [0.8, -1, 0.6, -1]);
});

test('engine detachment cleans a failed restore and rejects new leases', async () => {
  const f = fixture();
  await f.begin('detaching');
  f.state.beforeSet = async () => { throw new Error('window destroyed'); };
  await f.detach();
  assert.equal(f.listeners.size, 0);
  await assert.rejects(f.begin('too-late'), /PLAYER_BRIGHTNESS_FAILED/);
});

test('invalid calls do not poison the queue or alter the brightness', async () => {
  const f = fixture(0.4);
  await assert.rejects(f.begin(''), /PLAYER_BRIGHTNESS_FAILED/);
  await f.begin('valid');
  for (const value of [NaN, Infinity, -1, 0, 1.1]) {
    await assert.rejects(f.set('valid', value), /PLAYER_BRIGHTNESS_FAILED/);
  }
  assert.deepEqual(f.writes, []);
  assert.equal(await f.set('valid', 0.02), true);
  await f.end('valid');
  assert.equal(f.brightness, 0.4);
});

test('unavailable system setting does not modify the window until a drag', async () => {
  const f = fixture();
  f.state.failSetting = true;
  assert.equal(await f.begin('fallback'), 0.5);
  assert.deepEqual(f.writes, []);
  await f.set('fallback', 0.6);
  await f.end('fallback');
  assert.deepEqual(f.writes, [0.6, -1]);
});
