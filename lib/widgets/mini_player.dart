import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:animated_icon/animated_icon.dart';
import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:wiyamusic/constants/app_constants.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/models/full_player_state.dart';
import 'package:wiyamusic/models/position_data.dart';
import 'package:wiyamusic/screens/now_playing_page.dart';
import 'package:wiyamusic/services/common_services.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/theme/design_tokens.dart';
import 'package:wiyamusic/utilities/mediaitem.dart';
import 'package:wiyamusic/widgets/marquee.dart';
import 'package:wiyamusic/widgets/song_artwork.dart';
import 'package:wiyamusic/widgets/wiya_animated_icon.dart';

final Stream<FullPlayerState> _fullPlayerStateStream =
    Rx.combineLatest3(
          audioHandler.playbackStateStream,
          audioHandler.queue.distinct(),
          audioHandler.positionDataStream,
          (PlaybackState state, List<MediaItem> queue, PositionData pos) =>
              FullPlayerState(
                playbackState: state,
                queue: queue,
                position: pos,
              ),
        )
        .throttleTime(const Duration(milliseconds: 120), trailing: true)
        .asBroadcastStream();

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  static const double playerHeight = 72;
  static const double _borderRadius = WiyaDesign.cornerRadius;
  static const double _artworkSize = 52;
  static const double _artworkRadius = WiyaDesign.cornerRadiusSmall;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showExtendedControls =
        MediaQuery.sizeOf(context).width >= tabletNavigationBreakpoint;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: StreamBuilder<MediaItem?>(
        stream: audioHandler.mediaItem,
        builder: (context, mediaSnapshot) {
          final metadata = mediaSnapshot.data;
          if (metadata == null) return const SizedBox.shrink();

          return StreamBuilder<FullPlayerState>(
            stream: _fullPlayerStateStream,
            builder: (context, stateSnapshot) {
              final state = stateSnapshot.data;
              if (state == null) return const SizedBox.shrink();

              final hasNext =
                  state.queue.length > 1 &&
                  (state.playbackState.queueIndex ?? 0) <
                      state.queue.length - 1;

              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: showExtendedControls ? 30 : 0,
                ),
                child: _MiniPlayerBody(
                  colorScheme: colorScheme,
                  metadata: metadata,
                  state: state,
                  hasNext: hasNext,
                  showExtendedControls: showExtendedControls,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MiniPlayerBody extends StatefulWidget {
  const _MiniPlayerBody({
    required this.colorScheme,
    required this.metadata,
    required this.state,
    required this.hasNext,
    required this.showExtendedControls,
  });

  final ColorScheme colorScheme;
  final MediaItem metadata;
  final FullPlayerState state;
  final bool hasNext;
  final bool showExtendedControls;

  @override
  State<_MiniPlayerBody> createState() => _MiniPlayerBodyState();
}

class _MiniPlayerBodyState extends State<_MiniPlayerBody>
    with TickerProviderStateMixin {
  late final AnimationController _pressController;
  late final AnimationController _glowController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1, end: 0.98).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    if (widget.state.playbackState.playing) {
      _glowController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _MiniPlayerBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isPlaying = widget.state.playbackState.playing;
    final wasPlaying = oldWidget.state.playbackState.playing;
    if (isPlaying == wasPlaying) return;
    if (isPlaying) {
      _glowController.repeat();
    } else {
      _glowController.stop();
    }
  }

  @override
  void dispose() {
    _pressController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  static const double _dragThresholdForNavigation = 10;

  void _handleVerticalDrag(DragUpdateDetails details) {
    if ((details.primaryDelta ?? 0) < -_dragThresholdForNavigation) {
      _navigateToNowPlaying();
    }
  }

  void _navigateToNowPlaying() {
    Navigator.of(context).push(_createSlideTransition());
  }

  PageRoute<void> _createSlideTransition() {
    return PageRouteBuilder<void>(
      pageBuilder: (context, animation, _) => const NowPlayingPage(),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final tween = Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeInOut));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final metadata = widget.metadata;
    final state = widget.state;

    final totalDuration = state.position.duration > Duration.zero
        ? state.position.duration
        : (metadata.duration ?? Duration.zero);
    final progress = totalDuration.inMilliseconds == 0
        ? 0.0
        : (state.position.position.inMilliseconds /
                  totalDuration.inMilliseconds)
              .clamp(0.0, 1.0);

    return Dismissible(
      key: ValueKey('mini-player-${metadata.id}'),
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.35,
        DismissDirection.endToStart: 0.35,
      },
      onDismissed: (_) {
        unawaited(audioHandler.dismissPlayer());
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: GestureDetector(
          onTapDown: (_) => _pressController.forward(),
          onTapUp: (_) => _pressController.reverse(),
          onTapCancel: () => _pressController.reverse(),
          onVerticalDragUpdate: _handleVerticalDrag,
          onTap: _navigateToNowPlaying,
          child: SizedBox(
            height: MiniPlayer.playerHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(MiniPlayer._borderRadius),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: WiyaDesign.blurSigma * 0.45,
                      sigmaY: WiyaDesign.blurSigma * 0.45,
                    ),
                    child: Container(
                      decoration: WiyaDesign.glassSurface(
                        colorScheme: colorScheme,
                        fillOpacity: 0.62,
                        withGlow: true,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.showExtendedControls ? 16 : 10,
                      ),
                      child: Row(
                        children: [
                          _ArtworkWidget(metadata: metadata),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              switchInCurve: Curves.easeIn,
                              switchOutCurve: Curves.easeOut,
                              layoutBuilder: (currentChild, previousChildren) =>
                                  Stack(
                                    alignment: Alignment.centerLeft,
                                    children: [
                                      ...previousChildren,
                                      if (currentChild != null) currentChild,
                                    ],
                                  ),
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                              child: KeyedSubtree(
                                key: ValueKey(metadata.id),
                                child: _MetadataWidget(
                                  title: metadata.title,
                                  artist: metadata.artist,
                                  colorScheme: colorScheme,
                                ),
                              ),
                            ),
                          ),
                          _ControlsWidget(
                            colorScheme: colorScheme,
                            metadata: metadata,
                            playbackState: state.playbackState,
                            hasNext: widget.hasNext,
                            progress: progress,
                            showExtendedControls: widget.showExtendedControls,
                            queue: state.queue,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (state.playbackState.playing)
                  IgnorePointer(
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _glowController,
                        builder: (context, _) {
                          return CustomPaint(
                            painter: _MiniPlayerGlowBorderPainter(
                              progress: _glowController.value,
                              borderRadius: MiniPlayer._borderRadius,
                              color: WiyaDesign.primary,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft neon trail that travels along the Mini Player's rounded border path.
class _MiniPlayerGlowBorderPainter extends CustomPainter {
  _MiniPlayerGlowBorderPainter({
    required this.progress,
    required this.borderRadius,
    required this.color,
  });

  final double progress;
  final double borderRadius;
  final Color color;

  static const double _strokeInset = 1.25;
  static const double _trailFraction = 0.26;
  static const int _trailSteps = 28;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        _strokeInset,
        _strokeInset,
        size.width - _strokeInset * 2,
        size.height - _strokeInset * 2,
      ),
      Radius.circular(math.max(0, borderRadius - _strokeInset)),
    );
    final path = Path()..addRRect(rrect);
    // PathMetrics is single-pass — do not call isEmpty before first.
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final length = metric.length;
    if (length <= 0) return;

    // Quiet base rim so the shape reads even between glow peaks.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.14),
    );

    final head = progress * length;
    final trailLength = length * _trailFraction;

    for (var i = 0; i < _trailSteps; i++) {
      final t = i / (_trailSteps - 1); // 0 = tail, 1 = head
      final eased = Curves.easeIn.transform(t);
      final start = (head - trailLength * (1 - t) + length * 4) % length;
      final end =
          (head - trailLength * (1 - (i + 1) / _trailSteps) + length * 4) %
          length;

      final segment = _extractWrappedPath(metric, length, start, end);
      if (segment == null) continue;

      final alpha = 0.08 + eased * 0.72;
      final strokeWidth = 1.1 + eased * 1.8;

      canvas.drawPath(
        segment,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color.withValues(alpha: alpha),
      );
    }

    // Soft bloom near the leading edge only (one blur pass).
    final bloomStart = (head - length * 0.5 + length) % length;
    final bloomEnd = (head + length * 0.001) % length;
    final bloomPath = _extractWrappedPath(metric, length, bloomStart, bloomEnd);
    if (bloomPath != null) {
      canvas.drawPath(
        bloomPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawPath(
        bloomPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.95),
      );
    }
  }

  Path? _extractWrappedPath(
    PathMetric metric,
    double length,
    double start,
    double end,
  ) {
    start = start % length;
    end = end % length;
    if ((end - start).abs() < 0.4 && start > end) {
      // Degenerate tiny wrap; skip.
      return null;
    }

    if (end >= start) {
      return metric.extractPath(start, end);
    }

    // Segment wraps past the path origin.
    return Path()
      ..addPath(metric.extractPath(start, length), Offset.zero)
      ..addPath(metric.extractPath(0, end), Offset.zero);
  }

  @override
  bool shouldRepaint(covariant _MiniPlayerGlowBorderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.color != color;
  }
}

class _ArtworkWidget extends StatelessWidget {
  const _ArtworkWidget({required this.metadata});
  final MediaItem metadata;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Hero(
        tag: 'now_playing_artwork',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MiniPlayer._artworkRadius),
            boxShadow: WiyaDesign.softGlow(
              color: Theme.of(context).colorScheme.primary,
              blur: 14,
              opacity: 0.22,
            ),
          ),
          child: SongArtworkWidget(
            metadata: metadata,
            size: MiniPlayer._artworkSize,
            errorWidgetIconSize: 24,
            borderRadius: MiniPlayer._artworkRadius,
          ),
        ),
      ),
    );
  }
}

class _MetadataWidget extends StatelessWidget {
  const _MetadataWidget({
    required this.title,
    required this.artist,
    required this.colorScheme,
  });

  final String title;
  final String? artist;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarqueeWidget(
            manualScrollEnabled: false,
            animationDuration: const Duration(seconds: 8),
            backDuration: const Duration(seconds: 2),
            pauseDuration: const Duration(seconds: 2),
            child: Text(
              title,
              style: TextStyle(
                color: colorScheme.secondary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (artist != null && artist!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              artist!,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _ControlsWidget extends StatelessWidget {
  const _ControlsWidget({
    required this.colorScheme,
    required this.metadata,
    required this.playbackState,
    required this.hasNext,
    required this.progress,
    required this.showExtendedControls,
    required this.queue,
  });

  final ColorScheme colorScheme;
  final MediaItem metadata;
  final PlaybackState playbackState;
  final bool hasNext;
  final double progress;
  final bool showExtendedControls;
  final List<MediaItem> queue;

  @override
  Widget build(BuildContext context) {
    final isPlaying = playbackState.playing;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showExtendedControls) ...[
          _MiniLikeButton(
            key: ValueKey('mini-like-${metadata.id}'),
            metadata: metadata,
            colorScheme: colorScheme,
          ),
          _MiniShuffleButton(colorScheme: colorScheme),
          _MiniRepeatButton(colorScheme: colorScheme, queue: queue),
          const SizedBox(width: 4),
        ] else if (isPlaying) ...[
          WiyaAnimatedIcon(
            icon: AnimateIcons.activity,
            size: 22,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 6),
        ],
        _CircularPlayButton(
          colorScheme: colorScheme,
          playbackState: playbackState,
          progress: progress,
        ),
        if (hasNext) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: audioHandler.skipToNext,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            icon: Icon(
              FluentIcons.next_24_filled,
              color: colorScheme.onSurfaceVariant,
              size: 24,
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );
  }
}

class _MiniLikeButton extends StatefulWidget {
  const _MiniLikeButton({
    super.key,
    required this.metadata,
    required this.colorScheme,
  });

  final MediaItem metadata;
  final ColorScheme colorScheme;

  @override
  State<_MiniLikeButton> createState() => _MiniLikeButtonState();
}

class _MiniLikeButtonState extends State<_MiniLikeButton> {
  late final ValueNotifier<bool> _songLikeStatus;

  bool get _isRadioStation => widget.metadata.extras?['isLive'] == true;

  String? get _audioId {
    if (_isRadioStation) return widget.metadata.id;
    final ytid = widget.metadata.extras?['ytid']?.toString().trim();
    if (ytid != null && ytid.isNotEmpty) return ytid;
    return widget.metadata.id;
  }

  @override
  void initState() {
    super.initState();
    if (_isRadioStation) {
      _songLikeStatus = ValueNotifier(isRadioStationLiked(_audioId ?? ''));
      userLikedRadioStations.addListener(_syncRadioLikeStatus);
    } else {
      _songLikeStatus = ValueNotifier(isSongAlreadyLiked(_audioId));
      userLikedSongsList.addListener(_syncLikeStatus);
    }
  }

  void _syncLikeStatus() {
    final newStatus = isSongAlreadyLiked(_audioId);
    if (_songLikeStatus.value != newStatus) {
      _songLikeStatus.value = newStatus;
    }
  }

  void _syncRadioLikeStatus() {
    final newStatus = isRadioStationLiked(_audioId ?? '');
    if (_songLikeStatus.value != newStatus) {
      _songLikeStatus.value = newStatus;
    }
  }

  @override
  void didUpdateWidget(covariant _MiniLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metadata.id != widget.metadata.id) {
      if (_isRadioStation) {
        _songLikeStatus.value = isRadioStationLiked(_audioId ?? '');
      } else {
        _songLikeStatus.value = isSongAlreadyLiked(_audioId);
      }
    }
  }

  @override
  void dispose() {
    if (_isRadioStation) {
      userLikedRadioStations.removeListener(_syncRadioLikeStatus);
    } else {
      userLikedSongsList.removeListener(_syncLikeStatus);
    }
    _songLikeStatus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (offlineMode.value) return const SizedBox.shrink();

    return ValueListenableBuilder<bool>(
      valueListenable: _songLikeStatus,
      builder: (_, isLiked, __) {
        return IconButton(
          onPressed: () async {
            final id = _audioId;
            if (id == null) return;

            final originalValue = _songLikeStatus.value;
            _songLikeStatus.value = !originalValue;

            try {
              if (_isRadioStation) {
                if (originalValue) {
                  await removeRadioStationFromLiked(id);
                } else {
                  await addRadioStationToLiked(id);
                }
              } else {
                await updateSongLikeStatus(
                  id,
                  !originalValue,
                  songData: mediaItemToMap(widget.metadata),
                );
              }
            } catch (e) {
              _songLikeStatus.value = originalValue;
              logger.log('Error toggling like status', error: e);
            }
          },
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          tooltip: context.l10n!.likedSongs,
          icon: Icon(
            isLiked
                ? FluentIcons.heart_24_filled
                : FluentIcons.heart_24_regular,
            color: isLiked
                ? widget.colorScheme.primary
                : widget.colorScheme.onSurfaceVariant,
            size: 22,
          ),
          visualDensity: VisualDensity.compact,
        );
      },
    );
  }
}

class _MiniShuffleButton extends StatelessWidget {
  const _MiniShuffleButton({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: shuffleNotifier,
      builder: (_, value, __) {
        return IconButton(
          onPressed: () {
            audioHandler.setShuffleMode(
              value
                  ? AudioServiceShuffleMode.none
                  : AudioServiceShuffleMode.all,
            );
          },
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          tooltip: context.l10n!.shuffle,
          icon: Icon(
            FluentIcons.arrow_shuffle_24_regular,
            color: value ? colorScheme.primary : colorScheme.onSurfaceVariant,
            size: 22,
          ),
          visualDensity: VisualDensity.compact,
        );
      },
    );
  }
}

class _MiniRepeatButton extends StatelessWidget {
  const _MiniRepeatButton({required this.colorScheme, required this.queue});

  final ColorScheme colorScheme;
  final List<MediaItem> queue;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioServiceRepeatMode>(
      valueListenable: repeatNotifier,
      builder: (_, repeatMode, __) {
        final isActive = repeatMode != AudioServiceRepeatMode.none;

        return IconButton(
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
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          tooltip: context.l10n!.repeat,
          icon: Icon(
            repeatMode == AudioServiceRepeatMode.one
                ? FluentIcons.arrow_repeat_1_24_regular
                : FluentIcons.arrow_repeat_all_24_regular,
            color: isActive
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
            size: 22,
          ),
          visualDensity: VisualDensity.compact,
        );
      },
    );
  }
}

class _CircularPlayButton extends StatelessWidget {
  const _CircularPlayButton({
    required this.colorScheme,
    required this.playbackState,
    required this.progress,
  });

  final ColorScheme colorScheme;
  final PlaybackState playbackState;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: audioHandler.isPlayRequestPending,
      builder: (context, playRequestPending, _) {
        final processingState = playbackState.processingState;
        final isPlaying = playbackState.playing;
        final isLoading =
            playRequestPending ||
            processingState == AudioProcessingState.loading ||
            processingState == AudioProcessingState.buffering;
        final isCompleted = processingState == AudioProcessingState.completed;

        return SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(48, 48),
                painter: _CircularProgressPainter(
                  progress: progress,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  progressColor: colorScheme.primary,
                  strokeWidth: 3,
                ),
              ),
              if (isLoading)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colorScheme.primary,
                    ),
                  ),
                )
              else
                IconButton(
                  onPressed: isCompleted
                      ? () => audioHandler.playAgain()
                      : (isPlaying ? audioHandler.pause : audioHandler.play),
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  icon: Icon(
                    isCompleted
                        ? FluentIcons.arrow_counterclockwise_24_filled
                        : (isPlaying
                              ? FluentIcons.pause_16_filled
                              : FluentIcons.play_16_filled),
                    color: colorScheme.primary,
                    size: 22,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CircularProgressPainter extends CustomPainter {
  _CircularProgressPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CircularProgressPainter old) =>
      old.progress != progress ||
      old.backgroundColor != backgroundColor ||
      old.progressColor != progressColor ||
      old.strokeWidth != strokeWidth;
}
