import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { systemShare } from '@kit.ShareKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { zlib } from '@kit.BasicServicesKit';

// Only files explicitly selected in the system picker cross the sandbox boundary.
// No storage-wide permission, persistent URI grant, or background upload is used.
export class DocumentPlugin implements FlutterPlugin, MethodCallHandler {
  private channels: MethodChannel[] = [];
  private busy: boolean = false;
  private captureQueue: Promise<void> = Promise.resolve();
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  getUniqueClassName(): string { return 'FqDocumentPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    for (const name of ['fqapp/local_books', 'fqapp/library_backup', 'fqapp/downloads', 'fqapp/share']) {
      const channel = new MethodChannel(binding.getBinaryMessenger(), name);
      channel.setMethodCallHandler(this); this.channels.push(channel);
    }
  }
  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    for (const channel of this.channels) { channel.setMethodCallHandler(null); } this.channels = [];
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (['storeFanqieCapture', 'storeFanqieCapturePart', 'latestFanqieCapture', 'readFanqieCapturePart'].includes(call.method)) {
      this.captureQueue = this.captureQueue.then(async () => {
        try { result.success(await this.captureFile(call)); }
        catch (_) { result.error('CAPTURE_IO_FAILED', '本机采集文件读写失败，可尝试导出', null); }
      });
      return;
    }
    if (!['pickBookFile', 'openBackup', 'saveBackup', 'exportFanqieCapture', 'saveText', 'shareText'].includes(call.method)) { result.notImplemented(); return; }
    if (this.busy) { result.error('PICKER_BUSY', '请先完成当前文件操作', null); return; }
    this.busy = true;
    this.handle(call).then(value => result.success(value)).catch(() => {
      result.error('DOCUMENT_FAILED', '文件操作未完成，请检查文件格式、大小及保存位置', null);
    }).finally(() => { this.busy = false; });
  }
  async pickFont(): Promise<Map<string, Object> | null> {
    const uri = await this.select(['字体|.ttf,.otf,.ttc']);
    if (!uri) { return null; }
    const bytes = await this.read(uri, 32 * 1024 * 1024);
    const signature = Array.from(bytes.subarray(0, 4)).join(',');
    if (!['0,1,0,0', '79,84,84,79', '116,116,99,102'].includes(signature)) { throw new Error('FONT_FORMAT'); }
    const dir = this.context.filesDir + '/reader_fonts';
    if (!fs.accessSync(dir)) { fs.mkdirSync(dir); }
    // Content hash deduplicates repeated imports, preserving Dart's family cap.
    const digest = await this.digest(bytes);
    const name = this.name(uri);
    const path = dir + '/' + digest + (name.toLowerCase().endsWith('.otf') ? '.otf' : '.ttf');
    if (!fs.accessSync(path)) { await this.write(path, bytes); }
    const reply = new Map<string, Object>(); reply.set('name', name); reply.set('path', path); return reply;
  }
  private async digest(bytes: Uint8Array): Promise<string> {
    const value = cryptoFramework.createMd('SHA256'); await value.update({ data: bytes });
    return Array.from((await value.digest()).data).map(x => x.toString(16).padStart(2, '0')).join('');
  }
  private async handle(call: MethodCall): Promise<Object | null> {
    switch (call.method) {
      case 'pickBookFile': {
        const uri = await this.select(['电子书|.txt,.epub']); if (!uri) { return null; }
        const bytes = await this.read(uri, 32 * 1024 * 1024); const name = this.name(uri);
        const reply = new Map<string, Object>(); reply.set('name', name); reply.set('byteLength', bytes.length);
        if (name.toLowerCase().endsWith('.txt')) { reply.set('text', this.decodeText(bytes)); }
        else if (name.toLowerCase().endsWith('.epub')) { reply.set('bytes', bytes); }
        else { throw new Error('BOOK_FORMAT'); }
        return reply;
      }
      case 'openBackup': {
        const uri = await this.select(['书架备份|.json']); return uri ? this.read(uri, 16 * 1024 * 1024) : null;
      }
      case 'saveBackup': {
        const bytes = call.argument('bytes') as Uint8Array;
        if (!(bytes instanceof Uint8Array) || bytes.length > 16 * 1024 * 1024) { throw new Error('BACKUP_SIZE'); }
        return (await this.save(call.argument('name') as string, bytes, '.json')) !== null;
      }
      case 'exportFanqieCapture': return this.exportCapture(call);
      case 'saveText': {
        const text = call.argument('text') as string;
        if (typeof text !== 'string') { throw new Error('TEXT_INVALID'); }
        const bytes = new util.TextEncoder().encodeInto(text);
        if (bytes.length > 128 * 1024 * 1024) { throw new Error('EXPORT_SIZE'); }
        const uri = await this.save(call.argument('fileName') as string, bytes, '.txt');
        if (!uri) { throw new Error('EXPORT_CANCELLED'); }
        const reply = new Map<string, Object>(); reply.set('path', uri); reply.set('public', true); return reply;
      }
      case 'shareText': {
        const text = call.argument('text') as string; const title = call.argument('title') as string;
        if (typeof text !== 'string' || text.length > 32000) { throw new Error('SHARE_SIZE'); }
        const data = new systemShare.SharedData({ utd: 'general.plain-text', content: text, title: typeof title === 'string' ? title.slice(0, 200) : '' });
        const controller = new systemShare.ShareController(data);
        controller.show(this.context, { selectionMode: systemShare.SelectionMode.SINGLE }); return true;
      }
    }
    return null;
  }
  private captureDirectory(): string {
    const path = this.context.filesDir + '/fanqie-library-captures';
    if (!fs.accessSync(path)) { fs.mkdirSync(path); }
    if (!fs.lstatSync(path).isDirectory() || fs.lstatSync(path).isSymbolicLink()) { throw new Error('CAPTURE_DIRECTORY'); }
    return path;
  }
  private checkedBytes(call: MethodCall): Uint8Array {
    const bytes = call.argument('bytes') as Uint8Array;
    if (!(bytes instanceof Uint8Array) || bytes.length < 1 || bytes.length > 16 * 1024 * 1024) { throw new Error('CAPTURE_SIZE'); }
    return bytes;
  }
  private capturePart(name: string): string {
    if (typeof name !== 'string' || !/^part-[0-9]+-[a-fA-F0-9-]+\.json$/.test(name)) { throw new Error('PART_NAME'); }
    const path = this.captureDirectory() + '/' + name;
    const stat = fs.lstatSync(path);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.size < 1 || stat.size > 16 * 1024 * 1024) { throw new Error('PART_SIZE'); }
    return path;
  }
  private async captureFile(call: MethodCall): Promise<Object | null> {
    const dir = this.captureDirectory();
    if (call.method === 'readFanqieCapturePart') {
      return this.read(this.capturePart(call.argument('name') as string), 16 * 1024 * 1024);
    }
    if (call.method === 'latestFanqieCapture') {
      const names = fs.listFileSync(dir).filter(name => /^capture-[0-9]+-[a-fA-F0-9-]+\.json$/.test(name)).sort();
      if (names.length === 0) { return null; }
      const path = dir + '/' + names[names.length - 1];
      if (!fs.lstatSync(path).isFile() || fs.lstatSync(path).isSymbolicLink()) { throw new Error('CAPTURE_FILE'); }
      return this.read(path, 16 * 1024 * 1024);
    }
    const bytes = this.checkedBytes(call);
    const part = call.method === 'storeFanqieCapturePart';
    const name = `${part ? 'part' : 'capture'}-${Date.now()}-${util.generateRandomUUID()}.json`;
    const temporary = dir + '/pending-' + util.generateRandomUUID() + '.tmp';
    try {
      await this.write(temporary, bytes);
      await fs.rename(temporary, dir + '/' + name);
    } finally { if (fs.accessSync(temporary)) { fs.unlinkSync(temporary); } }
    return part ? name : true;
  }
  private async exportCapture(call: MethodCall): Promise<boolean> {
    const bytes = this.checkedBytes(call);
    const names = call.argument('parts') as string[];
    if (!Array.isArray(names) || names.length > 2000 || new Set(names).size !== names.length) { throw new Error('CAPTURE_PARTS'); }
    await this.captureQueue;
    // Stage only the manifest and its explicitly named immutable parts. The ZIP
    // encoder streams files on disk rather than loading a complete account into RAM.
    const sources = names.map(name => this.capturePart(name));
    const name = call.argument('name') as string;
    if (typeof name !== 'string' || !/^[a-zA-Z0-9_.-]{1,100}\.zip$/.test(name)) { throw new Error('ZIP_NAME'); }
    const uris = await new picker.DocumentViewPicker(this.context).save({ newFileNames: [name], fileSuffixChoices: ['.zip'] });
    if (!uris.length) { return false; }
    const staging = this.context.cacheDir + '/capture-export-' + util.generateRandomUUID();
    const archive = staging + '.zip';
    fs.mkdirSync(staging);
    const staged: string[] = [];
    try {
      const manifest = staging + '/manifest.json';
      staged.push(manifest); await this.write(manifest, bytes);
      for (let i = 0; i < names.length; i++) {
        const path = staging + '/' + names[i]; staged.push(path); await fs.copyFile(sources[i], path);
      }
      await zlib.compressFiles(staged, archive, {});
      const destination = await fs.open(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try { await fs.copyFile(archive, destination.fd); } finally { await fs.close(destination); }
      return true;
    } finally {
      for (const path of staged) { if (fs.accessSync(path)) { fs.unlinkSync(path); } }
      if (fs.accessSync(archive)) { fs.unlinkSync(archive); }
      if (fs.accessSync(staging)) { fs.rmdirSync(staging); }
    }
  }
  private async select(filters: string[]): Promise<string | null> {
    const uris = await new picker.DocumentViewPicker(this.context).select({ maxSelectNumber: 1, fileSuffixFilters: filters });
    return uris.length > 0 ? uris[0] : null;
  }
  private name(uri: string): string { return decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1)); }
  private async save(name: string, bytes: Uint8Array, suffix: string): Promise<string | null> {
    if (typeof name !== 'string' || !name.toLowerCase().endsWith(suffix) || /[\\/\u0000-\u001f]/.test(name) || name.length > 200) { throw new Error('NAME_INVALID'); }
    const uris = await new picker.DocumentViewPicker(this.context).save({ newFileNames: [name], fileSuffixChoices: [suffix] });
    if (!uris.length) { return null; } await this.write(uris[0], bytes); return uris[0];
  }
  private async read(uri: string, limit: number): Promise<Uint8Array> {
    const file = await fs.open(uri, fs.OpenMode.READ_ONLY);
    try {
      const size = (await fs.stat(file.fd)).size;
      if (size < 1 || size > limit) { throw new Error('FILE_SIZE'); }
      const bytes = new Uint8Array(size); let offset = 0;
      while (offset < size) {
        const part = new ArrayBuffer(Math.min(65536, size - offset));
        const count = await fs.read(file.fd, part, { length: part.byteLength });
        if (count <= 0) { throw new Error('SHORT_READ'); } bytes.set(new Uint8Array(part, 0, count), offset); offset += count;
      }
      return bytes;
    } finally { await fs.close(file); }
  }
  private async write(uri: string, bytes: Uint8Array): Promise<void> {
    const file = await fs.open(uri, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      let offset = 0;
      while (offset < bytes.length) {
        const part = bytes.slice(offset, Math.min(offset + 65536, bytes.length));
        const count = await fs.write(file.fd, part.buffer, { length: part.length });
        if (count <= 0) { throw new Error('SHORT_WRITE'); } offset += count;
      }
      await fs.fsync(file.fd);
    } finally { await fs.close(file); }
  }
  private decodeText(bytes: Uint8Array): string {
    if (bytes[0] === 0xff && bytes[1] === 0xfe) { return util.TextDecoder.create('utf-16le').decodeToString(bytes.subarray(2)); }
    if (bytes[0] === 0xfe && bytes[1] === 0xff) { return util.TextDecoder.create('utf-16be').decodeToString(bytes.subarray(2)); }
    try { return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes); }
    catch (_) { return util.TextDecoder.create('gb18030', { fatal: true }).decodeToString(bytes); }
  }
}
