// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/services/common_services.dart';
import 'package:wiyamusic/services/data_manager.dart';
import 'package:wiyamusic/services/download_notification_service.dart';
import 'package:wiyamusic/services/io_service.dart';
import 'package:wiyamusic/services/offline_download_coordinator.dart';
import 'package:wiyamusic/services/playlists_manager.dart';
import 'package:wiyamusic/utilities/flutter_toast.dart';

class OfflinePlaylistService {
  factory OfflinePlaylistService() => _instance;
  OfflinePlaylistService._internal();
  static final OfflinePlaylistService _instance =
      OfflinePlaylistService._internal();

  // Playlist download state notifiers
  final Map<String, ValueNotifier<DownloadProgress>> downloadProgressNotifiers =
      {};
  final List<String> activeDownloads = [];

  // List of playlists that are fully available offline
  final offlinePlaylists = ValueNotifier<List<dynamic>>(
    Hive.box('userNoBackup').get('offlinePlaylists', defaultValue: []),
  );

  ValueNotifier<DownloadProgress> getProgressNotifier(String playlistId) {
    if (!downloadProgressNotifiers.containsKey(playlistId)) {
      downloadProgressNotifiers[playlistId] = ValueNotifier<DownloadProgress>(
        DownloadProgress(total: 0),
      );
    }
    return downloadProgressNotifiers[playlistId]!;
  }

  bool isPlaylistDownloaded(String playlistId) {
    return offlinePlaylists.value.any(
      (playlist) => playlist['ytid'] == playlistId,
    );
  }

  bool isPlaylistDownloading(String playlistId) {
    return activeDownloads.contains(playlistId);
  }

  /// Checks whether [playlist] now has 100% of its songs downloaded offline
  /// and, if so, marks it offline too.
  ///
  /// Unlike the batch scan in [_handleDownloadCompletion] (which only runs
  /// right after a playlist finishes downloading), this is meant to be
  /// called any time a single playlist's song list or like-status changes —
  /// e.g. after adding a song to a custom playlist, or liking a playlist —
  /// so playlists created/modified *after* the triggering download aren't
  /// silently skipped.
  void checkAndAutoMarkOffline(Map playlist) {
    final id = playlist['ytid']?.toString();
    final pList = playlist['list'] as List?;
    if (id == null || pList == null || pList.isEmpty) return;
    if (isPlaylistDownloaded(id)) return;

    final offlineSongIds = userOfflineSongs.value
        .map((s) => s['ytid'])
        .toSet();
    if (!pList.every((s) => offlineSongIds.contains(s['ytid']))) return;

    offlinePlaylists.value = [
      ...offlinePlaylists.value,
      {
        ...playlist,
        'list': pList,
        'downloadedAt': DateTime.now().millisecondsSinceEpoch,
      },
    ];
    unawaited(
      addOrUpdateData<List>(
        'userNoBackup',
        'offlinePlaylists',
        offlinePlaylists.value,
      ),
    );
  }

