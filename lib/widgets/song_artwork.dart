import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:wiyamusic/widgets/no_artwork_cube.dart';
import 'package:wiyamusic/widgets/spinner.dart';

class SongArtworkWidget extends StatelessWidget {
  const SongArtworkWidget({
    super.key,
    required this.size,
    required this.metadata,
    this.width,
    this.height,
    this.borderRadius = 10.0,
    this.errorWidgetIconSize = 20.0,
  });
  final double size;
  final double? width;
  final double? height;
  final MediaItem metadata;
  final double borderRadius;
  final double errorWidgetIconSize;

  @override
  Widget build(BuildContext context) {
    final resolvedWidth = width ?? size;
    final resolvedHeight = height ?? size;
    final artUri = metadata.artUri;
    final localArtPath = metadata.extras?['artWorkPath']?.toString();

    if (artUri?.scheme == 'file' ||
        (localArtPath != null &&
            localArtPath.isNotEmpty &&
            !localArtPath.startsWith('http'))) {
      final path = artUri?.scheme == 'file'
          ? artUri!.toFilePath()
          : localArtPath!.replaceFirst('file://', '');
      return SizedBox(
        width: resolvedWidth,
        height: resolvedHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Image.file(
            File(path),
            fit: BoxFit.cover,
            width: resolvedWidth,
            height: resolvedHeight,
            errorBuilder: (context, error, stackTrace) =>
                NullArtworkWidget(iconSize: errorWidgetIconSize),
          ),
        ),
      );
    }

    final imageUrl = artUri?.toString() ?? '';
    if (imageUrl.isEmpty || !imageUrl.startsWith('http')) {
      return SizedBox(
        width: resolvedWidth,
        height: resolvedHeight,
        child: NullArtworkWidget(iconSize: errorWidgetIconSize),
      );
    }

    return CachedNetworkImage(
      width: resolvedWidth,
      height: resolvedHeight,
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      imageBuilder: (context, imageProvider) => ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image(
          image: imageProvider,
          fit: BoxFit.cover,
          width: resolvedWidth,
          height: resolvedHeight,
        ),
      ),
      placeholder: (context, url) => const Spinner(),
      errorWidget: (context, url, error) =>
          NullArtworkWidget(iconSize: errorWidgetIconSize),
    );
  }
}
