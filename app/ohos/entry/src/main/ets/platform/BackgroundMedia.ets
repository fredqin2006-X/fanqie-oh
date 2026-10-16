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
  private queue: Promise<void> = Promise.resolve();
  constructor(context: common.UIAbilityContext, channel: MethodChannel) { this.context = context; this.channel = channel; }
  update(call: MethodCall): Promise<void> { return this.enqueue(async () => {
    const playing = call.argument('playing') === true;
    if (!this.session) {
      const session = await avSession.createAVSession(this.context, 'fqapp-listening', 'audio'); this.session = session;
      session.on('play', () => { if (!this.playing) { this.action('playPause'); } });
      session.on('pause', () => { if (this.playing) { this.action('playPause'); } });
      session.on('stop', () => this.action('stop'));
      session.on('playNext', () => { if (this.hasNext) { this.action('next'); } });
      session.on('playPrevious', () => { if (this.hasPrev) { this.action('prev'); } });
      await session.activate();
    }
    this.playing = playing; this.hasNext = call.argument('hasNext') === true; this.hasPrev = call.argument('hasPrev') === true;
    const title = call.argument('title') as string; const episode = call.argument('episode') as string;
    const duration = this.number(call.argument('durationMs'), 0, Number.MAX_SAFE_INTEGER, 0);
    await this.session.setAVMetadata({ assetId: 'fqapp-listening', title: typeof title === 'string' ? title.slice(0, 500) : 'fqapp', artist: typeof episode === 'string' ? episode.slice(0, 500) : '', duration: duration });
    await this.session.setAVPlaybackState({ state: playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      speed: this.number(call.argument('speed'), 0.125, 4, 1), position: { elapsedTime: this.number(call.argument('positionMs'), 0, duration || Number.MAX_SAFE_INTEGER, 0), updateTime: Date.now() } });
    if (playing && !this.running) {
      const agent = await wantAgent.getWantAgent({ wants: [{ bundleName: this.context.abilityInfo.bundleName, abilityName: this.context.abilityInfo.name }], operationType: wantAgent.OperationType.START_ABILITY, requestCode: 0, wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG] });
      await backgroundTaskManager.startBackgroundRunning(this.context, backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, agent); this.running = true;
    } else if (!playing && this.running) { await backgroundTaskManager.stopBackgroundRunning(this.context); this.running = false; }
  }); }
  stop(): Promise<void> { return this.enqueue(async () => {
    this.playing = false; this.hasNext = false; this.hasPrev = false;
    try { if (this.running) { await backgroundTaskManager.stopBackgroundRunning(this.context); } }
    finally { this.running = false; const session = this.session; this.session = null; if (session) { await session.destroy(); } }
  }); }
  private action(action: string): void { const args = new Map<string, Object>(); args.set('action', action); this.channel.invokeMethod('onNotificationAction', args); }
  private number(value: Object | null, min: number, max: number, fallback: number): number { return typeof value === 'number' && Number.isFinite(value) ? Math.min(max, Math.max(min, value)) : fallback; }
  private enqueue(task: () => Promise<void>): Promise<void> { const result = this.queue.then(task); this.queue = result.catch(() => {}); return result; }
}
