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
/// On Android, [WakelockPlus] is enabled while downloads are active. On iOS,
/// wakelock is intentionally **not** used — holding the CPU awake during
/// background downloads was a major cause of thermal lag and device restarts.
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

  /// iOS: update at most every 2.5s. Android: every 800ms.
  static Duration get _minUpdateInterval => Platform.isIOS
      ? const Duration(milliseconds: 2500)
      : const Duration(milliseconds: 800);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  int _activeDownloads = 0;
  final Map<String, int> _playlistNotificationIds = {};
  final Set<String> _activePlaylistIds = {};
  final Set<int> _suppressedProgressIds = {};
  int _nextPlaylistSlot = 0;
  int _nextSongSlot = 0;

  DateTime? _lastProgressShownAt;
  int? _lastProgressShownId;
  int? _lastProgressShownValue;
  bool _showInFlight = false;
  _PendingProgressShow? _coalescedShow;

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
    // Wakelock only on Android. On iOS it keeps the SoC awake through long
    // download sessions and has been linked to thermal throttling / restarts.
    if (_activeDownloads == 1 && Platform.isAndroid) {
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    }
  }

  Future<void> _endSession() async {
    if (_activeDownloads > 0) _activeDownloads--;
    if (_activeDownloads == 0 && Platform.isAndroid) {
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

  void _dropCoalescedFor(int id) {
    if (_coalescedShow?.id == id) {
      _coalescedShow = null;
    }
    if (_lastProgressShownId == id) {
      _lastProgressShownId = null;
      _lastProgressShownValue = null;
      _lastProgressShownAt = null;
    }
  }

  Future<void> startPlaylistDownload({
    required String playlistId,
    required String playlistTitle,
    required int total,
  }) async {
    // Never show a progress notification for an empty queue ("0 of 0").
    if (total <= 0) return;

    await ensurePermission();
    final id = _playlistNotifId(playlistId);
    _suppressedProgressIds.remove(id);
    _activePlaylistIds.add(playlistId);
    await _beginSession();
    await _showProgress(
      id: id,
      title: 'Downloading $playlistTitle',
      body: 'Downloading 0 of $total songs...',
      progress: 0,
      maxProgress: total,
      force: true,
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
    // Ignore updates after finish / for empty queues — prevents stale
    // "0 of 0 songs" progress notifications from resurfacing.
    if (total <= 0 || !_activePlaylistIds.contains(playlistId)) return;

    final id = _playlistNotifId(playlistId);
    if (_suppressedProgressIds.contains(id)) return;

    final processed = (completed + failed).clamp(0, total);

    // On iOS, avoid byte-level fractional updates — they hammer the
    // notification center. Only bump when a whole song finishes, or when
    // forced via a coarse song-boundary call (currentSongProgress == null/1).
    if (Platform.isIOS &&
        currentSongProgress != null &&
        currentSongProgress < 0.999) {
      return;
    }

    final fractional = (!Platform.isIOS && currentSongProgress != null)
        ? currentSongProgress.clamp(0.0, 0.99)
        : 0.0;
    final progressUnits = ((processed + fractional) * 100).round().clamp(
      0,
      total * 100,
    );
    final maxUnits = total * 100;

    final status = processed >= total
        ? 'Downloaded $processed of $total songs'
        : 'Downloading $processed of $total songs...';
    final body = currentSongTitle == null || currentSongTitle.isEmpty
        ? status
        : '$status · $currentSongTitle';

    await _showProgress(
      id: id,
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
    final hadSession = _activePlaylistIds.remove(playlistId);
    final id = _playlistNotificationIds.remove(playlistId);

    // Stop any in-flight / coalesced progress updates from recreating the
    // ongoing notification after we cancel it.
    if (id != null) {
      _suppressedProgressIds.add(id);
      _dropCoalescedFor(id);
      try {
        await _plugin.cancel(id: id);
      } catch (_) {}
    }

    if (hadSession) {
      await _endSession();
    }

    // No progress notification was ever shown (empty / never started).
    if (id == null && !hadSession) {
      if (!cancelled && (completed > 0 || failed > 0)) {
        await _showCompleted(title: 'Download complete', body: playlistTitle);
      }
      return;
    }

    if (cancelled) {
      await _showCompleted(title: 'Download cancelled', body: playlistTitle);
      return;
    }

    // Never publish a completion body like "0 of 0 songs".
    if (total <= 0 && completed <= 0 && failed <= 0) {
      await _showCompleted(
        title: 'All downloads completed successfully',
        body: playlistTitle,
      );
      return;
    }

    final String title;
    final String body;
    if (failed > 0) {
      title = 'Downloaded $playlistTitle';
      body = '$completed of $total saved · $failed failed';
    } else if (completed <= 0) {
      title = 'Download complete';
      body = playlistTitle;
    } else if (total > 0 && completed >= total) {
      title = 'All downloads completed successfully';
      body = '$completed songs downloaded successfully';
    } else {
      title = 'Downloaded $playlistTitle';
      body = '$completed songs downloaded successfully';
    }

    await _showCompleted(title: title, body: body);
  }

  Future<int> startSongDownload({required String songTitle}) async {
    await ensurePermission();
    await _beginSession();
    final id = _songNotifId();
    _suppressedProgressIds.remove(id);
    await _showProgress(
      id: id,
      title: 'Downloading song',
      body: songTitle,
      progress: 0,
      maxProgress: 100,
      force: true,
    );
    return id;
  }

  Future<void> updateSongDownload({
    required int notificationId,
    required String songTitle,
    required double progress,
  }) async {
    if (!_initialized) return;
    if (_suppressedProgressIds.contains(notificationId)) return;
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
    _suppressedProgressIds.add(notificationId);
    _dropCoalescedFor(notificationId);

    try {
      await _plugin.cancel(id: notificationId);
    } catch (_) {}
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
    bool force = false,
  }) async {
    if (!_initialized) return;
    if (_suppressedProgressIds.contains(id)) return;

    // Guard against invalid empty-queue progress ("0 of 0").
    if (maxProgress <= 0) return;

    final now = DateTime.now();
    final safeMax = maxProgress;
    final safeProgress = progress.clamp(0, safeMax);

    if (!force) {
      final sameId = _lastProgressShownId == id;
      final sameValue = _lastProgressShownValue == safeProgress;
      final tooSoon =
          _lastProgressShownAt != null &&
          now.difference(_lastProgressShownAt!) < _minUpdateInterval;
      if (sameId && (sameValue || tooSoon)) {
        // Coalesce the latest payload so a burst of updates collapses to one.
        _coalescedShow = _PendingProgressShow(
          id: id,
          title: title,
          body: body,
          progress: safeProgress,
          maxProgress: safeMax,
        );
        return;
      }
    }

    if (_showInFlight) {
      _coalescedShow = _PendingProgressShow(
        id: id,
        title: title,
        body: body,
        progress: safeProgress,
        maxProgress: safeMax,
      );
      return;
    }

    _showInFlight = true;
    try {
      // Re-check after awaiting other work — finish may have suppressed us.
      if (_suppressedProgressIds.contains(id)) return;

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
        maxProgress: safeMax,
        progress: safeProgress,
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

      _lastProgressShownAt = DateTime.now();
      _lastProgressShownId = id;
      _lastProgressShownValue = safeProgress;
    } catch (e, stackTrace) {
      logger.log(
        'Failed to show download progress notification',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _showInFlight = false;
      final pending = _coalescedShow;
      _coalescedShow = null;
      if (pending != null && !_suppressedProgressIds.contains(pending.id)) {
        // Fire-and-forget the coalesced latest state after the in-flight show.
        unawaited(
          _showProgress(
            id: pending.id,
            title: pending.title,
            body: pending.body,
            progress: pending.progress,
            maxProgress: pending.maxProgress,
          ),
        );
      }
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

class _PendingProgressShow {
  const _PendingProgressShow({
    required this.id,
    required this.title,
    required this.body,
    required this.progress,
    required this.maxProgress,
  });

  final int id;
  final String title;
  final String body;
  final int progress;
  final int maxProgress;
}

final downloadNotificationService = DownloadNotificationService.instance;
