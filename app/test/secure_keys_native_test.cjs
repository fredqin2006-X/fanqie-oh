'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require('typescript');

function fixture() {
  const records = new Map(), roots = new Map(), operations = new Map();
  let generated = 0, serial = 0;
  const tags = Object.fromEntries(['ALGORITHM', 'KEY_SIZE', 'PURPOSE', 'PADDING',
    'BLOCK_MODE', 'NONCE', 'ASSOCIATED_DATA', 'AE_TAG'].map(name => ['HUKS_TAG_' + name, name]));
  const huks = {
    HuksTag: tags, HuksKeyAlg: { HUKS_ALG_AES: 1 },
    HuksKeySize: { HUKS_AES_KEY_SIZE_256: 256 },
    HuksKeyPurpose: { HUKS_KEY_PURPOSE_ENCRYPT: 1, HUKS_KEY_PURPOSE_DECRYPT: 2 },
    HuksKeyPadding: { HUKS_PADDING_NONE: 0 }, HuksCipherMode: { HUKS_MODE_GCM: 1 },
    async isKeyItemExist(alias) { return roots.has(alias); },
    async generateKeyItem(alias) { generated++; roots.set(alias, crypto.randomBytes(32)); },
    async initSession(alias, options) {
      const handle = ++serial;
      operations.set(handle, { alias, properties: options.properties });
      return { handle };
    },
    async abortSession(handle) { operations.delete(handle); },
    async finishSession(handle, options) {
      const op = operations.get(handle);
      operations.delete(handle);
      const props = Object.fromEntries(options.properties.map(p => [p.tag, p.value]));
      const encrypt = props.PURPOSE === 1;
      const cipher = encrypt
        ? crypto.createCipheriv('aes-256-gcm', roots.get(op.alias), props.NONCE)
        : crypto.createDecipheriv('aes-256-gcm', roots.get(op.alias), props.NONCE);
      cipher.setAAD(props.ASSOCIATED_DATA);
      if (!encrypt) cipher.setAuthTag(props.AE_TAG);
      let bytes = Buffer.concat([cipher.update(options.inData), cipher.final()]);
      if (encrypt) bytes = Buffer.concat([bytes, cipher.getAuthTag()]);
      return { outData: new Uint8Array(bytes) };
    },
  };
  const store = {
    async get(key, fallback) { return records.has(key) ? records.get(key) : fallback; },
    async has(key) { return records.has(key); },
    async put(key, value) { records.set(key, value); },
    async delete(key) { records.delete(key); },
    async flush() {},
  };
  const deps = {
    '@ohos/flutter_ohos': { MethodChannel: class { setMethodCallHandler() {} } },
    '@kit.ArkData': { preferences: { getPreferences: async () => store } },
    '@kit.UniversalKeystoreKit': { huks },
    '@kit.CryptoArchitectureKit': { cryptoFramework: {
      createRandom: () => ({ generateRandomSync: length => ({ data: crypto.randomBytes(length) }) }),
    } },
    '@kit.ArkTS': { util: {
      Base64Helper: class {
        decodeSync(value) { return new Uint8Array(Buffer.from(value, 'base64')); }
        encodeToStringSync(value) { return Buffer.from(value).toString('base64'); }
      },
      TextEncoder: class { encodeInto(value) { return new Uint8Array(Buffer.from(value)); } },
      TextDecoder: { create: () => ({ decodeWithStream: value => new TextDecoder('utf-8', { fatal: true }).decode(value) }) },
    } },
  };
  const source = fs.readFileSync(require('node:path').join(__dirname,
    '../ohos/entry/src/main/ets/platform/SecureKeyPlugin.ets'), 'utf8');
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
  });
  const exports = {};
  vm.runInNewContext(compiled.outputText, { exports, require: name => {
    assert.ok(Object.hasOwn(deps, name), name); return deps[name];
  } });
  const plugin = new exports.SecureKeyPlugin();
  plugin.onAttachedToEngine({ getApplicationContext: () => ({}), getBinaryMessenger() {} });
  const invoke = (method, key, value) => new Promise((resolve, reject) => {
    plugin.onMethodCall({ method, argument: name => ({ key, value })[name] },
      { success: resolve, error: code => reject(new Error(code)), notImplemented: () => reject(Error('NOT_IMPLEMENTED')) });
  });
  return { invoke, records, roots, get generated() { return generated; } };
}
const rootKey = 'fqapp_hive_encryption_key_v1';
const aiKey = 'fqapp_ai_credential_fixture';

test('AI credentials round-trip through authenticated ciphertext, replace and delete without exposing plaintext', async () => {
  const f = fixture();
  await f.invoke('write', aiKey, 'fixture-token-first');
  assert.equal(await f.invoke('read', aiKey), 'fixture-token-first');
  assert.equal(JSON.stringify([...f.records.values()]).includes('fixture-token'), false);
  const first = f.records.get(aiKey);
  await f.invoke('write', aiKey, 'fixture-token-second');
  assert.notEqual(f.records.get(aiKey), first);
  assert.equal(await f.invoke('read', aiKey), 'fixture-token-second');
  await f.invoke('delete', aiKey);
  assert.equal(await f.invoke('read', aiKey), null);
  assert.equal(f.generated, 1);
});
test('AI operations cannot replace or delete production data keys', async () => {
  const f = fixture(), value = Buffer.alloc(32, 7).toString('base64');
  await f.invoke('write', rootKey, value);
  const record = f.records.get(rootKey);
  await assert.rejects(f.invoke('write', rootKey, Buffer.alloc(32, 9).toString('base64')), /SECURE_REPLACEMENT_REFUSED/);
  await assert.rejects(f.invoke('delete', rootKey), /SECURE_REPLACEMENT_REFUSED/);
  assert.equal(f.records.get(rootKey), record);
  assert.equal(await f.invoke('read', rootKey), value);
});
test('wrong purpose, tampered ciphertext and missing HUKS root preserve existing records', async () => {
  const f = fixture();
  await f.invoke('write', aiKey, 'fixture-secret');
  const record = f.records.get(aiKey);
  f.records.set(aiKey + '_other', record);
  await assert.rejects(f.invoke('read', aiKey + '_other'), /SECURE_AUTH_FAILED/);
  f.roots.clear();
  await assert.rejects(f.invoke('read', aiKey), /SECURE_KEY_MISSING/);
  await assert.rejects(f.invoke('write', 'fqapp_ai_credential_new', 'new-token'), /SECURE_KEY_MISSING/);
  assert.equal(f.records.get(aiKey), record);
  assert.equal(f.generated, 1);
});
test('secure store rejects unsupported names and over-limit credential bytes', async () => {
  const f = fixture();
  await assert.rejects(f.invoke('write', 'other', 'token'), /SECURE_KEY_NAME_INVALID/);
  await assert.rejects(f.invoke('write', aiKey, 'x'.repeat(8193)), /SECURE_VALUE_INVALID/);
  assert.equal(f.records.size, 0);
});
