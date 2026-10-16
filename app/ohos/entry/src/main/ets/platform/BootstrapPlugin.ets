import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HuksProbeStore } from './HuksProbeStore';

export class BootstrapPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.Context | null = null;
  private pending: Promise<void> = Promise.resolve();

  getUniqueClassName(): string { return 'FqHarmonyBootstrapPlugin'; }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'fqapp/harmony_bootstrap');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.context = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'inspect') { result.notImplemented(); return; }
    this.pending = this.pending.then(async () => {
      const context = this.context;
      if (!context) { result.error('ENGINE_DETACHED', 'Engine is detached', null); return; }
      try {
        const fileReused = await this.checkPrivateFile(context);
        const store = await preferences.getPreferences(context, { name: 'fqapp_harmony_g1' });
        const keyReused = await new HuksProbeStore().verify(store);
        const previous = await store.get('launch_count', 0);
        if (typeof previous !== 'number' || !Number.isSafeInteger(previous) || previous < 0) {
          throw new Error('PREFERENCES_INVALID');
        }
        const launchCount = previous + 1;
        await store.put('launch_count', launchCount);
        await store.flush();
        if (await store.get('launch_count', 0) !== launchCount) {
          throw new Error('PREFERENCES_PERSIST_FAILED');
        }
        const response = new Map<string, Object>();
        response.set('apiVersion', deviceInfo.sdkApiVersion);
        response.set('launchCount', launchCount);
        response.set('fileReused', fileReused);
        response.set('keyReused', keyReused);
        // No paths, identifiers, ciphertext, or plaintext are logged or returned.
        hilog.info(0x0000, 'FqBootstrap', 'G1 storage passed; launch=%{public}d fileReused=%{public}s keyReused=%{public}s',
          launchCount, String(fileReused), String(keyReused));
        result.success(response);
      } catch (error) {
        const code = (error as Error).message;
        const allowedCodes = ['SECURE_RECORD_INVALID', 'SECURE_KEY_MISSING', 'SECURE_PERSIST_FAILED',
          'SECURE_VERIFY_FAILED', 'SECURE_EMPTY_RESULT', 'PREFERENCES_INVALID', 'PREFERENCES_PERSIST_FAILED',
          'PRIVATE_FILE_INVALID', 'SECURE_OPERATION_FAILED'];
        const safeCode = allowedCodes.includes(code) ? code : 'PLATFORM_STORAGE_FAILED';
        hilog.error(0x0000, 'FqBootstrap', 'G1 storage failed: %{public}s', safeCode);
        result.error(safeCode, 'Local storage verification failed; existing data preserved', null);
      }
    });
  }

  private async checkPrivateFile(context: common.Context): Promise<boolean> {
    const path = context.filesDir + '/harmony_g1_probe.txt';
    const marker = 'fqapp-harmony-g1-v1';
    const existed = await fileIo.access(path);
    if (!existed) {
      const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      try { await fileIo.write(file.fd, marker); } finally { await fileIo.close(file); }
    }
    if (await fileIo.readText(path) !== marker) { throw new Error('PRIVATE_FILE_INVALID'); }
    return existed;
  }
}
