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

import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wiyamusic/main.dart' show logger;

/// Shows an ongoing system notification with download progress.
///
/// Playlist downloads use a stable notification id derived from the playlist
/// id so progress updates replace the previous notification instead of
/// stacking. Single-song downloads use a separate id space.
///
/// [WakelockPlus] is enabled while any download is active so the process is
/// less likely to be suspended when the user leaves the app mid-download.
class DownloadNotificationService {
  DownloadNotificationService._();

  static final DownloadNotificationService instance =
      DownloadNotificationService._();

  static const _channelId = 'com.wiyamusic.downloads';
  static const _channelName = 'Downloads';
  static const _channelDescription =
      'Progress while downloading songs and playlists for offline listening';

  static const _playlistBaseId = 71000;
  static const _songBaseId = 72000;
  static const _completionId = 73000;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  int _activeDownloads = 0;
  final Map<String, int> _playlistNotificationIds = {};
  int _nextPlaylistSlot = 0;
  int _nextSongSlot = 0;

  Future<void> init() async {
    if (_initialized) return;

    try {
      const androidSettings = AndroidInitializationSettings('ic_notification');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        ),
      );

      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.low,
          showBadge: false,
          playSound: false,
          enableVibration: false,
        ),
      );

      _initialized = true;
    } catch (e, stackTrace) {
      logger.log(
        'Failed to init download notifications',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> ensurePermission() async {
    await init();
    try {
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: false, sound: false);
      }
    } catch (e, stackTrace) {
      logger.log(
        'Failed to request download notification permission',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _beginSession() async {
    _activeDownloads++;
    if (_activeDownloads == 1) {
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    }
  }

  Future<void> _endSession() async {
    if (_activeDownloads > 0) _activeDownloads--;
    if (_activeDownloads == 0) {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }

  int _playlistNotifId(String playlistId) {
    return _playlistNotificationIds.putIfAbsent(playlistId, () {
      final id = _playlistBaseId + (_nextPlaylistSlot % 500);
      _nextPlaylistSlot++;
      return id;
    });
  }

  int _songNotifId() {
    final id = _songBaseId + (_nextSongSlot % 500);
    _nextSongSlot++;
    return id;
  }

  Future<void> startPlaylistDownload({
    required String playlistId,
    required String playlistTitle,
    required int total,
  }) async {
    await ensurePermission();
    await _beginSession();
    await _showProgress(
      id: _playlistNotifId(playlistId),
      title: 'Downloading $playlistTitle',
      body: '0 of $total songs',
      progress: 0,
      maxProgress: total <= 0 ? 1 : total,
    );
  }

  Future<void> updatePlaylistDownload({
    required String playlistId,
    required String playlistTitle,
    required int completed,
    required int failed,
    required int total,
    String? currentSongTitle,
    double? currentSongProgress,
  }) async {
    if (!_initialized) return;

    final processed = (completed + failed).clamp(0, total);
    final maxProgress = total <= 0 ? 1 : total;
    // Combine song-level byte progress into the overall bar so the
    // notification moves smoothly within the current song slot.
    final fractional = currentSongProgress == null
        ? 0.0
        : currentSongProgress.clamp(0.0, 0.99);
    final progressUnits = total <= 0
        ? 0
        : ((processed + fractional) * 100).round().clamp(0, total * 100);
    final maxUnits = maxProgress * 100;

    final status = '$processed of $total songs';
    final body = currentSongTitle == null || currentSongTitle.isEmpty
        ? status
        : '$status · $currentSongTitle';

    await _showProgress(
      id: _playlistNotifId(playlistId),
      title: 'Downloading $playlistTitle',
      body: body,
      progress: progressUnits,
      maxProgress: maxUnits,
    );
  }

  Future<void> finishPlaylistDownload({
    required String playlistId,
    required String playlistTitle,
    required int completed,
    required int failed,
    required int total,
    required bool cancelled,
  }) async {
    final id = _playlistNotifId(playlistId);
    await _plugin.cancel(id: id);
    _playlistNotificationIds.remove(playlistId);
    await _endSession();

    if (cancelled) {
      await _showCompleted(title: 'Download cancelled', body: playlistTitle);
      return;
    }

    final body = failed > 0
        ? '$completed of $total saved · $failed failed'
        : '$completed of $total songs ready offline';
    await _showCompleted(title: 'Downloaded $playlistTitle', body: body);
  }

  Future<int> startSongDownload({required String songTitle}) async {
    await ensurePermission();
    await _beginSession();
    final id = _songNotifId();
    await _showProgress(
      id: id,
      title: 'Downloading song',
      body: songTitle,
      progress: 0,
      maxProgress: 100,
    );
    return id;
  }

  Future<void> updateSongDownload({
    required int notificationId,
    required String songTitle,
    required double progress,
  }) async {
    if (!_initialized) return;
    final pct = (progress.clamp(0.0, 1.0) * 100).round();
    await _showProgress(
      id: notificationId,
      title: 'Downloading song',
      body: '$songTitle · $pct%',
      progress: pct,
      maxProgress: 100,
    );
  }

  Future<void> finishSongDownload({
    required int notificationId,
    required String songTitle,
    required bool success,
    bool cancelled = false,
  }) async {
    await _plugin.cancel(id: notificationId);
    await _endSession();

    if (cancelled) return;

    await _showCompleted(
      title: success ? 'Download complete' : 'Download failed',
      body: songTitle,
    );
  }

  Future<void> _showProgress({
    required int id,
    required String title,
    required String body,
    required int progress,
    required int maxProgress,
  }) async {
    if (!_initialized) return;

    try {
      final android = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        showProgress: true,
        maxProgress: maxProgress <= 0 ? 1 : maxProgress,
        progress: progress.clamp(0, maxProgress <= 0 ? 1 : maxProgress),
        indeterminate: false,
        category: AndroidNotificationCategory.progress,
        icon: 'ic_notification',
        playSound: false,
        enableVibration: false,
      );

      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: android,
          iOS: const DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: false,
            presentSound: false,
          ),
        ),
      );
    } catch (e, stackTrace) {
      logger.log(
        'Failed to show download progress notification',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _showCompleted({
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;

    try {
      const android = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        ongoing: false,
        autoCancel: true,
        onlyAlertOnce: true,
        icon: 'ic_notification',
        category: AndroidNotificationCategory.status,
      );

      await _plugin.show(
        id: _completionId,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: android,
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: false,
          ),
        ),
      );
    } catch (e, stackTrace) {
      logger.log(
        'Failed to show download completion notification',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}

final downloadNotificationService = DownloadNotificationService.instance;
