import 'dart:async';
import 'dart:collection';
import 'dart:io';

/// Global coordination for offline downloads so iOS never runs unbounded
/// concurrent work (which previously caused thermal/CPU overload and restarts).
class OfflineDownloadCoordinator {
  OfflineDownloadCoordinator._();

  static final OfflineDownloadCoordinator instance =
      OfflineDownloadCoordinator._();

  /// Hard cap on simultaneous song downloads across the whole app.
  /// iOS is always 1; Android stays conservative at 1 as well to avoid
  /// YouTube rate limits.
  static int get maxConcurrentSongDownloads => 1;

  /// Only one playlist download pipeline may run at a time. Extra requests wait.
  static const int maxConcurrentPlaylistDownloads = 1;

  bool _paused = false;
  Completer<void>? _resumeGate;

  int _songSlotsInUse = 0;
  final Queue<Completer<void>> _songWaiters = Queue<Completer<void>>();

  int _playlistSlotsInUse = 0;
  final Queue<Completer<void>> _playlistWaiters = Queue<Completer<void>>();

  bool get isPaused => _paused;

  /// Pause in-flight download loops (used when the app backgrounds on iOS).
  void pause() {
    _paused = true;
  }

  /// Resume download loops after the app returns to the foreground.
  void resume() {
    if (!_paused) return;
    _paused = false;
    final gate = _resumeGate;
    _resumeGate = null;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  /// Yields until downloads are allowed to continue.
  Future<void> waitWhilePaused() async {
    while (_paused) {
      _resumeGate ??= Completer<void>();
      await _resumeGate!.future;
    }
  }

  Future<T> withSongSlot<T>(Future<T> Function() action) async {
    while (_songSlotsInUse >= maxConcurrentSongDownloads) {
      final waiter = Completer<void>();
      _songWaiters.add(waiter);
      await waiter.future;
    }
    _songSlotsInUse++;
    try {
      await waitWhilePaused();
      return await action();
    } finally {
      _songSlotsInUse--;
      if (_songWaiters.isNotEmpty) {
        final next = _songWaiters.removeFirst();
        if (!next.isCompleted) next.complete();
      }
    }
  }

  Future<T> withPlaylistSlot<T>(Future<T> Function() action) async {
    while (_playlistSlotsInUse >= maxConcurrentPlaylistDownloads) {
      final waiter = Completer<void>();
      _playlistWaiters.add(waiter);
      await waiter.future;
    }
    _playlistSlotsInUse++;
    try {
      await waitWhilePaused();
      return await action();
    } finally {
      _playlistSlotsInUse--;
      if (_playlistWaiters.isNotEmpty) {
        final next = _playlistWaiters.removeFirst();
        if (!next.isCompleted) next.complete();
      }
    }
  }

  /// Extra delay between playlist songs on iOS to shed heat / CPU.
  Duration get interSongDelay => Platform.isIOS
      ? const Duration(milliseconds: 900)
      : const Duration(milliseconds: 400);

  Duration get rateLimitBackoff => Platform.isIOS
      ? const Duration(seconds: 12)
      : const Duration(seconds: 8);
}

final offlineDownloadCoordinator = OfflineDownloadCoordinator.instance;
