import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult,
  EventChannel, StreamHandler, EventSink } from '@ohos/flutter_ohos';
import { textToSpeech } from '@kit.CoreSpeechKit';

export class SystemTtsPlugin implements FlutterPlugin, MethodCallHandler, StreamHandler {
  private channel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private sink: EventSink | null = null;
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private rate: number = 1;
  private serial: number = 0;
  private current: string = '';
  private requests: Map<string, string> = new Map();
  private queue: Promise<void> = Promise.resolve();
  private generation: number = 0;
  getUniqueClassName(): string { return 'FqSystemTtsPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'fqapp/system_tts'); this.channel.setMethodCallHandler(this);
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), 'fqapp/system_tts_events'); this.eventChannel.setStreamHandler(this);
  }
  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null); this.eventChannel?.setStreamHandler(null); this.sink = null; this.close();
  }
  onListen(_args: Object, events: EventSink): void { this.sink = events; }
  onCancel(_args: Object): void { this.sink = null; }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.queue = this.queue.then(async () => {
      try {
        switch (call.method) {
          case 'engines': {
            // Only advertise an engine after the system confirms Chinese voice availability.
            const voices = await textToSpeech.listVoices({ requestId: 'fqVoices' + (++this.serial), online: 1 });
            const engines: Map<string, Object>[] = [];
            if (voices.some(item => /^zh[-_]CN$/.test(item.language))) { const item = new Map<string, Object>(); item.set('package', 'harmony.system.zhCN'); item.set('label', '鸿蒙系统中文朗读'); engines.push(item); }
            const reply = new Map<string, Object>(); reply.set('engines', engines);
            if (engines.length > 0) { reply.set('defaultEngine', 'harmony.system.zhCN'); } result.success(reply); break;
          }
          case 'initialize': {
            const selected = call.argument('engine') as string | null;
            if (selected !== null && selected !== undefined && selected !== '' && selected !== 'harmony.system.zhCN') { throw new Error('ENGINE'); }
            const rate = call.argument('rate') as number;
            if (!Number.isFinite(rate) || rate < 0.5 || rate > 2) { throw new Error('RATE'); }
            this.close(); const generation = this.generation;
            const engine = await textToSpeech.createEngine({ language: 'zh-CN', person: 13, online: 1, extraParams: { name: '番茄OH', isBackStage: true } });
            if (generation !== this.generation) { engine.shutdown(); throw new Error('CANCELLED'); }
            this.rate = rate; this.engine = engine;
            engine.setListener({
              onStart: (id: string, _response: textToSpeech.StartResponse) => this.emit(id, 'start'),
              onComplete: (id: string, response: textToSpeech.CompleteResponse) => {
                // type=0 only finishes synthesis. Advancing Dart's queue here
                // stops audio that is still playing and truncates each chunk.
                if (response.type === 1) { this.emit(id, 'done'); }
              },
              onStop: (id: string, _response: textToSpeech.StopResponse) => this.emit(id, 'interrupted'),
              onError: (id: string, _code: number, _message: string) => this.emit(id, 'error'),
              onData: (_id: string, _audio: ArrayBuffer, _response: textToSpeech.SynthesisResponse) => {}
            }); result.success(300); break;
          }
          case 'speak': {
            const text = call.argument('text') as string; const id = call.argument('id') as string;
            if (!this.engine || typeof text !== 'string' || text.length < 1 || text.length > 300 || typeof id !== 'string' || id.length > 128) { throw new Error('SPEAK'); }
            const request = 'fqSpeak' + Date.now() + (++this.serial); this.requests.clear(); this.requests.set(request, id); this.current = request;
            this.engine.speak(text, { requestId: request, extraParams: { speed: this.rate, volume: 1, pitch: 1, languageContext: 'zh-CN', playType: 1, soundChannel: 3, queueMode: 1 } }); result.success(null); break;
          }
          case 'stop': this.requests.clear(); this.current = ''; this.engine?.stop(); result.success(null); break;
          case 'shutdown': this.close(); result.success(null); break;
          case 'settings': result.error('TTS_SETTINGS_UNAVAILABLE', '鸿蒙系统音色由系统管理，请在系统设置中调整', null); break;
          default: result.notImplemented();
        }
      } catch (_) { result.error('SYSTEM_TTS_UNAVAILABLE', '系统中文朗读不可用，请检查系统音色是否已安装', null); }
    });
  }
  private emit(request: string, type: string): void {
    const id = this.requests.get(request); if (!id || request !== this.current) { return; }
    const event = new Map<string, Object>(); event.set('id', id); event.set('type', type); this.sink?.success(event);
    if (type !== 'start') { this.requests.delete(request); this.current = ''; }
  }
  private close(): void { ++this.generation; this.requests.clear(); this.current = ''; this.engine?.shutdown(); this.engine = null; }
}
