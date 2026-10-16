import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../services/native_player.dart';

/// Keeps software-decoded HarmonyOS video on an ArkUI surface, avoiding the
/// external-texture buffer import. Flutter still lays out and controls the video.
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
        final controller = PlatformViewsService.initExpensiveOhosView(
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
