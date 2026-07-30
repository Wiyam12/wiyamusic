import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/services/common_services.dart';
import 'package:wiyamusic/services/router_service.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/utilities/app_utils.dart';
import 'package:wiyamusic/utilities/mediaitem.dart';
import 'package:wiyamusic/widgets/now_playing/marquee_text_widget.dart';
import 'package:wiyamusic/widgets/playback_icon_button.dart';
import 'package:wiyamusic/widgets/position_slider.dart';

class NowPlayingControls extends StatelessWidget {
  const NowPlayingControls({
    super.key,
    required this.size,
    required this.audioId,
    required this.adjustedIconSize,
    required this.adjustedMiniIconSize,
    required this.metadata,
  });

  final Size size;
  final dynamic audioId;
  final double adjustedIconSize;
  final double adjustedMiniIconSize;
  final MediaItem metadata;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = size.width > 800;

    final titleFontSize = getResponsiveTitleFontSize(size);
    final artistFontSize = getResponsiveArtistFontSize(size);
    final canOpenArtist = _canOpenArtist(metadata);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final isCompact = availableHeight < 280;
        final isVeryCompact = availableHeight < 220;

        final spacing = isDesktop
            ? (isVeryCompact
                  ? 6.0
                  : isCompact
                  ? 10.0
                  : 16.0)
            : isVeryCompact
            ? 6.0
            : isCompact
            ? 10.0
            : 16.0;
        // Scale hard in the short iPad control strip so play/repeat never overflow.
        final iconScale = isDesktop
            ? (isVeryCompact
                  ? 0.55
                  : isCompact
                  ? 0.68
                  : 0.85)
            : isVeryCompact
            ? 0.7
            : isCompact
            ? 0.82
            : 1.0;
        final fontScale = isDesktop
            ? (isVeryCompact
                  ? 0.72
                  : isCompact
                  ? 0.8
                  : 0.9)
            : isVeryCompact
            ? 0.85
            : isCompact
            ? 0.9
            : 1.0;
        final controlsMaxWidth = isDesktop
            ? (constraints.maxWidth * 0.72).clamp(420.0, 560.0)
            : constraints.maxWidth;
        final likeSize = isDesktop
            ? (isVeryCompact ? 22.0 : isCompact ? 26.0 : 30.0)
            : 26.0;

        final panel = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: controlsMaxWidth),
              child: _SongMetaRow(
                metadata: metadata,
                titleFontSize: titleFontSize * fontScale,
                artistFontSize: artistFontSize * fontScale,
                canOpenArtist: canOpenArtist,
                onArtistTap: () => _openArtistPage(context, metadata),
                colorScheme: colorScheme,
                centered: isDesktop,
                likeIconSize: likeSize,
              ),
            ),
            SizedBox(height: spacing),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: controlsMaxWidth),
              child: PositionSlider(
                largeControls: isDesktop && !isVeryCompact,
              ),
            ),
            SizedBox(height: spacing * 0.75),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: controlsMaxWidth),
              child: PlayerControlButtons(
                metadata: metadata,
                iconSize: adjustedIconSize * iconScale,
                miniIconSize: adjustedMiniIconSize * iconScale,
                centered: isDesktop,
                controlGap: isDesktop ? (isVeryCompact ? 8 : 14) : 0,
              ),
            ),
          ],
        );

        return ClipRect(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: controlsMaxWidth,
              child: panel,
            ),
          ),
        );
      },
    );
  }

  bool _canOpenArtist(MediaItem metadata) {
    final info = _extractArtistInfo(metadata);
    return !offlineMode.value &&
        (info.artist.isNotEmpty ||
            info.artistId.isNotEmpty ||
            info.sourceSongId.isNotEmpty);
  }

  void _openArtistPage(BuildContext context, MediaItem metadata) {
    final info = _extractArtistInfo(metadata);
    final lookup = info.artistId.isNotEmpty
        ? info.artistId
        : info.artist.isNotEmpty
        ? info.artist
        : info.sourceSongId;

    if (lookup.isEmpty) return;

    final router = GoRouter.of(context);
    final basePath = _artistRouteBasePath(context);
    final artistData = {
      'ytid': info.artistId.isNotEmpty ? info.artistId : lookup,
      if (info.artist.isNotEmpty) 'title': info.artist,
      if (info.sourceSongId.isNotEmpty) 'sourceSongId': info.sourceSongId,
      if (info.videoAuthor.isNotEmpty) 'videoAuthor': info.videoAuthor,
      'source': 'youtube-artist',
      'isArtist': true,
      'list': [],
    };

    Navigator.of(context).pop();
    unawaited(
      router.push(
        '$basePath/artist/${Uri.encodeComponent(lookup)}',
        extra: artistData,
      ),
    );
  }

  ({String artist, String artistId, String sourceSongId, String videoAuthor})
  _extractArtistInfo(MediaItem metadata) {
    return (
      artist: metadata.artist?.trim() ?? '',
      artistId: metadata.extras?['artistId']?.toString().trim() ?? '',
      sourceSongId: metadata.extras?['ytid']?.toString().trim() ?? '',
      videoAuthor: metadata.extras?['videoAuthor']?.toString().trim() ?? '',
    );
  }

  String _artistRouteBasePath(BuildContext context) {
    try {
      final currentPath = GoRouterState.of(context).uri.path;
      if (currentPath.startsWith(NavigationManager.searchPath)) {
        return NavigationManager.searchPath;
      }
      if (currentPath.startsWith(NavigationManager.libraryPath)) {
        return NavigationManager.libraryPath;
      }
    } catch (_) {}

    return NavigationManager.homePath;
  }
}

