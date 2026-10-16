import { Any, PlatformView, PlatformViewFactory, StandardMessageCodec } from '@ohos/flutter_ohos';
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import { common } from '@kit.AbilityKit';

type SurfaceChanged = (playerId: number, viewId: number, surface: string) => void;

@Component
struct SoftwareVideoSurface {
  view: SoftwareVideoView | null = null;
  private controller: XComponentController = new XComponentController();
  build() {
    XComponent({ id: `fq-video-${this.view?.viewId ?? -1}`, type: XComponentType.SURFACE, controller: this.controller })
      .width('100%').height('100%')
      .onLoad(() => this.view?.attach(this.controller.getXComponentSurfaceId()))
      .onDestroy(() => this.view?.detach())
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
  constructor(viewId: number, playerId: number, changed: SurfaceChanged) {
    super(); this.viewId = viewId; this.playerId = playerId; this.changed = changed;
  }
  getView(): WrappedBuilder<[Params]> { return new WrappedBuilder(videoBuilder); }
  attach(surface: string): void {
    if (!this.disposed) { this.changed(this.playerId, this.viewId, surface); }
  }
  detach(): void { this.changed(this.playerId, this.viewId, '0'); }
  dispose(): void { this.disposed = true; this.detach(); }
}

export class SoftwareVideoViewFactory extends PlatformViewFactory {
  private changed: SurfaceChanged;
  constructor(changed: SurfaceChanged) { super(StandardMessageCodec.INSTANCE); this.changed = changed; }
  create(_context: common.Context, viewId: number, args: Any): PlatformView {
    const values = args as Map<string, number>;
    return new SoftwareVideoView(viewId, values.get('playerId') ?? 0, this.changed);
  }
}
