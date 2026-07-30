import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/models/position_data.dart';
import 'package:wiyamusic/utilities/formatter.dart';
import 'package:wiyamusic/utilities/mediaitem.dart';

class PositionSlider extends StatefulWidget {
  const PositionSlider({super.key, this.largeControls = false});

  /// Larger track, thumb, and time labels for iPad / desktop layouts.
  final bool largeControls;

  @override
  State<PositionSlider> createState() => _PositionSliderState();
}

class _PositionSliderState extends State<PositionSlider> {
  bool _isDragging = false;
  double _dragValue = 0;

  PositionData _positionData = PositionData(
    Duration.zero,
    Duration.zero,
    Duration.zero,
  );

  /// Bound to the current [MediaItem.id] so a track change can snap the UI
  /// back to 0:00 immediately — even while the player still reports the
  /// previous song's end position during loading.
  String? _boundMediaId;

  /// While true, ignore stale high positions from the previous track.
  bool _holdAtStart = false;

  /// Last raw position from the player (including values ignored while holding).
  Duration? _lastRawPosition;

  DateTime? _holdStartedAt;

  StreamSubscription<MediaItem?>? _mediaSubscription;
  StreamSubscription<PositionData>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _onMediaItem(audioHandler.mediaItem.valueOrNull);
    _applyPositionData(
      PositionData(
        audioHandler.audioPlayer.position,
        audioHandler.audioPlayer.bufferedPosition,
        resolveReportedDuration(
          audioHandler.mediaItem.valueOrNull?.duration,
          audioHandler.audioPlayer.duration ?? Duration.zero,
        ),
      ),
    );

    _mediaSubscription = audioHandler.mediaItem.listen(_onMediaItem);
    _positionSubscription = audioHandler.positionDataStream.listen(
      _applyPositionData,
    );
  }

  @override
  void dispose() {
    _mediaSubscription?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _onMediaItem(MediaItem? media) {
    final mediaId = media?.id;
    if (mediaId == null || mediaId == _boundMediaId) {
      // Same track: keep duration in sync when MediaItem is enriched later.
      if (mediaId != null &&
          media?.duration != null &&
          media!.duration! > Duration.zero &&
          media.duration != _positionData.duration) {
        _updatePositionData(
          PositionData(
            _positionData.position,
            _positionData.bufferedPosition,
            media.duration!,
          ),
        );
      }
      return;
    }

    final isInitialBind = _boundMediaId == null;
    _boundMediaId = mediaId;
    _lastRawPosition = null;

    if (isInitialBind) {
      // Opening Now Playing mid-song must adopt the live position — do not
      // pin to 0:00 waiting for a near-zero tick that will never arrive.
      _holdAtStart = false;
      _holdStartedAt = null;
      if (mounted) setState(() {});
      return;
    }

    _holdAtStart = true;
    _holdStartedAt = DateTime.now();
    _updatePositionData(
      PositionData(
        Duration.zero,
        Duration.zero,
        media?.duration ?? Duration.zero,
      ),
    );
  }

  void _applyPositionData(PositionData data) {
    if (_holdAtStart) {
      final previousRaw = _lastRawPosition;
      _lastRawPosition = data.position;

      final nearStart = data.position.inMilliseconds < 4000;
      final jumpedBack =
          previousRaw != null &&
          previousRaw.inMilliseconds > 4000 &&
          previousRaw - data.position > const Duration(seconds: 1);
      final holdTimedOut =
          _holdStartedAt != null &&
          DateTime.now().difference(_holdStartedAt!) >
              const Duration(seconds: 3) &&
          audioHandler.audioPlayer.playing;

      if (nearStart || jumpedBack || holdTimedOut) {
        _holdAtStart = false;
        _holdStartedAt = null;
        _updatePositionData(data);
      }
      return;
    }

    _lastRawPosition = data.position;
    _updatePositionData(data);
  }

  void _updatePositionData(PositionData data) {
    if (!mounted) return;
    setState(() => _positionData = data);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final large = widget.largeControls;

    // Guard against inflated offline-file metadata if the stream briefly
    // emits the raw player duration before correction.
    final known = audioHandler.mediaItem.valueOrNull?.duration;
    final safeDuration = resolveReportedDuration(
      known,
      _positionData.duration,
    );

    final maxDuration = safeDuration.inSeconds > 0
        ? safeDuration.inSeconds.toDouble()
        : 1.0;

    final currentValue = _isDragging
        ? _dragValue
        : _positionData.position.inSeconds.toDouble();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: large ? 4.5 : 3,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: large ? 9 : 7,
            ),
            overlayShape: RoundSliderOverlayShape(
              overlayRadius: large ? 20 : 16,
            ),
            activeTrackColor: colorScheme.primary,
            inactiveTrackColor: colorScheme.outlineVariant,
            thumbColor: colorScheme.primary,
            overlayColor: colorScheme.primary.withValues(alpha: 0.18),
          ),
          child: Slider(
            value: currentValue.clamp(0.0, maxDuration),
            onChanged: (value) {
              setState(() {
                _isDragging = true;
                _dragValue = value;
              });
            },
            onChangeEnd: (value) {
              audioHandler.seek(Duration(seconds: value.toInt()));
              setState(() {
                _isDragging = false;
              });
            },
            max: maxDuration,
            semanticFormatterCallback: (value) => formatDuration(value.toInt()),
          ),
        ),
        _buildPositionRow(context, safeDuration),
      ],
    );
  }

  Widget _buildPositionRow(BuildContext context, Duration duration) {
    final colorScheme = Theme.of(context).colorScheme;
    final positionText = formatDuration(
      _isDragging ? _dragValue.toInt() : _positionData.position.inSeconds,
    );
    final durationText = formatDuration(duration.inSeconds);
    final fontSize = widget.largeControls ? 14.0 : 12.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            positionText,
            style: TextStyle(
              fontSize: fontSize,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            durationText,
            style: TextStyle(
              fontSize: fontSize,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
