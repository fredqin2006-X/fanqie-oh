import { Any, PlatformView, PlatformViewFactory, StandardMessageCodec } from '@ohos/flutter_ohos';
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import { common } from '@kit.AbilityKit';

type SurfaceChanged = (playerId: number, viewId: number, surface: string) => void;

class VideoSurfaceController extends XComponentController {
  view: SoftwareVideoView | null = null;
  onSurfaceCreated(surfaceId: string): void { this.view?.attach(surfaceId); }
  onSurfaceDestroyed(surfaceId: string): void { this.view?.detach(surfaceId); }
}

@Component
struct SoftwareVideoSurface {
  view: SoftwareVideoView | null = null;
  private controller: VideoSurfaceController = new VideoSurfaceController();
  aboutToAppear(): void { this.controller.view = this.view; }
  build() {
    XComponent({ id: `fq-video-${this.view?.viewId ?? -1}`, type: XComponentType.TEXTURE, controller: this.controller })
      .width('100%').height('100%')
      .onTouch((event: TouchEvent) => this.view?.forwardTouch(event))
  }
}

@Builder
function videoBuilder(params: Params) {
  SoftwareVideoSurface({ view: params.platformView as SoftwareVideoView })
}

class SoftwareVideoView extends PlatformView {
  private playerId: number;
  private changed: SurfaceChanged;
  private disposed: boolean = false;
  private surface: string = '0';
  constructor(viewId: number, playerId: number, changed: SurfaceChanged) {
    super(); this.viewId = viewId; this.playerId = playerId; this.changed = changed;
  }
  getView(): WrappedBuilder<[Params]> { return new WrappedBuilder(videoBuilder); }
  attach(surface: string): void {
    if (!this.disposed && surface !== '0' && surface !== this.surface) {
      this.surface = surface;
      this.changed(this.playerId, this.viewId, surface);
    }
  }
  forwardTouch(event: TouchEvent): void {
    if (this.disposed) { return; }
    // Hybrid DISPLAY nodes receive native input above Flutter's render surface.
    // Return it to Flutter's gesture arena so the existing controls own taps,
    // seeks and page swipes. Do not feed Flutter-injected events back again.
    if (this.injectedTimestamps.has(event.timestamp)) {
      this.injectedTimestamps.delete(event.timestamp);
      return;
    }
    this.touchDispatcher?.(this.viewId, event);
  }
  detach(surface: string): void {
    if (surface !== this.surface || this.surface === '0') { return; }
    this.surface = '0'; this.changed(this.playerId, this.viewId, '0');
  }
  dispose(): void { this.disposed = true; this.detach(this.surface); }
}

export class SoftwareVideoViewFactory extends PlatformViewFactory {
  private changed: SurfaceChanged;
  constructor(changed: SurfaceChanged) { super(StandardMessageCodec.INSTANCE); this.changed = changed; }
  create(_context: common.Context, viewId: number, args: Any): PlatformView {
    const values = args as Map<string, number>;
    return new SoftwareVideoView(viewId, values.get('playerId') ?? 0, this.changed);
  }
}
