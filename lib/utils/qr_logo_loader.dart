import 'dart:ui' as ui;

import 'package:flutter/services.dart';

class QrLogoLoader {
  QrLogoLoader._();

  static const String _logoAssetPath = 'assets/images/logo.png';
  static const int _badgeSizePx = 256;
  static ui.Image? _cachedLogo;
  static Future<ui.Image?>? _pendingLoad;

  static Future<ui.Image?> loadLogoImage() {
    final cached = _cachedLogo;
    if (cached != null) {
      return Future<ui.Image?>.value(cached);
    }
    final pending = _pendingLoad;
    if (pending != null) {
      return pending;
    }
    _pendingLoad = _loadInternal();
    return _pendingLoad!;
  }

  static Future<ui.Image?> _loadInternal() async {
    try {
      final data = await rootBundle.load(_logoAssetPath);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final rawLogo = frame.image;

      final size = _badgeSizePx.toDouble();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(
        recorder,
        ui.Rect.fromLTWH(0, 0, size, size),
      );
      final badgeRect = ui.Rect.fromLTWH(0, 0, size, size);
      final badgeRRect = ui.RRect.fromRectAndRadius(
        badgeRect,
        ui.Radius.circular(size * 0.22),
      );

      canvas.drawRRect(
        badgeRRect,
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      canvas.drawRRect(
        badgeRRect,
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = size * 0.03
          ..color = const ui.Color(0xFFE5E7EB),
      );

      final inset = size * 0.14;
      final dstRect = ui.Rect.fromLTWH(
        inset,
        inset,
        size - (inset * 2),
        size - (inset * 2),
      );
      final srcRect = ui.Rect.fromLTWH(
        0,
        0,
        rawLogo.width.toDouble(),
        rawLogo.height.toDouble(),
      );
      canvas.drawImageRect(
        rawLogo,
        srcRect,
        dstRect,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );

      _cachedLogo = await recorder
          .endRecording()
          .toImage(_badgeSizePx, _badgeSizePx);
      return _cachedLogo;
    } catch (_) {
      return null;
    } finally {
      _pendingLoad = null;
    }
  }
}
