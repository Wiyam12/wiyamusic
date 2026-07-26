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
import 'package:flutter/material.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/models/position_data.dart';
import 'package:wiyamusic/utilities/formatter.dart';
import 'package:wiyamusic/utilities/mediaitem.dart';

class PositionSlider extends StatefulWidget {
  const PositionSlider({super.key});

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

  void _onMediaItem(MediaItem? media) {
    final mediaId = media?.id;
    if (mediaId == null || mediaId == _boundMediaId) return;

    _boundMediaId = mediaId;
    _holdAtStart = true;
    _positionData = PositionData(
      Duration.zero,
      Duration.zero,
      media?.duration ?? Duration.zero,
    );
  }

  void _applyPositionData(PositionData data) {
    if (_holdAtStart) {
      // The player often keeps emitting the old track's end position until the
      // new source is ready. Only release once we see a fresh near-zero tick.
      if (data.position.inMilliseconds < 1500) {
        _holdAtStart = false;
        _positionData = data;
      }
      return;
    }

    _positionData = data;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      builder: (context, mediaSnapshot) {
        _onMediaItem(mediaSnapshot.data);

        return StreamBuilder<PositionData>(
          stream: audioHandler.positionDataStream,
          builder: (context, snapshot) {
            if (snapshot.data != null) {
              _applyPositionData(snapshot.data!);
            }

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
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
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
                    semanticFormatterCallback: (value) =>
                        formatDuration(value.toInt()),
                  ),
                ),
                _buildPositionRow(context, safeDuration),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPositionRow(BuildContext context, Duration duration) {
    final colorScheme = Theme.of(context).colorScheme;
    final positionText = formatDuration(
      _isDragging ? _dragValue.toInt() : _positionData.position.inSeconds,
    );
    final durationText = formatDuration(duration.inSeconds);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            positionText,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            durationText,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
