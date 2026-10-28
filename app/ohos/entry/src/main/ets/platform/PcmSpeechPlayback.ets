import { audio } from '@kit.AudioKit';
import { textToSpeech } from '@kit.CoreSpeechKit';

// CoreSpeech's synthesizer accepts 0.5–2x. For higher rates synthesize normal
// PCM and let AudioRenderer perform time stretching (0.25–4x, API 11).
export class PcmSpeechPlayback {
  private rate: number;
  private event: (type: string) => void;
  private renderer: audio.AudioRenderer | null = null;
  private chunks: Map<number, ArrayBuffer> = new Map();
  private byteLength: number = 0;
  private channels: number = 1;
  private cancelled: boolean = false;
  private finishing: boolean = false;
  constructor(rate: number, event: (type: string) => void) { this.rate = rate; this.event = event; }
  start(info: textToSpeech.StartResponse): void {
    if (info.audioType !== 'pcm' || info.sampleRate !== 16000 || info.sampleBit !== 16 ||
      (info.audioChannel !== 1 && info.audioChannel !== 2)) { this.fail(); return; }
    this.channels = info.audioChannel;
  }
  append(data: ArrayBuffer, info: textToSpeech.SynthesisResponse): void {
    if (this.cancelled || this.finishing) { return; }
    if (info.audioType !== 'pcm' || !Number.isInteger(info.sequence) || info.sequence < 0 ||
      info.sequence > 100000 || data.byteLength % 2 !== 0) { this.fail(); return; }
    if (this.chunks.has(info.sequence)) { return; }
    this.byteLength += data.byteLength;
    // One native request is at most 300 characters. Bound malformed streams.
    if (this.byteLength > 8 * 1024 * 1024) { this.fail(); return; }
    this.chunks.set(info.sequence, data.slice(0));
  }
  async finish(): Promise<void> {
    if (this.cancelled || this.finishing) { return; }
    this.finishing = true;
    let renderer: audio.AudioRenderer | null = null;
    let adopted = false;
    try {
      if (this.byteLength === 0 || this.byteLength % (this.channels * 2) !== 0) { throw new Error('EMPTY_PCM'); }
      const ordered: ArrayBuffer[] = [];
      for (let i = 0; i < this.chunks.size; ++i) {
        const chunk = this.chunks.get(i);
        if (!chunk) { throw new Error('MISSING_PCM_SEQUENCE'); }
        ordered.push(chunk);
      }
      this.chunks.clear();
      renderer = await audio.createAudioRenderer({
        streamInfo: { samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
          channels: this.channels === 1 ? audio.AudioChannel.CHANNEL_1 : audio.AudioChannel.CHANNEL_2,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW },
        rendererInfo: { usage: audio.StreamUsage.STREAM_USAGE_AUDIOBOOK, rendererFlags: 0 }
      });
      if (this.cancelled) { return; }
      this.renderer = renderer;
      adopted = true;
      renderer.setSpeed(this.rate);
      renderer.on('audioInterrupt', (interrupt: audio.InterruptEvent): void => {
        if (interrupt.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE ||
          interrupt.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
          if (!this.cancelled) { this.event('interrupted'); }
          this.stop().catch(() => {});
        }
      });
      await renderer.start();
      if (this.cancelled) { return; }
      this.event('start');
      for (const chunk of ordered) {
        let offset = 0;
        while (!this.cancelled && offset < chunk.byteLength) {
          const written = await renderer.write(chunk.slice(offset));
          if (written <= 0 || written > chunk.byteLength - offset) { throw new Error('PCM_WRITE_FAILED'); }
          offset += written;
        }
        if (this.cancelled) { return; }
      }
      await renderer.drain();
      if (!this.cancelled) { this.event('done'); }
    } catch (_) { this.fail(); }
    finally {
      // stop() takes ownership when cancellation releases the active renderer.
      if (renderer && (!adopted || this.renderer === renderer)) {
        this.renderer = null;
        try { await renderer.release(); } catch (_) { /* renderer already stopped */ }
      }
    }
  }
  async stop(): Promise<void> {
    this.cancelled = true; this.chunks.clear(); this.byteLength = 0;
    const renderer = this.renderer; this.renderer = null;
    if (renderer) { try { await renderer.release(); } catch (_) { /* already stopped */ } }
  }
  private fail(): void {
    if (!this.cancelled) { this.event('error'); }
    this.stop().catch(() => {});
  }
}
