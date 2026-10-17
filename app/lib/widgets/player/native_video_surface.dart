import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../services/native_player.dart';

/// Embeds the software decoder through an ArkUI texture node so Flutter can
/// compose its existing controls and modal routes over the complete viewport.
class NativeVideoSurface extends StatelessWidget {
  const NativeVideoSurface({super.key, required this.textureId});

  final int textureId;

  @override
  Widget build(BuildContext context) {
    final playerId = NativePlayer.nativeSurfacePlayer(textureId);
    if (playerId == null) return Texture(textureId: textureId);
    return PlatformViewLink(
      key: ValueKey(playerId),
      viewType: 'fqapp/software_video',
      surfaceFactory: (context, controller) => OhosViewSurface(
        controller: controller as OhosViewController,
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        gestureRecognizers: const {},
      ),
      onCreatePlatformView: (params) {
        // Do not opt into hybrid fallback: its overlay slice clips modal routes
        // to the video rectangle in the pinned HarmonyOS engine.
        final controller = PlatformViewsService.initOhosView(
          id: params.id,
          viewType: params.viewType,
          layoutDirection: Directionality.of(context),
          creationParams: {'playerId': playerId},
          creationParamsCodec: const StandardMessageCodec(),
        );
        controller.addOnPlatformViewCreatedListener(
          params.onPlatformViewCreated,
        );
        controller.create();
        return controller;
      },
    );
  }
}
