import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/native_player.dart';

/// Hardware players use their native texture. Harmony's software fallback
/// uploads the latest RGBA frame, avoiding the emulator's native-image import.
class NativeVideoSurface extends StatelessWidget {
  const NativeVideoSurface({super.key, required this.textureId});

  final int textureId;

  @override
  Widget build(BuildContext context) {
    final playerId = NativePlayer.nativeSurfacePlayer(textureId);
    return playerId == null
        ? Texture(textureId: textureId)
        : _SoftwareVideoFrame(key: ValueKey(playerId), playerId: playerId);
  }
}

class _SoftwareVideoFrame extends StatefulWidget {
  const _SoftwareVideoFrame({super.key, required this.playerId});
  final int playerId;

  @override
  State<_SoftwareVideoFrame> createState() => _SoftwareVideoFrameState();
}

class _SoftwareVideoFrameState extends State<_SoftwareVideoFrame> {
  Timer? _timer;
  ui.Image? _image;
  int _serial = 0;
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) => _next());
    _next();
  }

  Future<void> _next() async {
    if (_pending || !mounted) return;
    _pending = true;
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      final frame = await NativePlayer.readVideoFrame(widget.playerId, _serial);
      if (!mounted || frame == null) return;
      final width = (frame['width'] as num).toInt();
      final height = (frame['height'] as num).toInt();
      final pixels = frame['pixels'] as Uint8List;
      if (width <= 0 || height <= 0 || pixels.length != width * height * 4) return;
      buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
      descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      codec = await descriptor.instantiateCodec();
      final decoded = (await codec.getNextFrame()).image;
      if (!mounted) {
        decoded.dispose();
        return;
      }
      final previous = _image;
      setState(() {
        _image = decoded;
        _serial = (frame['serial'] as num).toInt();
      });
      previous?.dispose();
    } catch (_) {
      // A frame request may race player disposal during navigation. The player
      // event channel remains responsible for reporting source/decode errors.
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
      _pending = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawImage(
    image: _image,
    fit: BoxFit.fill,
    filterQuality: FilterQuality.low,
  );
}
