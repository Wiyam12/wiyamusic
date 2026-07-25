/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     WiyaMusic is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     WiyaMusic is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about WiyaMusic, including how to contribute,
 *     please visit: https://github.com/Wiyam12/wiyamusic
 */

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/models/song_lyrics.dart';
import 'package:wiyamusic/services/common_services.dart';
import 'package:wiyamusic/utilities/async_loader.dart';
import 'package:wiyamusic/widgets/now_playing/synced_lyrics_view.dart';
import 'package:wiyamusic/widgets/song_artwork.dart';

/// Toggles artwork ↔ lyrics with a fade (replaces FlipCard).
class NowPlayingLyricsController {
  final ValueNotifier<bool> showingLyrics = ValueNotifier<bool>(false);

  void toggle() {
    showingLyrics.value = !showingLyrics.value;
  }

  void dispose() {
    showingLyrics.dispose();
  }
}

class NowPlayingArtwork extends StatelessWidget {
  const NowPlayingArtwork({
    super.key,
    required this.size,
    required this.metadata,
    required this.lyricsController,
  });
  final Size size;
  final MediaItem metadata;
  final NowPlayingLyricsController lyricsController;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : width;

        return SizedBox(
          width: width,
          height: height,
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [0.0, 0.14, 0.86, 1.0],
              ).createShader(bounds);
            },
            child: ValueListenableBuilder<bool>(
              valueListenable: lyricsController.showingLyrics,
              builder: (context, showingLyrics, _) {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: showingLyrics
                      ? KeyedSubtree(
                          key: ValueKey(
                            'lyrics-${metadata.id}-${metadata.title}',
                          ),
                          child: SizedBox(
                            width: width,
                            height: height,
                            child: ColoredBox(
                              color: colorScheme.surfaceContainerHigh,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: lyricsController.toggle,
                                child: AsyncLoader<SongLyrics?>(
                                  future: getSongLyricsData(
                                    artist: metadata.artist,
                                    title: metadata.title,
                                    album: metadata.album,
                                    duration: metadata.duration,
                                    songId:
                                        metadata.extras?['ytid']?.toString(),
                                  ),
                                  emptyWidget: _LyricsPlaceholder(
                                    colorScheme: colorScheme,
                                    message: context.l10n!.lyricsNotAvailable,
                                  ),
                                  errorBuilder: (ctx, error, stack) =>
                                      _LyricsPlaceholder(
                                        colorScheme: colorScheme,
                                        message:
                                            context.l10n!.lyricsNotAvailable,
                                      ),
                                  builder: (context, songLyrics) {
                                    final data = songLyrics;
                                    if (data == null || data.isEmpty) {
                                      return _LyricsPlaceholder(
                                        colorScheme: colorScheme,
                                        message:
                                            context.l10n!.lyricsNotAvailable,
                                      );
                                    }
                                    return SyncedLyricsView(
                                      lyrics: data,
                                      onToggleArtwork: lyricsController.toggle,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        )
                      : KeyedSubtree(
                          key: const ValueKey('artwork'),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: lyricsController.toggle,
                            child: SongArtworkWidget(
                              metadata: metadata,
                              size: width,
                              width: width,
                              height: height,
                              errorWidgetIconSize: size.width / 8,
                              borderRadius: 0,
                            ),
                          ),
                        ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _LyricsPlaceholder extends StatelessWidget {
  const _LyricsPlaceholder({
    required this.colorScheme,
    required this.message,
  });

  final ColorScheme colorScheme;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.text_quote_24_regular,
            size: 48,
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
