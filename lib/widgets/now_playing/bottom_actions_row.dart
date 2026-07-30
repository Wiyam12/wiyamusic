import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/services/common_services.dart';
import 'package:wiyamusic/services/data_manager.dart';
import 'package:wiyamusic/services/router_service.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/utilities/flutter_bottom_sheet.dart';
import 'package:wiyamusic/utilities/flutter_toast.dart';
import 'package:wiyamusic/utilities/mediaitem.dart';
import 'package:wiyamusic/utilities/playlist_dialogs.dart';
import 'package:wiyamusic/widgets/now_playing/now_playing_artwork.dart';
import 'package:wiyamusic/widgets/now_playing/song_share_card.dart';
import 'package:wiyamusic/widgets/popup_menu_item.dart';
import 'package:wiyamusic/widgets/queue_list_view.dart';

class BottomActionsRow extends StatelessWidget {
  const BottomActionsRow({
    super.key,
    required this.metadata,
    required this.iconSize,
    required this.isLargeScreen,
    required this.lyricsController,
  });
  final MediaItem metadata;
  final double iconSize;
  final bool isLargeScreen;
  final NowPlayingLyricsController lyricsController;

  bool get isRadioStation => metadata.extras?['isLive'] == true;

  void _toggleLargeScreenQueue() {
    final next = !nowPlayingQueueVisible.value;
    nowPlayingQueueVisible.value = next;
    unawaited(
      addOrUpdateData<bool>('settings', 'nowPlayingQueueVisible', next),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n!;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final size = screenWidth < 360 ? iconSize * 0.95 : iconSize;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 8,
        vertical: isLargeScreen ? 8 : 4,
      ),
      child: Align(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isLargeScreen ? 420 : double.infinity,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (!isRadioStation)
                IconButton(
                  icon: Icon(
                    FluentIcons.text_quote_24_regular,
                    color: colorScheme.onSurface,
                  ),
                  iconSize: size,
                  tooltip: l10n.lyrics,
                  onPressed: lyricsController.toggle,
                )
              else
                IconButton(
                  icon: Icon(
                    FluentIcons.timer_24_regular,
                    color: colorScheme.onSurface,
                  ),
                  iconSize: size,
                  tooltip: l10n.sleepTimer,
                  onPressed: () => _showSleepTimerDialog(context),
                ),
              IconButton(
                icon: Icon(
                  FluentIcons.options_24_regular,
                  color: colorScheme.onSurface,
                ),
                iconSize: size,
                tooltip: l10n.equalizer,
                onPressed: () {
                  // Minimize now playing first, then open equalizer on the shell.
                  Navigator.of(context).pop();
                  NavigationManager.router.push('/settings/equalizer');
                },
              ),
              if (!isRadioStation)
                ValueListenableBuilder<bool>(
                  valueListenable: nowPlayingQueueVisible,
                  builder: (context, queueVisible, _) {
                    final isActive = isLargeScreen && queueVisible;
                    return IconButton(
                      icon: Icon(
                        FluentIcons.apps_list_detail_24_regular,
                        color: isActive
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                      iconSize: size,
                      tooltip: l10n.queue,
                      onPressed: () {
                        if (isLargeScreen) {
                          _toggleLargeScreenQueue();
                        } else {
                          showCustomBottomSheet(
                            context,
                            const QueueWidget(isBottomSheet: true),
                          );
                        }
                      },
                    );
                  },
                )
              else
                const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }
}

List<PopupMenuEntry<String>> buildNowPlayingMoreMenuItems({
  required BuildContext context,
  required MediaItem metadata,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final l10n = context.l10n!;
  final isRadioStation = metadata.extras?['isLive'] == true;
  final audioId = _audioIdFor(metadata);
  final isOffline = isSongAlreadyOffline(audioId);
  final isDownloading =
      audioId != null && audioId.isNotEmpty && isSongDownloading(audioId);

  return [
    buildPopupMenuItem<String>(
      value: 'share',
      icon: FluentIcons.share_24_regular,
      label: l10n.share,
      colorScheme: colorScheme,
    ),
    if (!isRadioStation)
      buildPopupMenuItem<String>(
        value: 'offline',
        icon: isOffline
            ? FluentIcons.cloud_off_24_regular
            : isDownloading
            ? FluentIcons.arrow_download_24_regular
            : FluentIcons.cloud_arrow_down_24_regular,
        label: isOffline
            ? l10n.removeOffline
            : isDownloading
            ? l10n.alreadyDownloading
            : l10n.makeOffline,
        colorScheme: colorScheme,
      ),
    buildPopupMenuItem<String>(
      value: 'sleep_timer',
      icon: FluentIcons.timer_24_regular,
      label: l10n.sleepTimer,
      colorScheme: colorScheme,
    ),
    if (!offlineMode.value && !isRadioStation)
      buildPopupMenuItem<String>(
        value: 'add_to_playlist',
        icon: FluentIcons.album_add_24_regular,
        label: l10n.addToPlaylist,
        colorScheme: colorScheme,
      ),
    if (!isRadioStation)
      buildPopupMenuItem<String>(
        value: 'lyrics',
        icon: FluentIcons.text_quote_24_regular,
        label: l10n.lyrics,
        colorScheme: colorScheme,
      ),
  ];
}

Future<void> handleNowPlayingMoreAction({
  required BuildContext context,
  required String value,
  required MediaItem metadata,
  required NowPlayingLyricsController lyricsController,
}) async {
  switch (value) {
    case 'share':
      await showSongSharePhotocard(context, metadata);
      break;
    case 'offline':
      await _toggleOffline(context, _audioIdFor(metadata), metadata);
      break;
    case 'sleep_timer':
      final active = sleepTimerNotifier.value != null;
      if (active) {
        audioHandler.cancelSleepTimer();
        sleepTimerNotifier.value = null;
        showToast(
          context,
          context.l10n!.sleepTimerCancelled,
          duration: const Duration(seconds: 1, milliseconds: 500),
        );
      } else {
        _showSleepTimerDialog(context);
      }
      break;
    case 'add_to_playlist':
      showAddToPlaylistDialog(context, song: mediaItemToMap(metadata));
      break;
    case 'lyrics':
      lyricsController.toggle();
      break;
  }
}

String? _audioIdFor(MediaItem metadata) {
  if (metadata.extras?['isLive'] == true) return metadata.id;
  final ytid = metadata.extras?['ytid']?.toString().trim();
  if (ytid != null && ytid.isNotEmpty) return ytid;
  return metadata.id;
}

Future<void> _toggleOffline(
  BuildContext context,
  String? audioId,
  MediaItem metadata,
) async {
  final originalValue = isSongAlreadyOffline(audioId);

  if (!originalValue &&
      audioId != null &&
      audioId.isNotEmpty &&
      isSongDownloading(audioId)) {
    if (context.mounted) {
      showToast(context, context.l10n!.alreadyDownloading);
    }
    return;
  }

  try {
    final bool success;
    if (originalValue) {
      success = await removeSongFromOffline(audioId);
    } else {
      final songMap = mediaItemToMap(metadata);
      // Prefer live player duration when MediaItem duration is missing.
      final playerDuration = audioHandler.audioPlayer.duration;
      if (songMap['duration'] == null &&
          playerDuration != null &&
          playerDuration > Duration.zero) {
        songMap['duration'] = playerDuration.inSeconds;
      }
      success = await makeSongOffline(songMap, cancelExisting: false);
    }
    if (!success) {
      logger.log('Offline toggle failed for $audioId');
    }
  } on SongOfflineRateLimited {
    logger.log('Offline download rate limited for $audioId');
  } catch (e) {
    logger.log('Error toggling offline status', error: e);
  }
}

void _showSleepTimerDialog(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;

  showDialog(
    context: context,
    builder: (context) {
      final duration = sleepTimerNotifier.value ?? Duration.zero;
      var hours = duration.inMinutes ~/ 60;
      var minutes = duration.inMinutes % 60;

      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(FluentIcons.timer_24_regular, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  context.l10n!.sleepTimer,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n!.selectDuration,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                _buildTimeSelector(
                  context: context,
                  label: context.l10n!.hours,
                  value: hours,
                  colorScheme: colorScheme,
                  onDecrement: () {
                    if (hours > 0) setState(() => hours--);
                  },
                  onIncrement: () => setState(() => hours++),
                ),
                const SizedBox(height: 16),
                _buildTimeSelector(
                  context: context,
                  label: context.l10n!.minutes,
                  value: minutes,
                  colorScheme: colorScheme,
                  onDecrement: () {
                    if (minutes > 0) setState(() => minutes--);
                  },
                  onIncrement: () {
                    if (minutes < 59) setState(() => minutes++);
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    ...[15, 30, 45, 60].map((mins) {
                      return ActionChip(
                        label: Text('$mins min'),
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        labelStyle: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onPressed: () {
                          setState(() {
                            hours = mins ~/ 60;
                            minutes = mins % 60;
                          });
                        },
                      );
                    }),
                    ActionChip(
                      label: Text(context.l10n!.endOfSong),
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      labelStyle: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onPressed: () {
                        audioHandler.setSleepTimerEndOfSong();
                        showToast(
                          context,
                          context.l10n!.sleepTimerSet,
                          duration: const Duration(
                            seconds: 1,
                            milliseconds: 500,
                          ),
                        );
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.onSurfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(context.l10n!.cancel),
              ),
              FilledButton(
                onPressed: () {
                  final duration = Duration(hours: hours, minutes: minutes);
                  if (duration.inSeconds > 0) {
                    audioHandler.setSleepTimer(duration);
                    showToast(
                      context,
                      context.l10n!.sleepTimerSet,
                      duration: const Duration(seconds: 1, milliseconds: 500),
                    );
                  }
                  Navigator.pop(context);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(context.l10n!.setTimer),
              ),
            ],
          );
        },
      );
    },
  );
}

Widget _buildTimeSelector({
  required BuildContext context,
  required String label,
  required int value,
  required ColorScheme colorScheme,
  required VoidCallback onDecrement,
  required VoidCallback onIncrement,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w500,
            fontSize: 16,
          ),
        ),
        Row(
          children: [
            IconButton(
              icon: Icon(
                FluentIcons.line_horizontal_1_24_regular,
                color: colorScheme.onSurfaceVariant,
              ),
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: onDecrement,
            ),
            Container(
              width: 48,
              alignment: Alignment.center,
              child: Text(
                '$value',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                FluentIcons.add_24_regular,
                color: colorScheme.onSurfaceVariant,
              ),
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: onIncrement,
            ),
          ],
        ),
      ],
    ),
  );
}