  Future<void> downloadPlaylist(BuildContext context, Map playlist) async {
    final playlistId = playlist['ytid'] as String? ?? playlist['title'];

    if (playlistId == null || playlistId.isEmpty) {
      showToast(context, context.l10n!.error);
      return;
    }

    // Check if already downloading
    if (isPlaylistDownloading(playlistId)) {
      showToast(context, context.l10n!.alreadyDownloading);
      return;
    }

    // Initialize download state
    final songsList = playlist['list'] as List<dynamic>? ?? [];
    if (songsList.isEmpty) {
      showToast(context, context.l10n!.playlistEmpty);
      return;
    }

    // Set up progress tracking (dedupe by ytid so the same song is never
    // downloaded twice in one playlist run).
    final seenYtids = <String>{};
    final uniqueSongs = <dynamic>[];
    for (final song in songsList) {
      final id = song is Map ? song['ytid']?.toString() : null;
      if (id == null || id.isEmpty) {
        uniqueSongs.add(song);
        continue;
      }
      if (!seenYtids.add(id)) continue;
      uniqueSongs.add(song);
    }

    final progressNotifier = getProgressNotifier(playlistId)
      ..value = DownloadProgress(total: uniqueSongs.length);
    activeDownloads.add(playlistId);

    final playlistTitle =
        playlist['title']?.toString().trim().isNotEmpty == true
        ? playlist['title'].toString().trim()
        : 'Playlist';

    try {
      // Only one playlist pipeline (and its progress notification) runs at a
      // time; queued playlists wait without showing a premature "0 of N".
      await offlineDownloadCoordinator.withPlaylistSlot(() async {
        await downloadNotificationService.startPlaylistDownload(
          playlistId: playlistId,
          playlistTitle: playlistTitle,
          total: uniqueSongs.length,
        );

        final songQueue = Queue<dynamic>.from(uniqueSongs);
        await _processDownloadQueue(
          songQueue,
          progressNotifier,
          playlistId: playlistId,
          playlistTitle: playlistTitle,
        ).timeout(
          Duration(minutes: uniqueSongs.length * 2),
          onTimeout: () {
            logger.log('Download timeout for playlist $playlistId');
            progressNotifier.value.isCancelled = true;
            progressNotifier.notifyListeners();
          },
        );
      });

      // Handle completion
      await _handleDownloadCompletion(
        context,
        playlistId,
        playlist,
        progressNotifier,
      );
    } catch (e, stackTrace) {
      logger.log(
        'Error during playlist download',
        error: e,
        stackTrace: stackTrace,
      );
      activeDownloads.remove(playlistId);
      final completed = progressNotifier.value.completed;
      final failed = progressNotifier.value.failed;
      final total = progressNotifier.value.total;
      unawaited(
        downloadNotificationService.finishPlaylistDownload(
          playlistId: playlistId,
          playlistTitle: playlistTitle,
          completed: completed,
          failed: failed,
          total: total,
          cancelled: true,
        ),
      );
      cleanupProgressNotifier(playlistId);
      if (context.mounted) {
        showToast(context, '${context.l10n!.error}: $e');
      }
    }
  }

