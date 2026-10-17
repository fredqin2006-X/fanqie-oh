import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../services/native_player.dart';

/// Displays software-decoded video directly on an ArkUI surface. The pinned
/// emulator engine imports nested video textures as black after a cold start.
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
