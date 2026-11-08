import { common } from '@kit.AbilityKit';
import { PiPWindow, typeNode, window } from '@kit.ArkUI';
import { MethodCall, MethodChannel } from '@ohos/flutter_ohos';

type SurfaceTarget = (playerId: number, surface: string | null) => void;

class FloatingSurfaceController extends XComponentController {
  changed: (surface: string | null) => void = (_surface: string | null): void => {};
  onSurfaceCreated(surface: string): void { this.changed(surface); }
  onSurfaceDestroyed(_surface: string): void { this.changed(null); }
}

// System PiP supplies its own accessible controls and restores the ability when
// the user expands it. The existing player keeps decoding into the PiP surface.
export class FloatingVideo {
  private controller: PiPWindow.PiPController | null = null;
  private node: typeNode.XComponent | null = null;
  private playerId: number = 0;
  private owner: number = 0;
  private surface: string | null = null;
  private started: boolean = false;
  private stopping: boolean = false;
  private restoring: boolean = false;
  private context: common.UIAbilityContext;
  private channel: MethodChannel;
  private target: SurfaceTarget;
  constructor(context: common.UIAbilityContext, channel: MethodChannel, target: SurfaceTarget) {
    this.context = context; this.channel = channel; this.target = target;
  }

  static supported(): boolean {
    try { return PiPWindow.isPiPEnabled(); } catch (_) { return false; }
  }
  owns(playerId: number): boolean { return this.playerId === playerId && this.surface !== null; }

  async prepare(call: MethodCall, playerId: number): Promise<void> {
    await this.stop();
    if (!FloatingVideo.supported()) { throw new Error('PIP_UNSUPPORTED'); }
    const win = await window.getLastWindow(this.context);
    const surfaceController = new FloatingSurfaceController();
    const node = typeNode.createNode(win.getUIContext(), 'XComponent', {
      type: XComponentType.SURFACE, controller: surfaceController
    });
    node.attribute.width('100%').height('100%');
    this.node = node; this.playerId = playerId; this.owner = call.argument('owner') as number;
    this.stopping = false; this.restoring = false;
    surfaceController.changed = (surface: string | null): void => {
      if (this.node !== node) { return; }
      this.surface = surface;
      try { this.target(this.playerId, surface); }
      catch (_) { this.action('stop'); }
    };
    try {
      const controller = await PiPWindow.create({
        context: this.context, componentController: surfaceController,
        templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
        contentWidth: this.size(call, 'videoWidth', 16),
        contentHeight: this.size(call, 'videoHeight', 9),
        controlGroups: [PiPWindow.VideoPlayControlGroup.VIDEO_PREVIOUS_NEXT]
      }, node);
      this.controller = controller;
      controller.on('stateChange', (state: PiPWindow.PiPState): void => {
        if (this.controller !== controller) { return; }
        if (state === PiPWindow.PiPState.STARTED) { this.started = true; }
        else if (state === PiPWindow.PiPState.ABOUT_TO_RESTORE) {
          this.restoring = true; this.restore(); this.action('fullscreen');
        } else if (state === PiPWindow.PiPState.STOPPED || state === PiPWindow.PiPState.ERROR) {
          this.started = false; this.restore();
          if (!this.stopping && !this.restoring) { this.action('stop'); }
        }
      });
      controller.on('controlEvent', (event: PiPWindow.ControlEventParam): void => {
        if (this.controller !== controller || this.stopping) { return; }
        switch (event.controlType) {
          case PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE: this.action('playPause'); break;
          case PiPWindow.PiPControlType.VIDEO_PREVIOUS: this.action('prev'); break;
          case PiPWindow.PiPControlType.VIDEO_NEXT: this.action('next'); break;
        }
      });
      if (!await controller.getPiPSettingSwitch()) { throw new Error('PIP_DISABLED'); }
      this.update(call);
      controller.setAutoStartEnabled(true);
    } catch (error) { await this.stop(); throw error as Error; }
  }

  async show(): Promise<void> {
    const controller = this.controller;
    if (!controller) { throw new Error('PIP_NOT_PREPARED'); }
    if (!this.started && !await controller.isPiPActive()) { await controller.startPiP(); }
  }
  update(call: MethodCall): void {
    const controller = this.controller;
    if (!controller) { return; }
    const playing = call.argument('playing') as Object | null;
    if (typeof playing === 'boolean') {
      controller.updatePiPControlStatus(PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE,
        playing ? PiPWindow.PiPControlStatus.PLAY : PiPWindow.PiPControlStatus.PAUSE);
    }
    const previous = call.argument('hasPrev') as Object | null;
    const next = call.argument('hasNext') as Object | null;
    if (typeof previous === 'boolean') { controller.setPiPControlEnabled(PiPWindow.PiPControlType.VIDEO_PREVIOUS, previous); }
    if (typeof next === 'boolean') { controller.setPiPControlEnabled(PiPWindow.PiPControlType.VIDEO_NEXT, next); }
    if (this.size(call, 'videoWidth', 0) > 0 && this.size(call, 'videoHeight', 0) > 0) {
      controller.updateContentSize(this.size(call, 'videoWidth', 16), this.size(call, 'videoHeight', 9));
    }
  }
  swap(playerId: number): void {
    if (!this.controller) { throw new Error('PIP_NOT_PREPARED'); }
    const previous = this.playerId;
    if (previous === playerId) { return; }
    if (this.surface !== null) {
      this.target(playerId, this.surface);
      this.target(previous, null);
    }
    this.playerId = playerId;
  }
  async stop(): Promise<void> {
    const controller = this.controller;
    this.stopping = true;
    this.restore();
    this.controller = null;
    if (controller) {
      controller.setAutoStartEnabled(false);
      controller.off('stateChange'); controller.off('controlEvent');
      try { if (this.started || await controller.isPiPActive()) { await controller.stopPiP(); } } catch (_) { /* release node even after system close */ }
    }
    const node = this.node; this.node = null;
    node?.dispose(); this.playerId = 0; this.started = false; this.restoring = false;
  }
  private restore(): void {
    if (this.surface !== null) {
      this.surface = null;
      try { this.target(this.playerId, null); } catch (_) { /* player may already be disposed */ }
    }
  }
  private action(action: string): void {
    const args = new Map<string, Object>(); args.set('owner', this.owner); args.set('action', action);
    this.channel.invokeMethod('onFloatingAction', args);
  }
  private size(call: MethodCall, name: string, fallback: number): number {
    const value = call.argument(name) as number;
    return Number.isFinite(value) && value > 0 && value <= 16384 ? value : fallback;
  }
}