  Future<void> _handleDownloadCompletion(
    BuildContext context,
    String playlistId,
    Map playlist,
    ValueNotifier<DownloadProgress> progressNotifier,
  ) async {
    try {
      // Remove from active downloads
      activeDownloads.remove(playlistId);

      final songsList = playlist['list'] as List<dynamic>;

      // Only add to offline playlists if not cancelled and most songs succeeded
      if (!progressNotifier.value.isCancelled &&
          progressNotifier.value.completed > progressNotifier.value.failed) {
        // Create an offline version of the playlist
        final offlinePlaylist = {
          ...playlist,
          'ytid': playlistId,
          'title': playlist['title'],
          'image': playlist['image'],
          'source': playlist['source'],
          'list': songsList,
          'downloadedAt': DateTime.now().millisecondsSinceEpoch,
        };

        // Add to offline playlists
        final updatedPlaylists = List<dynamic>.from(offlinePlaylists.value);

        final existingIndex = updatedPlaylists.indexWhere(
          (p) => p['ytid'] == playlistId,
        );

        if (existingIndex != -1) {
          updatedPlaylists[existingIndex] = offlinePlaylist;
        } else {
          updatedPlaylists.add(offlinePlaylist);
        }

        // Also mark albums/playlists whose songs are now fully offline
        final offlineSongIds = userOfflineSongs.value
            .map((s) => s['ytid'])
            .toSet();

        final seenIds = <String>{};
        final userPlaylistSources = <Map>[
          ...userCustomPlaylists.value,
          ...userLikedPlaylists.value,
          for (final folder in userPlaylistFolders.value)
            ...List<Map>.from(folder['playlists'] ?? []),
          ...playlists,
        ].where((p) {
          final id = p['ytid']?.toString();
          return id != null && seenIds.add(id);
        }).toList();
        for (final p in userPlaylistSources) {
          final pList = p['list'] as List?;
          if (pList == null ||
              pList.isEmpty ||
              p['ytid'] == playlistId ||
              isPlaylistDownloaded(
                p['ytid']?.toString() ?? '',
              )) {
            continue;
          }
          if (pList.every((s) => offlineSongIds.contains(s['ytid']))) {
            updatedPlaylists.add({
              ...p,
              'list': pList,
              'downloadedAt': DateTime.now().millisecondsSinceEpoch,
            });
          }
        }

        offlinePlaylists.value = updatedPlaylists;
        unawaited(
          addOrUpdateData<List>(
            'userNoBackup',
            'offlinePlaylists',
            offlinePlaylists.value,
          ),
        );

        if (context.mounted) {
          showToast(
            context,
            '${context.l10n!.playlistDownloaded}: ${progressNotifier.value.completed}/${songsList.length}',
          );
        }
      } else if (!progressNotifier.value.isCancelled) {
        // Cancelled toast is shown by cancelDownload, only show failure toast here.
        if (context.mounted) {
          showToast(
            context,
            '${context.l10n!.downloadFailed}: ${progressNotifier.value.failed}/${songsList.length}',
          );
        }
      }

      // Capture queue counters before cleanup resets them to 0/0 — otherwise
      // the completion notification incorrectly shows "0 of 0 songs".
      final completed = progressNotifier.value.completed;
      final failed = progressNotifier.value.failed;
      final total = progressNotifier.value.total;
      final cancelled = progressNotifier.value.isCancelled;

      final playlistTitle =
          playlist['title']?.toString().trim().isNotEmpty == true
          ? playlist['title'].toString().trim()
          : 'Playlist';

      // Replace the progress notification before wiping local progress state.
      await downloadNotificationService.finishPlaylistDownload(
        playlistId: playlistId,
        playlistTitle: playlistTitle,
        completed: completed,
        failed: failed,
        total: total,
        cancelled: cancelled,
      );

      cleanupProgressNotifier(playlistId);
    } catch (e, stackTrace) {
      logger.log(
        'Error handling download completion',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> cancelDownload(BuildContext context, String playlistId) async {
    if (!isPlaylistDownloading(playlistId)) return;

    try {
      final progressNotifier = getProgressNotifier(playlistId);
      progressNotifier.value.isCancelled = true;
      progressNotifier.notifyListeners();

      // Immediate visual feedback
      showToast(context, context.l10n!.cancellingDownload);

      const maxWaitTime = Duration(seconds: 30);
      final startTime = DateTime.now();

      // Wait for the ongoing tasks to complete with timeout
      while (activeDownloads.contains(playlistId)) {
        await Future.delayed(const Duration(milliseconds: 100));

        if (DateTime.now().difference(startTime) > maxWaitTime) {
          logger.log('Timeout waiting for download cancellation');
          activeDownloads.remove(playlistId);
          cleanupProgressNotifier(playlistId);
          break;
        }
      }

      showToast(context, context.l10n!.downloadCancelled);
    } catch (e, stackTrace) {
      logger.log('Error cancelling download', error: e, stackTrace: stackTrace);
      // Force remove from active downloads and cleanup on error
      activeDownloads.remove(playlistId);
      cleanupProgressNotifier(playlistId);
    }
  }

  Future<void> removeOfflinePlaylist(String playlistId) async {
    try {
      final normalizedPlaylistId = playlistId.trim();
      if (normalizedPlaylistId.isEmpty) {
        logger.log('Invalid playlistId for removal');
        return;
      }

      // Find the playlist
      final playlistIndex = offlinePlaylists.value.indexWhere(
        (playlist) =>
            playlist is Map &&
            playlist['ytid']?.toString() == normalizedPlaylistId,
      );

      if (playlistIndex == -1) {
        logger.log('Playlist not found for removal: $normalizedPlaylistId');
        return;
      }

      final playlist = offlinePlaylists.value[playlistIndex] as Map;

      // Get songs that are only in this playlist
      final songsInPlaylist = playlist['list'] as List<dynamic>? ?? [];
      for (final song in songsInPlaylist) {
        try {
          final songId = song['ytid'] as String?;

          if (songId == null || songId.isEmpty) {
            continue;
          }

          // Check if this song is used in other offline playlists
          final isUsedInOtherPlaylists = offlinePlaylists.value
              .where(
                (p) =>
                    p is Map && p['ytid']?.toString() != normalizedPlaylistId,
              ) // Exclude current playlist
              .any((p) {
                final playlistSongs = p['list'] as List<dynamic>? ?? [];
                return playlistSongs.any((s) => s['ytid'] == songId);
              });

          // Also check if song is in user's liked songs or OTHER custom playlists
          final isInLikedSongs = userLikedSongsList.value.any(
            (s) => s['ytid'] == songId,
          );
          final isInOtherCustomPlaylists = getUserCustomPlaylists()
              .where((p) => p['ytid']?.toString() != normalizedPlaylistId)
              .any((p) {
                final customPlaylistSongs = p['list'] as List<dynamic>? ?? [];
                return customPlaylistSongs.any((s) => s['ytid'] == songId);
              });

          // Only remove if not used elsewhere
          if (!isUsedInOtherPlaylists &&
              !isInLikedSongs &&
              !isInOtherCustomPlaylists) {
            await removeSongFromOffline(songId);
          }
        } catch (e, stackTrace) {
          logger.log(
            'Error removing song from offline',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }

      // Remove playlist from offline playlists
      final updatedPlaylists = List<dynamic>.from(offlinePlaylists.value)
        ..removeWhere(
          (p) => p is Map && p['ytid']?.toString() == normalizedPlaylistId,
        );
      offlinePlaylists.value = updatedPlaylists;
      unawaited(
        addOrUpdateData<List>(
          'userNoBackup',
          'offlinePlaylists',
          offlinePlaylists.value,
        ),
      );
    } catch (e, stackTrace) {
      logger.log(
        'Error removing offline playlist',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> deleteAllDownloads() async {
    // Cancel all active downloads first and wait for them to stop
    final activeIds = List<String>.from(activeDownloads);
    for (final id in activeIds) {
      final notifier = downloadProgressNotifiers[id];
      if (notifier != null) {
        notifier.value.isCancelled = true;
        notifier.notifyListeners();
      }
    }

    const maxWaitTime = Duration(seconds: 30);
    final startTime = DateTime.now();
    while (activeDownloads.isNotEmpty) {
      if (DateTime.now().difference(startTime) > maxWaitTime) {
        logger.log('Timeout waiting for downloads to cancel before delete');
        activeDownloads.clear();
        break;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    try {
      final tracksDir = Directory('$applicationDirPath/${FilePaths.tracksDir}');
      final artworksDir = Directory(
        '$applicationDirPath/${FilePaths.artworksDir}',
      );

      if (await tracksDir.exists()) {
        await tracksDir.delete(recursive: true);
      }
      if (await artworksDir.exists()) {
        await artworksDir.delete(recursive: true);
      }

      await FilePaths.ensureDirectoriesExist();

      userOfflineSongs.value = [];

      offlinePlaylists.value = [];

      for (final notifier in downloadProgressNotifiers.values) {
        notifier.dispose();
      }
      downloadProgressNotifiers.clear();
      activeDownloads.clear();

      unawaited(addOrUpdateData<List>('userNoBackup', 'offlineSongs', []));
      unawaited(addOrUpdateData<List>('userNoBackup', 'offlinePlaylists', []));

      logger.log('All downloads deleted successfully');
    } catch (e, stackTrace) {
      logger.log(
        'Error deleting all downloads',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  void cleanupProgressNotifier(String playlistId) {
    try {
      if (downloadProgressNotifiers.containsKey(playlistId)) {
        final notifier = downloadProgressNotifiers[playlistId];
        notifier?.value = DownloadProgress(total: 0);
      }
    } catch (e, stackTrace) {
      logger.log(
        'Error cleaning up progress notifier',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _processDownloadQueue(
    Queue<dynamic> songQueue,
    ValueNotifier<DownloadProgress> progressNotifier, {
    required String playlistId,
    required String playlistTitle,
  }) async {
    DateTime? lastUiProgressAt;
    var lastUiSongProgress = -1.0;
    final uiInterval = Platform.isIOS
        ? const Duration(milliseconds: 1500)
        : const Duration(milliseconds: 800);
    final uiStep = Platform.isIOS ? 0.08 : 0.05;

    while (songQueue.isNotEmpty && !progressNotifier.value.isCancelled) {
      await offlineDownloadCoordinator.waitWhilePaused();
      if (progressNotifier.value.isCancelled) break;

      final song = songQueue.removeFirst();

      try {
        if (song == null ||
            song['ytid'] == null ||
            song['ytid'].toString().isEmpty) {
          logger.log('Invalid song data in playlist download');
          progressNotifier.value.failed++;
          progressNotifier.notifyListeners();
          _notifyPlaylistProgress(
            playlistId: playlistId,
            playlistTitle: playlistTitle,
            progress: progressNotifier.value,
          );
          continue;
        }

        final songTitle = song['title']?.toString() ?? 'Song';

        // Skip if already offline
        if (isSongAlreadyOffline(song['ytid'])) {
          // Find the existing offline song to get the correct audioPath
          final offlineSong = getOfflineSongByYtid(song['ytid']);
          if (offlineSong.isNotEmpty) {
            // Update the song in the playlist with the correct offline properties
            song['audioPath'] = offlineSong['audioPath'];
            song['artworkPath'] = offlineSong['artworkPath'];
          }
          // Update progress
          progressNotifier.value.completed++;
          progressNotifier.notifyListeners();
          _notifyPlaylistProgress(
            playlistId: playlistId,
            playlistTitle: playlistTitle,
            progress: progressNotifier.value,
            currentSongTitle: songTitle,
            currentSongProgress: 1,
          );
        } else {
          try {
            lastUiSongProgress = -1;
            final success = await makeSongOffline(
              song,
              cancelExisting: false,
              showNotification: false,
              onProgress: (songProgress) {
                final now = DateTime.now();
                final jumped =
                    lastUiSongProgress < 0 ||
                    (songProgress - lastUiSongProgress).abs() >= uiStep;
                final timedOut =
                    lastUiProgressAt == null ||
                    now.difference(lastUiProgressAt!) >= uiInterval;
                if (!jumped && !timedOut && songProgress < 0.999) return;
                lastUiProgressAt = now;
                lastUiSongProgress = songProgress;
                _notifyPlaylistProgress(
                  playlistId: playlistId,
                  playlistTitle: playlistTitle,
                  progress: progressNotifier.value,
                  currentSongTitle: songTitle,
                  currentSongProgress: songProgress,
                );
              },
            );
            if (success) {
              progressNotifier.value.completed++;
            } else {
              progressNotifier.value.failed++;
            }
          } on SongOfflineRateLimited {
            progressNotifier.value.failed++;
            // Single backoff — no tight auto-retry loop.
            await Future<void>.delayed(
              offlineDownloadCoordinator.rateLimitBackoff,
            );
          }
          progressNotifier.notifyListeners();
          _notifyPlaylistProgress(
            playlistId: playlistId,
            playlistTitle: playlistTitle,
            progress: progressNotifier.value,
          );
          // Brief pause between songs to reduce CPU heat / rate limiting.
          await Future<void>.delayed(
            offlineDownloadCoordinator.interSongDelay,
          );
        }
      } catch (e, stackTrace) {
        logger.log(
          'Failed to download song: ${song?['title']}',
          error: e,
          stackTrace: stackTrace,
        );
        progressNotifier.value.failed++;
        progressNotifier.notifyListeners();
        _notifyPlaylistProgress(
          playlistId: playlistId,
          playlistTitle: playlistTitle,
          progress: progressNotifier.value,
        );
      }
    }
  }

  void _notifyPlaylistProgress({
    required String playlistId,
    required String playlistTitle,
    required DownloadProgress progress,
    String? currentSongTitle,
    double? currentSongProgress,
  }) {
    unawaited(
      downloadNotificationService.updatePlaylistDownload(
        playlistId: playlistId,
        playlistTitle: playlistTitle,
        completed: progress.completed,
        failed: progress.failed,
        total: progress.total,
        currentSongTitle: currentSongTitle,
        currentSongProgress: currentSongProgress,
      ),
    );
  }
}

class DownloadProgress {
  DownloadProgress({
    required this.total,
    this.completed = 0,
    this.failed = 0,
    this.isCancelled = false,
  });

  final int total;
  int completed;
  int failed;
  bool isCancelled;

  double get progress {
    if (total <= 0) return 0;
    final totalProcessed = completed + failed;
    return totalProcessed > total ? 1.0 : totalProcessed / total;
  }

  @override
  String toString() {
    final percentage = (progress * 100).toStringAsFixed(1);
    return '$percentage% ($completed/$total)';
  }
}

// Global instance for easy access
final offlinePlaylistService = OfflinePlaylistService();