class _SongMetaRow extends StatelessWidget {
  const _SongMetaRow({
    required this.metadata,
    required this.titleFontSize,
    required this.artistFontSize,
    required this.canOpenArtist,
    required this.onArtistTap,
    required this.colorScheme,
    this.centered = false,
    this.likeIconSize = 26,
  });

  final MediaItem metadata;
  final double titleFontSize;
  final double artistFontSize;
  final bool canOpenArtist;
  final VoidCallback onArtistTap;
  final ColorScheme colorScheme;
  final bool centered;
  final double likeIconSize;

  @override
  Widget build(BuildContext context) {
    if (centered) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: MarqueeTextWidget(
                  text: metadata.title,
                  fontColor: colorScheme.onSurface,
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.w700,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 6),
              _OfflineDownloadIndicator(metadata: metadata),
              _LikeButton(metadata: metadata, iconSize: likeIconSize),
            ],
          ),
          if (metadata.artist != null) ...[
            const SizedBox(height: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: canOpenArtist ? onArtistTap : null,
              child: MarqueeTextWidget(
                text: metadata.artist!,
                fontColor: colorScheme.onSurfaceVariant,
                fontSize: artistFontSize,
                fontWeight: FontWeight.w500,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MarqueeTextWidget(
                text: metadata.title,
                fontColor: colorScheme.onSurface,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w700,
              ),
              const SizedBox(height: 4),
              if (metadata.artist != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: canOpenArtist ? onArtistTap : null,
                  child: MarqueeTextWidget(
                    text: metadata.artist!,
                    fontColor: colorScheme.onSurfaceVariant,
                    fontSize: artistFontSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _OfflineDownloadIndicator(metadata: metadata),
        _LikeButton(metadata: metadata, iconSize: likeIconSize),
      ],
    );
  }
}

/// Matches the song-bar offline trailing: progress ring while downloading,
/// cloud icon when already offline.
class _OfflineDownloadIndicator extends StatefulWidget {
  const _OfflineDownloadIndicator({required this.metadata});

  final MediaItem metadata;

  @override
  State<_OfflineDownloadIndicator> createState() =>
      _OfflineDownloadIndicatorState();
}

class _OfflineDownloadIndicatorState extends State<_OfflineDownloadIndicator> {
  late final ValueNotifier<bool> _offlineStatus;

  bool get isRadioStation => widget.metadata.extras?['isLive'] == true;

  String? get audioId {
    if (isRadioStation) return null;
    final ytid = widget.metadata.extras?['ytid']?.toString().trim();
    if (ytid != null && ytid.isNotEmpty) return ytid;
    return widget.metadata.id;
  }

  @override
  void initState() {
    super.initState();
    _offlineStatus = ValueNotifier<bool>(isSongAlreadyOffline(audioId));
    userOfflineSongs.addListener(_syncOfflineStatus);
  }

  void _syncOfflineStatus() {
    final next = isSongAlreadyOffline(audioId);
    if (_offlineStatus.value != next) {
      _offlineStatus.value = next;
    }
  }

  @override
  void didUpdateWidget(covariant _OfflineDownloadIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metadata.id != widget.metadata.id) {
      _offlineStatus.value = isSongAlreadyOffline(audioId);
    }
  }

  @override
  void dispose() {
    userOfflineSongs.removeListener(_syncOfflineStatus);
    _offlineStatus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = audioId;
    if (id == null || id.isEmpty || isRadioStation) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final progressListenable = songDownloadProgressNotifier(id);

    return ValueListenableBuilder<bool>(
      valueListenable: _offlineStatus,
      builder: (context, isOffline, _) {
        return ValueListenableBuilder<double?>(
          valueListenable: progressListenable,
          builder: (context, progress, _) {
            final isDownloading = progress != null;
            if (!isOffline && !isDownloading) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: SizedBox(
                width: 28,
                height: 28,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isDownloading)
                      CircularProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        strokeWidth: 2.4,
                        backgroundColor: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.2),
                        color: colorScheme.primary,
                      ),
                    Icon(
                      FluentIcons.cloud_off_24_regular,
                      size: 15,
                      color: isDownloading
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
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
}

class _LikeButton extends StatefulWidget {
  const _LikeButton({required this.metadata, this.iconSize = 26});

  final MediaItem metadata;
  final double iconSize;

  @override
  State<_LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton> {
  late final ValueNotifier<bool> _songLikeStatus;

  bool get isRadioStation => widget.metadata.extras?['isLive'] == true;

  String? get audioId {
    if (isRadioStation) return widget.metadata.id;
    final ytid = widget.metadata.extras?['ytid']?.toString().trim();
    if (ytid != null && ytid.isNotEmpty) return ytid;
    return widget.metadata.id;
  }

  @override
  void initState() {
    super.initState();
    if (isRadioStation) {
      _songLikeStatus = ValueNotifier<bool>(isRadioStationLiked(audioId ?? ''));
      userLikedRadioStations.addListener(_syncRadioLikeStatus);
    } else {
      _songLikeStatus = ValueNotifier<bool>(isSongAlreadyLiked(audioId));
      userLikedSongsList.addListener(_syncLikeStatus);
    }
  }

  void _syncLikeStatus() {
    final newStatus = isSongAlreadyLiked(audioId);
    if (_songLikeStatus.value != newStatus) {
      _songLikeStatus.value = newStatus;
    }
  }

  void _syncRadioLikeStatus() {
    final newStatus = isRadioStationLiked(audioId ?? '');
    if (_songLikeStatus.value != newStatus) {
      _songLikeStatus.value = newStatus;
    }
  }

  @override
  void didUpdateWidget(covariant _LikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metadata.id != widget.metadata.id) {
      if (isRadioStation) {
        _songLikeStatus.value = isRadioStationLiked(audioId ?? '');
      } else {
        _songLikeStatus.value = isSongAlreadyLiked(audioId);
      }
    }
  }

  @override
  void dispose() {
    if (isRadioStation) {
      userLikedRadioStations.removeListener(_syncRadioLikeStatus);
    } else {
      userLikedSongsList.removeListener(_syncLikeStatus);
    }
    _songLikeStatus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (offlineMode.value) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<bool>(
      valueListenable: _songLikeStatus,
      builder: (_, isLiked, __) {
        return IconButton(
          icon: Icon(
            isLiked
                ? FluentIcons.heart_24_filled
                : FluentIcons.heart_24_regular,
            color: isLiked ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          iconSize: widget.iconSize,
          tooltip: context.l10n!.likedSongs,
          onPressed: () async {
            final id = audioId;
            if (id == null) return;

            final originalValue = _songLikeStatus.value;
            _songLikeStatus.value = !originalValue;

            try {
              if (isRadioStation) {
                if (originalValue) {
                  await removeRadioStationFromLiked(id);
                } else {
                  await addRadioStationToLiked(id);
                }
              } else {
                await updateSongLikeStatus(
                  audioId,
                  !originalValue,
                  songData: mediaItemToMap(widget.metadata),
                );
              }
            } catch (e) {
              _songLikeStatus.value = originalValue;
              logger.log('Error toggling like status', error: e);
            }
          },
        );
      },
    );
  }
}

class PlayerControlButtons extends StatelessWidget {
  const PlayerControlButtons({
    super.key,
    required this.metadata,
    required this.iconSize,
    required this.miniIconSize,
    this.centered = false,
    this.controlGap = 0,
  });
  final MediaItem metadata;
  final double iconSize;
  final double miniIconSize;
  final bool centered;
  final double controlGap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final controlSize = screenWidth < 360 ? iconSize * 0.9 : iconSize;
    final sideSize = screenWidth < 360 ? miniIconSize * 0.95 : miniIconSize;
    final gap = centered ? (controlGap > 0 ? controlGap : 12.0) : 0.0;

    return StreamBuilder<List<MediaItem>>(
      stream: audioHandler.queue,
      builder: (context, snapshot) {
        return ValueListenableBuilder<AudioServiceRepeatMode>(
          valueListenable: repeatNotifier,
          builder: (_, repeatMode, __) {
            final children = <Widget>[
              _buildShuffleButton(context, colorScheme, sideSize),
              _FlatControlButton(
                icon: FluentIcons.previous_24_filled,
                isEnabled:
                    audioHandler.hasPrevious ||
                    repeatMode != AudioServiceRepeatMode.none,
                tooltip: context.l10n!.skipToPrevious,
                onPressed: () => audioHandler.skipToPrevious(),
                colorScheme: colorScheme,
                iconSize: controlSize,
              ),
              PlaybackIconButton(
                iconColor: colorScheme.onPrimary,
                backgroundColor: colorScheme.primary,
                iconSize: controlSize * 1.05,
                padding: EdgeInsets.all(controlSize * 0.42),
              ),
              _FlatControlButton(
                icon: FluentIcons.next_24_filled,
                // Repeat All keeps Next enabled so the last song can loop
                // back to the first track of the current playlist.
                isEnabled:
                    audioHandler.hasNext ||
                    repeatMode != AudioServiceRepeatMode.none,
                tooltip: context.l10n!.skipToNext,
                onPressed: () => repeatMode == AudioServiceRepeatMode.one
                    ? audioHandler.playAgain()
                    : audioHandler.skipToNext(),
                colorScheme: colorScheme,
                iconSize: controlSize,
              ),
              _buildRepeatButton(
                context,
                colorScheme,
                sideSize,
                snapshot.data ?? [],
              ),
            ];

            return Row(
              mainAxisAlignment: centered
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.spaceBetween,
              children: centered
                  ? [
                      for (var i = 0; i < children.length; i++) ...[
                        if (i > 0) SizedBox(width: gap),
                        children[i],
                      ],
                    ]
                  : children,
            );
          },
        );
      },
    );
  }

  Widget _buildShuffleButton(
    BuildContext context,
    ColorScheme colorScheme,
    double size,
  ) {
    return ValueListenableBuilder<bool>(
      valueListenable: shuffleNotifier,
      builder: (_, value, __) {
        return IconButton(
          icon: Icon(
            FluentIcons.arrow_shuffle_24_regular,
            color: value ? colorScheme.primary : colorScheme.onSurface,
          ),
          tooltip: context.l10n!.shuffle,
          iconSize: size,
          onPressed: () {
            audioHandler.setShuffleMode(
              value
                  ? AudioServiceShuffleMode.none
                  : AudioServiceShuffleMode.all,
            );
          },
        );
      },
    );
  }

  Widget _buildRepeatButton(
    BuildContext context,
    ColorScheme colorScheme,
    double size,
    List<MediaItem> queue,
  ) {
    return ValueListenableBuilder<AudioServiceRepeatMode>(
      valueListenable: repeatNotifier,
      builder: (_, repeatMode, __) {
        final isActive = repeatMode != AudioServiceRepeatMode.none;

        return IconButton(
          icon: Icon(
            repeatMode == AudioServiceRepeatMode.one
                ? FluentIcons.arrow_repeat_1_24_regular
                : FluentIcons.arrow_repeat_all_24_regular,
            color: isActive ? colorScheme.primary : colorScheme.onSurface,
          ),
          tooltip: context.l10n!.repeat,
          iconSize: size,
          onPressed: () {
            final AudioServiceRepeatMode newMode;
            if (repeatMode == AudioServiceRepeatMode.none) {
              newMode = queue.length <= 1
                  ? AudioServiceRepeatMode.one
                  : AudioServiceRepeatMode.all;
            } else if (repeatMode == AudioServiceRepeatMode.all) {
              newMode = AudioServiceRepeatMode.one;
            } else {
              newMode = AudioServiceRepeatMode.none;
            }
            repeatNotifier.value = newMode;
            audioHandler.setRepeatMode(newMode);
          },
        );
      },
    );
  }
}

class _FlatControlButton extends StatelessWidget {
  const _FlatControlButton({
    required this.icon,
    required this.isEnabled,
    required this.tooltip,
    required this.onPressed,
    required this.colorScheme,
    required this.iconSize,
  });

  final IconData icon;
  final bool isEnabled;
  final String tooltip;
  final VoidCallback onPressed;
  final ColorScheme colorScheme;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        icon,
        color: isEnabled
            ? colorScheme.onSurface
            : colorScheme.onSurface.withValues(alpha: 0.3),
      ),
      tooltip: tooltip,
      iconSize: iconSize,
      onPressed: isEnabled ? onPressed : null,
    );
  }
}
