import { common, wantAgent } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { MethodCall, MethodChannel } from '@ohos/flutter_ohos';

export class BackgroundMedia {
  private context: common.UIAbilityContext;
  private channel: MethodChannel;
  private session: avSession.AVSession | null = null;
  private running: boolean = false;
  private playing: boolean = false;
  private hasNext: boolean = false;
  private hasPrev: boolean = false;
  private owner: string | null = null;
  private floatingOwner: number = 0;
  private title: string = '番茄OH';
  private episode: string = '';
  private cover: string = '';
  private duration: number = 0;
  private position: number = 0;
  private speed: number = 1;
  private queue: Promise<void> = Promise.resolve();
  constructor(context: common.UIAbilityContext, channel: MethodChannel) { this.context = context; this.channel = channel; }
  update(call: MethodCall, owner: string = 'listen', replace: boolean = true): Promise<void> { return this.enqueue(async () => {
    // Partial PiP updates and a delayed stop must not reclaim a media session
    // that a newer listening mode has already taken over.
    if (!replace && this.owner !== owner) { return; }
    if (this.owner !== owner) {
      await this.release(); this.reset(); this.owner = owner;
    }
    if (owner === 'floating') { this.floatingOwner = call.argument('owner') as number; }
    if (!this.session) {
      const session = await avSession.createAVSession(this.context, 'fqapp-listening', 'audio'); this.session = session;
      session.on('play', () => { if (this.session === session && !this.playing) { this.action('playPause'); } });
      session.on('pause', () => { if (this.session === session && this.playing) { this.action('playPause'); } });
      session.on('stop', () => { if (this.session === session) { this.action('stop'); } });
      session.on('playNext', () => { if (this.session === session && this.hasNext) { this.action('next'); } });
      session.on('playPrevious', () => { if (this.session === session && this.hasPrev) { this.action('prev'); } });
      await session.activate();
    }
    const playing = call.argument('playing') as Object | null;
    const next = call.argument('hasNext') as Object | null;
    const previous = call.argument('hasPrev') as Object | null;
    if (typeof playing === 'boolean') { this.playing = playing; }
    if (typeof next === 'boolean') { this.hasNext = next; }
    if (typeof previous === 'boolean') { this.hasPrev = previous; }
    const title = call.argument('title') as string; const episode = call.argument('episode') as string;
    if (typeof title === 'string') { this.title = title.slice(0, 500); }
    if (typeof episode === 'string') { this.episode = episode.slice(0, 500); }
    this.duration = this.number(call.argument('durationMs'), 0, Number.MAX_SAFE_INTEGER, this.duration);
    this.position = this.number(call.argument('positionMs'), 0, this.duration || Number.MAX_SAFE_INTEGER, this.position);
    this.speed = this.number(call.argument('speed'), 0.125, 4, this.speed);
    const metadata: avSession.AVMetadata = { assetId: 'fqapp-' + owner, title: this.title, artist: this.episode, duration: this.duration };
    const cover = call.argument('coverUrl') as string;
    if (typeof cover === 'string') {
      this.cover = cover.length <= 4096 && /^https?:\/\/[^\s@]+$/.test(cover) ? cover : '';
    }
    if (this.cover !== '') { metadata.mediaImage = this.cover; }
    await this.session.setAVMetadata(metadata);
    await this.session.setAVPlaybackState({ state: this.playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      speed: this.speed, position: { elapsedTime: this.position, updateTime: Date.now() } });
    if (this.playing && !this.running) {
      const agent = await wantAgent.getWantAgent({ wants: [{ bundleName: this.context.abilityInfo.bundleName, abilityName: this.context.abilityInfo.name }], operationType: wantAgent.OperationType.START_ABILITY, requestCode: 0, wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG] });
      await backgroundTaskManager.startBackgroundRunning(this.context, backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, agent); this.running = true;
    } else if (!this.playing && this.running && owner !== 'floating') {
      await backgroundTaskManager.stopBackgroundRunning(this.context); this.running = false;
    }
  }); }
  stop(owner: string | null = null): Promise<void> { return this.enqueue(async () => {
    if (owner !== null && this.owner !== owner) { return; }
    this.reset(); await this.release();
  }); }
  private async release(): Promise<void> {
    try { if (this.running) { await backgroundTaskManager.stopBackgroundRunning(this.context); } }
    finally { this.running = false; const session = this.session; this.session = null; if (session) { await session.destroy(); } }
  }
  private reset(): void {
    this.owner = null; this.floatingOwner = 0; this.playing = false; this.hasNext = false; this.hasPrev = false;
    this.title = '番茄OH'; this.episode = ''; this.cover = ''; this.duration = 0; this.position = 0; this.speed = 1;
  }
  private action(action: string): void {
    if (this.owner === null) { return; }
    const args = new Map<string, Object>(); args.set('action', action);
    if (this.owner === 'floating') {
      args.set('owner', this.floatingOwner); this.channel.invokeMethod('onFloatingAction', args);
    } else { this.channel.invokeMethod('onNotificationAction', args); }
  }
  private number(value: Object | null, min: number, max: number, fallback: number): number { return typeof value === 'number' && Number.isFinite(value) ? Math.min(max, Math.max(min, value)) : fallback; }
  private enqueue(task: () => Promise<void>): Promise<void> { const result = this.queue.then(task); this.queue = result.catch(() => {}); return result; }
}
