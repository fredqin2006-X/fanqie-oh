import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { huks } from '@kit.UniversalKeystoreKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

interface SealedKey {
  version: number;
  nonce: string;
  ciphertext: string;
}

// The non-exportable wrapping key remains in HUKS. Preferences contain only
// authenticated ciphertext, random nonces, and the envelope version.
export class SecureKeyPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.Context | null = null;
  private pending: Promise<void> = Promise.resolve();
  private readonly alias: string = 'fqapp.harmony.local-data.wrap.v1';
  private readonly base64: util.Base64Helper = new util.Base64Helper();
  private readonly encoder: util.TextEncoder = new util.TextEncoder();

  getUniqueClassName(): string { return 'FqSecureKeyPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'fqapp/secure_keys');
    this.channel.setMethodCallHandler(this);
  }
  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.context = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'read' && call.method !== 'write') { result.notImplemented(); return; }
    this.pending = this.pending.then(async () => {
      try {
        const context = this.context;
        if (!context) { throw new Error('SECURE_ENGINE_DETACHED'); }
        const key = call.argument('key') as string;
        if (key !== 'fqapp_hive_encryption_key_v1' && key !== 'fqapp_device_pool_key_v1') {
          throw new Error('SECURE_KEY_NAME_INVALID');
        }
        const store = await preferences.getPreferences(context, { name: 'fqapp_secure_keys_v1' });
        if (call.method === 'read') {
          result.success(await this.read(store, key));
        } else {
          const value = call.argument('value') as string;
          if (typeof value !== 'string' || !/^[A-Za-z0-9+/]{43}=$/.test(value) ||
            this.base64.decodeSync(value).length !== 32) { throw new Error('SECURE_VALUE_INVALID'); }
          const prior = await this.read(store, key);
          if (prior !== null && prior !== value) { throw new Error('SECURE_REPLACEMENT_REFUSED'); }
          if (prior === null) { await this.write(store, key, value); }
          result.success(null);
        }
      } catch (error) {
        const message = (error as Error).message;
        const codes = ['SECURE_ENGINE_DETACHED', 'SECURE_KEY_NAME_INVALID', 'SECURE_VALUE_INVALID',
          'SECURE_REPLACEMENT_REFUSED', 'SECURE_KEY_MISSING', 'SECURE_RECORD_INVALID', 'SECURE_AUTH_FAILED'];
        result.error(codes.includes(message) ? message : 'SECURE_STORE_UNAVAILABLE',
          'Secure key unavailable; stored data was preserved', null);
      }
    });
  }

  private async exists(): Promise<boolean> {
    try { return await huks.isKeyItemExist(this.alias, { properties: [] }); }
    catch (error) {
      if ((error as BusinessError).code === 12000011) { return false; }
      throw new Error('SECURE_STORE_UNAVAILABLE');
    }
  }

  private async read(store: preferences.Preferences, key: string): Promise<string | null> {
    const encoded = await store.get(key, '');
    if (encoded === '') { return null; }
    if (typeof encoded !== 'string') { throw new Error('SECURE_RECORD_INVALID'); }
    if (!await this.exists()) { throw new Error('SECURE_KEY_MISSING'); }
    const record = JSON.parse(encoded) as SealedKey;
    if (record.version !== 1 || typeof record.nonce !== 'string' || typeof record.ciphertext !== 'string') {
      throw new Error('SECURE_RECORD_INVALID');
    }
    const nonce = this.base64.decodeSync(record.nonce);
    const ciphertext = this.base64.decodeSync(record.ciphertext);
    if (nonce.length !== 12 || ciphertext.length !== 60) { throw new Error('SECURE_RECORD_INVALID'); }
    const params = this.parameters(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, key, nonce);
    params.push({ tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: ciphertext.slice(-16) });
    const plain = await this.crypt(params, ciphertext.slice(0, -16));
    try { return util.TextDecoder.create('utf-8', { fatal: true }).decodeWithStream(plain); }
    finally { plain.fill(0); }
  }

  private async write(store: preferences.Preferences, key: string, value: string): Promise<void> {
    if (!await this.exists()) {
      // Never create a replacement wrapping key if either production entry exists.
      for (const purpose of ['fqapp_hive_encryption_key_v1', 'fqapp_device_pool_key_v1']) {
        if (await store.has(purpose)) { throw new Error('SECURE_KEY_MISSING'); }
      }
      const props = this.parameters(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT |
        huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT);
      await huks.generateKeyItem(this.alias, { properties: props });
    }
    const nonce = cryptoFramework.createRandom().generateRandomSync(12).data;
    const plain = this.encoder.encodeInto(value);
    let encrypted: Uint8Array;
    try { encrypted = await this.crypt(this.parameters(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, key, nonce), plain); }
    finally { plain.fill(0); }
    const record: SealedKey = { version: 1, nonce: this.base64.encodeToStringSync(nonce),
      ciphertext: this.base64.encodeToStringSync(encrypted) };
    await store.put(key, JSON.stringify(record));
    await store.flush();
    if (await this.read(store, key) !== value) { throw new Error('SECURE_AUTH_FAILED'); }
  }

  private parameters(purpose: number, name?: string, nonce?: Uint8Array): huks.HuksParam[] {
    const props: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM }
    ];
    if (nonce && name) {
      props.push({ tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce });
      props.push({ tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: this.encoder.encodeInto(name) });
    }
    return props;
  }

  private async crypt(properties: huks.HuksParam[], data: Uint8Array): Promise<Uint8Array> {
    const session = await huks.initSession(this.alias, { properties: properties });
    try {
      const result = await huks.finishSession(session.handle, { properties: properties, inData: data });
      if (!result.outData) { throw new Error('SECURE_AUTH_FAILED'); }
      return result.outData;
    } catch (_) {
      try { await huks.abortSession(session.handle, { properties: [] }); } catch (_) { /* already closed */ }
      throw new Error('SECURE_AUTH_FAILED');
    }
  }
}
