import { huks } from '@kit.UniversalKeystoreKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

interface SealedProbe {
  version: number;
  nonce: string;
  ciphertext: string;
  digest: string;
}

// G1-only namespace. Never share its alias or record with production Hive keys.
export class HuksProbeStore {
  private readonly alias: string = 'fqapp.harmony.g1.probe.kek.v1';
  private readonly entry: string = 'huks_probe_v1';
  private readonly base64: util.Base64Helper = new util.Base64Helper();
  private readonly encoder: util.TextEncoder = new util.TextEncoder();

  async verify(store: preferences.Preferences): Promise<boolean> {
    const encoded = await store.get(this.entry, '');
    let exists: boolean = false;
    try {
      exists = await huks.isKeyItemExist(this.alias, { properties: [] });
    } catch (error) {
      // HUKS rejects (rather than returning false) for a missing alias.
      if ((error as BusinessError).code !== 12000011) {
        throw new Error('SECURE_OPERATION_FAILED');
      }
    }
    if (typeof encoded !== 'string') {
      throw new Error('SECURE_RECORD_INVALID');
    }
    if (encoded.length > 0) {
      // Losing a HUKS key must not silently replace the encrypted record.
      if (!exists) { throw new Error('SECURE_KEY_MISSING'); }
      const record = JSON.parse(encoded) as SealedProbe;
      await this.readAndVerify(record);
      return true;
    }
    if (!exists) {
      await huks.generateKeyItem(this.alias, {
        properties: this.parameters(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT |
          huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT)
      });
    }
    const probe = cryptoFramework.createRandom().generateRandomSync(32).data;
    const nonce = cryptoFramework.createRandom().generateRandomSync(12).data;
    const parameters = this.parameters(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT);
    parameters.push({ tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce });
    parameters.push({ tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: this.encoder.encodeInto(this.entry) });
    const ciphertext = await this.crypt(parameters, probe);
    const record: SealedProbe = {
      version: 1,
      nonce: this.base64.encodeToStringSync(nonce),
      ciphertext: this.base64.encodeToStringSync(ciphertext),
      digest: await this.digest(probe)
    };
    // Verify before committing, then re-read the committed ciphertext.
    await this.readAndVerify(record);
    await store.put(this.entry, JSON.stringify(record));
    await store.flush();
    const saved = await store.get(this.entry, '');
    if (typeof saved !== 'string' || saved !== JSON.stringify(record)) {
      throw new Error('SECURE_PERSIST_FAILED');
    }
    await this.readAndVerify(JSON.parse(saved) as SealedProbe);
    probe.fill(0);
    return false;
  }

  private async readAndVerify(record: SealedProbe): Promise<void> {
    if (record.version !== 1 || typeof record.nonce !== 'string' ||
      typeof record.ciphertext !== 'string' || typeof record.digest !== 'string') {
      throw new Error('SECURE_RECORD_INVALID');
    }
    const nonce = this.base64.decodeSync(record.nonce);
    const ciphertext = this.base64.decodeSync(record.ciphertext);
    if (nonce.length !== 12 || ciphertext.length !== 48) {
      throw new Error('SECURE_RECORD_INVALID');
    }
    const parameters = this.parameters(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT);
    parameters.push({ tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce });
    parameters.push({ tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: this.encoder.encodeInto(this.entry) });
    parameters.push({ tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: ciphertext.slice(-16) });
    const plain = await this.crypt(parameters, ciphertext.slice(0, -16));
    try {
      if (plain.length !== 32 || await this.digest(plain) !== record.digest) {
        throw new Error('SECURE_VERIFY_FAILED');
      }
    } finally { plain.fill(0); }
  }

  private parameters(purpose: number): huks.HuksParam[] {
    return [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM }
    ];
  }

  private async crypt(properties: huks.HuksParam[], data: Uint8Array): Promise<Uint8Array> {
    const session = await huks.initSession(this.alias, { properties: properties });
    try {
      const result = await huks.finishSession(session.handle, { properties: properties, inData: data });
      if (!result.outData) { throw new Error('SECURE_EMPTY_RESULT'); }
      return result.outData;
    } catch (error) {
      try { await huks.abortSession(session.handle, { properties: [] }); } catch (_) { /* already closed */ }
      throw new Error('SECURE_OPERATION_FAILED');
    }
  }

  private async digest(value: Uint8Array): Promise<string> {
    const hash = cryptoFramework.createMd('SHA256');
    await hash.update({ data: value });
    return this.base64.encodeToStringSync((await hash.digest()).data);
  }
}
