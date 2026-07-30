import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:wiyamusic/utilities/artwork_provider.dart';

/// Returns true when the top strip of [imageUrl] is bright enough that dark
/// icons/text are needed for contrast.
Future<bool> isArtworkTopRegionLight(String? imageUrl) async {
  if (imageUrl == null || imageUrl.isEmpty) return false;

  try {
    final provider = ArtworkProvider.get(imageUrl);
    final image = await _resolveImage(
      provider,
      // Small decode is enough for luminance sampling.
      const ImageConfiguration(size: Size(48, 48)),
    );
    if (image == null) return false;

    final byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) return false;

    final width = image.width;
    final height = image.height;
    if (width <= 0 || height <= 0) return false;

    // Sample the top ~30% where the back / overflow icons sit.
    final sampleHeight = (height * 0.3).ceil().clamp(1, height);
    final bytes = byteData.buffer.asUint8List();

    var totalLuminance = 0.0;
    var counted = 0;
    for (var y = 0; y < sampleHeight; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final a = bytes[i + 3];
        if (a < 16) continue;
        final r = bytes[i] / 255.0;
        final g = bytes[i + 1] / 255.0;
        final b = bytes[i + 2] / 255.0;
        // Relative luminance (sRGB).
        totalLuminance += 0.2126 * r + 0.7152 * g + 0.0722 * b;
        counted++;
      }
    }

    if (counted == 0) return false;
    return (totalLuminance / counted) > 0.58;
  } catch (_) {
    return false;
  }
}

Future<ui.Image?> _resolveImage(
  ImageProvider provider,
  ImageConfiguration config,
) {
  final completer = Completer<ui.Image?>();
  late final ImageStreamListener listener;
  final stream = provider.resolve(config);

  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete(info.image);
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete(null);
    },
  );

  stream.addListener(listener);
  return completer.future.timeout(
    const Duration(seconds: 4),
    onTimeout: () {
      stream.removeListener(listener);
      return null;
    },
  );
}

/// Picks a readable icon/title color for an expanded playlist header.
Color playlistHeaderForegroundColor({
  required bool isTopRegionLight,
  required Color collapsedColor,
  double expandProgress = 1,
}) {
  final expanded = isTopRegionLight ? const Color(0xFF111827) : Colors.white;
  return Color.lerp(collapsedColor, expanded, expandProgress.clamp(0.0, 1.0))!;
}
