import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/theme/design_tokens.dart';
import 'package:wiyamusic/utilities/artwork_provider.dart';
import 'package:wiyamusic/utilities/flutter_toast.dart';

/// Spotify-style share photocard for the currently playing track.
class SongShareCard extends StatelessWidget {
  const SongShareCard({super.key, required this.metadata, this.width = 360});

  final MediaItem metadata;
  final double width;

  static String artworkSourceFor(MediaItem metadata) {
    final localPath = metadata.extras?['artWorkPath']?.toString();
    if (localPath != null &&
        localPath.isNotEmpty &&
        !localPath.startsWith('http')) {
      return localPath;
    }

    final artUri = metadata.artUri?.toString();
    if (artUri != null && artUri.isNotEmpty && artUri != 'null') {
      return artUri;
    }

    final highRes = metadata.extras?['highResImage']?.toString();
    if (highRes != null && highRes.isNotEmpty) return highRes;

    final lowRes = metadata.extras?['lowResImage']?.toString();
    if (lowRes != null && lowRes.isNotEmpty) return lowRes;

    return '';
  }

  @override
  Widget build(BuildContext context) {
    final height = width * 16 / 9;
    final artworkSource = artworkSourceFor(metadata);
    final imageProvider = artworkSource.isEmpty
        ? ArtworkProvider.defaultArtwork
        : ArtworkProvider.get(artworkSource);
    final title = metadata.title.trim().isEmpty ? 'Unknown' : metadata.title;
    final artist = (metadata.artist ?? '').trim().isEmpty
        ? 'Unknown artist'
        : metadata.artist!.trim();
    final coverSize = width * 0.72;

    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WiyaDesign.cornerRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: ColoredBox(
                  color: WiyaDesign.background.withValues(alpha: 0.72),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    WiyaDesign.primaryDeep.withValues(alpha: 0.18),
                    Colors.transparent,
                    WiyaDesign.background.withValues(alpha: 0.92),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                width * 0.08,
                height * 0.1,
                width * 0.08,
                height * 0.08,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: coverSize,
                          height: coverSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              WiyaDesign.cornerRadiusMedium,
                            ),
                            boxShadow: WiyaDesign.softGlow(
                              blur: 36,
                              opacity: 0.35,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              WiyaDesign.cornerRadiusMedium,
                            ),
                            child: Image(
                              image: imageProvider,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Image(
                                image: ArtworkProvider.defaultArtwork,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: height * 0.05),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: WiyaDesign.onSurface,
                            fontSize: width * 0.065,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        SizedBox(height: height * 0.012),
                        Text(
                          artist,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: WiyaDesign.onSurfaceVariant,
                            fontSize: width * 0.042,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/icons/wiyamusic_icon.png',
                          width: 22,
                          height: 22,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'WiyaMusic',
                        style: TextStyle(
                          color: WiyaDesign.onSurface,
                          fontFamily: 'paytoneOne',
                          fontSize: width * 0.045,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens a Spotify-like photocard preview and shares it as a PNG image.
Future<void> showSongSharePhotocard(
  BuildContext context,
  MediaItem metadata,
) async {
  final shareKey = GlobalKey();
  final colorScheme = Theme.of(context).colorScheme;
  final l10n = context.l10n!;
  final title = metadata.title.trim().isEmpty ? 'Unknown' : metadata.title;
  final artist = (metadata.artist ?? '').trim();
  final shareText = artist.isEmpty
      ? '$title\nWiyaMusic'
      : '$title — $artist\nWiyaMusic';

  // Warm the artwork cache so the captured card isn't empty/blank.
  final artworkSource = SongShareCard.artworkSourceFor(metadata);
  if (artworkSource.isNotEmpty) {
    try {
      await precacheImage(ArtworkProvider.get(artworkSource), context);
    } catch (_) {}
  }

  if (!context.mounted) return;

  final previewWidth = (MediaQuery.sizeOf(context).width - 48).clamp(
    260.0,
    360.0,
  );

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      var sharing = false;

      return StatefulBuilder(
        builder: (context, setState) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.share,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: RepaintBoundary(
                      key: shareKey,
                      child: SongShareCard(
                        metadata: metadata,
                        width: previewWidth,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: sharing
                          ? null
                          : () async {
                              setState(() => sharing = true);
                              try {
                                await _captureAndSharePhotocard(
                                  context: context,
                                  key: shareKey,
                                  fileName:
                                      'wiyamusic-share-${DateTime.now().millisecondsSinceEpoch}.png',
                                  shareText: shareText,
                                );
                                if (sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                }
                              } finally {
                                if (context.mounted) {
                                  setState(() => sharing = false);
                                }
                              }
                            },
                      icon: sharing
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.onPrimary,
                              ),
                            )
                          : const Icon(FluentIcons.share_24_filled),
                      label: Text(l10n.share),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<void> _captureAndSharePhotocard({
  required BuildContext context,
  required GlobalKey key,
  required String fileName,
  required String shareText,
}) async {
  try {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;

    await WidgetsBinding.instance.endOfFrame;
    // Give network/file images one more frame to settle before capture.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await WidgetsBinding.instance.endOfFrame;

    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final bytes = byteData?.buffer.asUint8List();
    if (bytes == null) return;

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes);

    final result = await SharePlus.instance.share(
      ShareParams(
        title: shareText,
        subject: shareText,
        text: shareText,
        files: [XFile(file.path, mimeType: 'image/png')],
        fileNameOverrides: [fileName],
      ),
    );

    if (result.status == ShareResultStatus.unavailable && context.mounted) {
      showToast(context, context.l10n!.error);
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error sharing song photocard',
      error: e,
      stackTrace: stackTrace,
    );
    if (context.mounted) showToast(context, context.l10n!.error);
  }
}
