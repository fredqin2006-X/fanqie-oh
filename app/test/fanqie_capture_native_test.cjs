'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require('typescript');

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'fq-capture-test-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const state = { pickerCalls: 0, failRename: false, zipEntries: [], cancel: false };
  const api = {
    OpenMode: { READ_ONLY: fs.constants.O_RDONLY, READ_WRITE: fs.constants.O_RDWR,
      CREATE: fs.constants.O_CREAT, TRUNC: fs.constants.O_TRUNC },
    accessSync: value => fs.existsSync(value), mkdirSync: fs.mkdirSync,
    lstatSync: fs.lstatSync, listFileSync: fs.readdirSync,
    unlinkSync: fs.unlinkSync, rmdirSync: fs.rmdirSync,
    open: async (name, mode) => {
      const fd = fs.openSync(name, mode === fs.constants.O_RDONLY ? 'r' : (mode & fs.constants.O_CREAT) ? 'w+' : 'r+');
      if (mode & fs.constants.O_TRUNC) fs.ftruncateSync(fd, 0);
      return { fd };
    },
    close: async file => fs.closeSync(file.fd),
    stat: async fd => fs.fstatSync(fd),
    read: async (fd, buffer, options) => fs.readSync(fd, new Uint8Array(buffer), 0, options.length, null),
    write: async (fd, buffer, options) => fs.writeSync(fd, new Uint8Array(buffer), 0, options.length, null),
    fsync: async fd => fs.fsyncSync(fd),
    rename: async (from, to) => { if (state.failRename) throw Error('rename'); fs.renameSync(from, to); },
    copyFile: async (from, to) => {
      if (typeof to === 'number') fs.writeFileSync(to, fs.readFileSync(from)); else fs.copyFileSync(from, to);
    },
  };
  const deps = {
    '@ohos/flutter_ohos': {}, '@kit.AbilityKit': {}, '@kit.ShareKit': {}, '@kit.CryptoArchitectureKit': {},
    '@kit.CoreFileKit': { fileIo: api, picker: { DocumentViewPicker: class {
      async save() { state.pickerCalls++; return state.cancel ? [] : [path.join(root, 'export.zip')]; }
    } } },
    '@kit.ArkTS': { util: { generateRandomUUID: crypto.randomUUID } },
    '@kit.BasicServicesKit': { zlib: { compressFiles: async (files, output) => {
      state.zipEntries = files.map(p => [path.basename(p), fs.readFileSync(p, 'utf8')]);
      fs.writeFileSync(output, 'mock ZIP');
    } } },
  };
  const source = fs.readFileSync(path.join(__dirname,
    '../ohos/entry/src/main/ets/platform/DocumentPlugin.ets'), 'utf8');
  const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } });
  const exports = {};
  vm.runInNewContext(compiled.outputText, { exports, Uint8Array, ArrayBuffer, require: name => deps[name] });
  const plugin = new exports.DocumentPlugin({ filesDir: root, cacheDir: root });
  const call = (method, args = {}) => new Promise((resolve, reject) => plugin.onMethodCall({
    method, argument: key => args[key],
  }, { success: resolve, error: code => reject(Error(code)), notImplemented: () => reject(Error('unsupported')) }));
  return { root, state, call };
}
const bytes = value => new TextEncoder().encode(value);

test('capture parts round-trip and manifest is only exposed after atomic rename', async t => {
  const f = fixture(t); assert.equal(await f.call('latestFanqieCapture'), null);
  const name = await f.call('storeFanqieCapturePart', { bytes: bytes('{"part":1}') });
  assert.match(name, /^part-\d+-[a-f0-9-]+\.json$/);
  assert.equal(new TextDecoder().decode(await f.call('readFanqieCapturePart', { name })), '{"part":1}');
  await f.call('storeFanqieCapture', { bytes: bytes('{"complete":true}') });
  f.state.failRename = true;
  await assert.rejects(f.call('storeFanqieCapture', { bytes: bytes('{"broken":true}') }), /CAPTURE_IO_FAILED/);
  assert.equal(new TextDecoder().decode(await f.call('latestFanqieCapture')), '{"complete":true}');
  assert.equal(fs.readdirSync(path.join(f.root, 'fanqie-library-captures')).some(n => n.endsWith('.tmp')), false);
});
test('invalid part names and empty or oversized writes fail without breaking later operations', async t => {
  const f = fixture(t);
  for (const name of ['../outside.json', '/absolute.json', 'part-1-a.json/../secret']) {
    await assert.rejects(f.call('readFanqieCapturePart', { name }), /CAPTURE_IO_FAILED/);
  }
  for (const payload of [new Uint8Array(0), new Uint8Array(16 * 1024 * 1024 + 1)]) {
    await assert.rejects(f.call('storeFanqieCapturePart', { bytes: payload }), /CAPTURE_IO_FAILED/);
  }
  assert.equal(await f.call('storeFanqieCapture', { bytes: bytes('{}') }), true);
});
test('export selects only manifest parts and removes its temporary files', async t => {
  const f = fixture(t);
  const name = await f.call('storeFanqieCapturePart', { bytes: bytes('{"part":1}') });
  await f.call('storeFanqieCapturePart', { bytes: bytes('{"unrelated":true}') });
  fs.writeFileSync(path.join(f.root, 'export.zip'), 'old');
  assert.equal(await f.call('exportFanqieCapture', { name: 'capture.zip', parts: [name], bytes: bytes('{}') }), true);
  assert.deepEqual(Array.from(f.state.zipEntries, pair => Array.from(pair)), [['manifest.json', '{}'], [name, '{"part":1}']]);
  assert.equal(fs.readdirSync(f.root).some(n => n.startsWith('capture-export-')), false);
});
test('missing and duplicate parts fail before asking for a destination; cancel writes nothing', async t => {
  const f = fixture(t);
  for (const parts of [['part-1-a.json'], ['part-1-a.json', 'part-1-a.json']]) {
    await assert.rejects(f.call('exportFanqieCapture', { name: 'capture.zip', parts, bytes: bytes('{}') }), /DOCUMENT_FAILED/);
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.equal(f.state.pickerCalls, 0);
  f.state.cancel = true;
  assert.equal(await f.call('exportFanqieCapture', { name: 'capture.zip', parts: [], bytes: bytes('{}') }), false);
  assert.equal(fs.existsSync(path.join(f.root, 'export.zip')), false);
});
