import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:ios_audio_equalizer/ios_audio_equalizer.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:wiyamusic/constants/clients.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/models/equalizer_models.dart';
import 'package:wiyamusic/models/playback_context.dart';
import 'package:wiyamusic/models/position_data.dart';
import 'package:wiyamusic/services/common_services.dart';
import 'package:wiyamusic/services/data_manager.dart';
import 'package:wiyamusic/services/io_service.dart';
import 'package:wiyamusic/services/listening_stats_service.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/utilities/connectivity_utils.dart';
import 'package:wiyamusic/utilities/map_utils.dart';
import 'package:wiyamusic/utilities/mediaitem.dart';
import 'package:wiyamusic/utilities/queue_entry_utils.dart';

class WiyaMusicAudioHandler extends BaseAudioHandler {
  WiyaMusicAudioHandler() {
    if (Platform.isAndroid) {
      _androidEqualizer = AndroidEqualizer();
      // Send YouTube CDN headers directly via ExoPlayer. The default local
      // HTTP proxy often causes googlevideo 403s after cleartext is allowed.
      audioPlayer = AudioPlayer(
        useProxyForRequestHeaders: false,
        audioPipeline: AudioPipeline(androidAudioEffects: [_androidEqualizer!]),
        audioLoadConfiguration: const AudioLoadConfiguration(
          androidLoadControl: AndroidLoadControl(
            maxBufferDuration: Duration(seconds: 60),
            bufferForPlaybackDuration: Duration(milliseconds: 500),
            bufferForPlaybackAfterRebufferDuration: Duration(seconds: 3),
          ),
        ),
      );
      audioPlayer.setAndroidAudioAttributes(
        const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
      );
    } else {
      audioPlayer = AudioPlayer();
    }

    _setupEventSubscriptions();
    _updatePlaybackState();
    _initialize();
  }

  AndroidEqualizer? _androidEqualizer;
  late final AudioPlayer audioPlayer;
  bool _equalizerInitialized = false;
  Future<bool>? _equalizerInitFuture;
  DateTime _equalizerRetryNotBefore = DateTime.fromMillisecondsSinceEpoch(0);

  Timer? _sleepTimer;
  Timer? _debounceTimer;
  bool sleepTimerExpired = false;
  bool sleepTimerEndOfSong = false;

  final List<Map> _queueList = [];
  final List<Map> _originalQueueList = [];
  final List<Map> _historyList = [];
  final BehaviorSubject<List<Map>> _queueMapStream =
      BehaviorSubject<List<Map>>.seeded([]);
  final QueueEntryIdManager _queueEntryIds = QueueEntryIdManager();
  int _currentQueueIndex = 0;
  int _currentLoadingIndex = -1;
  int _currentLoadingTransitionId = -1;
  bool _isUpdatingState = false;
  bool _pendingPlaybackStateUpdate = false;

  /// Origin of the active queue (liked songs, playlist, single song, …).
  final ValueNotifier<PlaybackContext> playbackContextNotifier =
      ValueNotifier<PlaybackContext>(PlaybackContext.singleSong());

  /// Offline shuffle-cycle: ytids already played in the current fallback pass.
  final Set<String> _offlineFallbackPlayedIds = <String>{};

  /// After stop/dismiss, ignore player events that would revive the session.
  bool _mediaSessionDismissed = false;
  int _songTransitionCounter = 0;

  bool _completionEventPending = false;
  bool _completionHandlerLoadStarted = false;
  /// Guards against double-firing completion from both ProcessingState.completed
  /// and the near-end position fallback used on iOS.
  int _completionGeneration = 0;
  DateTime? _lastNearEndCompletionAt;

  String? _lastError;

  /// True while resolving a stream URL / setting the audio source.
  /// UI should disable Play and ignore duplicate taps while this is true.
  final ValueNotifier<bool> isPlayRequestPending = ValueNotifier(false);

  /// Emits whenever a user-initiated play request fails (no auto-retry).
  final StreamController<void> _playbackFailureController =
      StreamController<void>.broadcast();

  Stream<void> get playbackFailureStream => _playbackFailureController.stream;

  static const int _maxHistorySize = 50;
  static const int _queueLookahead = 3;
  static const int _maxConcurrentPreloads = 2;
  static const Duration _songTransitionTimeout = Duration(seconds: 30);
  static const Duration _debounceInterval = Duration(milliseconds: 150);
  static const Duration _positionDataThreshold = Duration(milliseconds: 250);
  static const Duration _playbackStateHeartbeat = Duration(seconds: 1);

  static const String _recentMediaIdPrefix = 'recent:';

  int _activePreloadCount = 0;
  final Set<String> _preloadingYtIds = <String>{};
  final Set<String> _preloadedYtIds = <String>{};
  final math.Random _random = math.Random();
  Map? _preparedGenreFallback;
  String? _preparedGenreFallbackSeedId;
  Future<void>? _genreFallbackPreparation;

  late final Stream<PositionData> _positionDataStream =
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
        audioPlayer.positionStream,
        audioPlayer.bufferedPositionStream,
        audioPlayer.durationStream,
        (position, bufferedPosition, duration) {
          final reported = duration ?? Duration.zero;
          final known =
              parseSongDuration(currentSong?['duration']) ??
              mediaItem.valueOrNull?.duration;
          return PositionData(
            position,
            bufferedPosition,
            resolveReportedDuration(known, reported),
          );
        },
      ).distinct((prev, curr) {
        return (prev.position - curr.position).abs() < _positionDataThreshold &&
            prev.duration == curr.duration &&
            (prev.bufferedPosition - curr.bufferedPosition).abs() <
                _positionDataThreshold;
      }).asBroadcastStream();

  Stream<PositionData> get positionDataStream => _positionDataStream;

  late final Stream<PlaybackState> _playbackStateStream = playbackState
      .distinct((prev, curr) {
        final prevPositionBucket =
            prev.updatePosition.inMilliseconds ~/
            _positionDataThreshold.inMilliseconds;
        final currPositionBucket =
            curr.updatePosition.inMilliseconds ~/
            _positionDataThreshold.inMilliseconds;
        return prev.playing == curr.playing &&
            prev.processingState == curr.processingState &&
            prev.queueIndex == curr.queueIndex &&
            prev.speed == curr.speed &&
            prevPositionBucket == currPositionBucket;
      })
      .asBroadcastStream();

  Stream<PlaybackState> get playbackStateStream => _playbackStateStream;

  List<MediaControl> _controls(bool playing) {
    final hasMultipleTracks = _queueList.length > 1;

    return [
      if (hasMultipleTracks)
        MediaControl.skipToPrevious
      else
        MediaControl.rewind,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.stop,
      if (hasMultipleTracks)
        MediaControl.skipToNext
      else
        MediaControl.fastForward,
    ];
  }

  final _processingStateMap = {
    ProcessingState.idle: AudioProcessingState.idle,
    ProcessingState.loading: AudioProcessingState.loading,
    ProcessingState.buffering: AudioProcessingState.buffering,
    ProcessingState.ready: AudioProcessingState.ready,
    ProcessingState.completed: AudioProcessingState.completed,
  };

  void _logStreamError(String message, Object error, StackTrace stackTrace) {
    logger.log(message, error: error, stackTrace: stackTrace);
  }

  void _setupEventSubscriptions() {
    audioPlayer.playbackEventStream
        .throttleTime(const Duration(milliseconds: 100))
        .listen(
          (event) {
            _updatePlaybackState();
          },
          onError: (error, stackTrace) {
            _logStreamError('Playback event stream error', error, stackTrace);
          },
        );

    audioPlayer.processingStateStream.distinct().listen(
      _handleProcessingStateChange,
      onError: (error, stackTrace) {
        _logStreamError('Processing state stream error', error, stackTrace);
      },
    );

    // iOS/AVPlayer sometimes never emits ProcessingState.completed (or emits
    // ready immediately after it). Watch position as a reliable fallback so
    // queue auto-advance still works when a track reaches its end.
    audioPlayer.positionStream
        .throttleTime(const Duration(milliseconds: 400))
        .listen(
          _handleNearEndPosition,
          onError: (error, stackTrace) {
            _logStreamError('Position stream error', error, stackTrace);
          },
        );

    audioPlayer.durationStream.listen(
      (duration) {
        if (_currentQueueIndex < _queueList.length && duration != null) {
          _updateCurrentMediaItemWithDuration(duration);
        }
      },
      onError: (error, stackTrace) {
        _logStreamError('Duration stream error', error, stackTrace);
      },
    );

    audioPlayer.playerStateStream
        .distinct()
        .throttleTime(const Duration(milliseconds: 100))
        .listen(
          (state) {
            listeningStatsService.handlePlayerStateForListeningStats(
              state,
              currentSong: currentSong,
            );
            if (state.processingState == ProcessingState.idle &&
                !state.playing &&
                _lastError != null) {
              // Keep the error for UI notification paths; do not auto-retry.
              _lastError = null;
            }
            _debouncedStateUpdate();
          },
          onError: (error, stackTrace) {
            _logStreamError('Player state stream error', error, stackTrace);
          },
        );

    Rx.combineLatest2(
          audioPlayer.currentIndexStream.distinct(),
          audioPlayer.sequenceStateStream.distinct(),
          (index, sequence) => {'index': index, 'sequence': sequence},
        )
        .throttleTime(const Duration(milliseconds: 100))
        .listen(
          (_) => _debouncedStateUpdate(),
          onError: (error, stackTrace) {
            _logStreamError('Current index stream error', error, stackTrace);
          },
        );
  }

  void _debouncedStateUpdate() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceInterval, () {
      if (!_isUpdatingState) {
        _updatePlaybackState();
      }
    });
  }

  void _hydrateQueueEntryIds() {
    _queueEntryIds
      ..ensureIds(_queueList)
      ..ensureIds(_originalQueueList);
  }

  MediaItem _getMediaItemForQueue(Map song) {
    return mapToMediaItem(song).copyWith(id: _queueEntryIds.ensureId(song));
  }

  List<MediaItem> _buildQueueMediaItems() =>
      _queueList.map(_getMediaItemForQueue).toList(growable: false);

  bool _shouldUpdateDuration(Duration? currentDuration, Duration nextDuration) {
    return currentDuration == null ||
        !durationEquals(currentDuration, nextDuration);
  }

  bool _isCurrentMediaItemMatchingSong(
    MediaItem? currentItem,
    MediaItem currentQueueMediaItem,
    String? currentSongYtid,
  ) {
    if (currentItem == null) return false;

    if (currentItem.id == currentQueueMediaItem.id) {
      return true;
    }

    return currentSongYtid != null &&
        currentSongYtid.isNotEmpty &&
        currentItem.extras?['ytid']?.toString() == currentSongYtid;
  }

  void _updateCurrentMediaItemWithDuration(Duration duration) {
    try {
      final queueIndex = _currentQueueIndex;
      if (queueIndex < 0 || queueIndex >= _queueList.length) return;

      final currentSong = _queueList[queueIndex];
      final knownDuration =
          parseSongDuration(currentSong['duration']) ??
          mediaItem.valueOrNull?.duration;
      final resolvedDuration = resolveReportedDuration(knownDuration, duration);

      // Persist the trusted length back onto the queue song so later offline
      // / rebuild paths don't depend on inflated file metadata.
      if (resolvedDuration > Duration.zero &&
          parseSongDuration(currentSong['duration']) == null) {
        currentSong['duration'] = resolvedDuration.inSeconds;
      }

      final currentMediaItem = _getMediaItemForQueue(currentSong);
      final currentSongYtid = currentSong['ytid']?.toString();
      final currentItem = mediaItem.valueOrNull;
      final isMatchingCurrentItem = _isCurrentMediaItemMatchingSong(
        currentItem,
        currentMediaItem,
        currentSongYtid,
      );

      if (currentItem != null &&
          isMatchingCurrentItem &&
          _shouldUpdateDuration(currentItem.duration, resolvedDuration)) {
        mediaItem.add(currentItem.copyWith(duration: resolvedDuration));
      } else if (!isMatchingCurrentItem) {
        mediaItem.add(currentMediaItem.copyWith(duration: resolvedDuration));
      }

      listeningStatsService.updateListeningSessionDuration(
        currentSongYtid,
        resolvedDuration,
      );

      final existingQueue = queue.valueOrNull;
      if (existingQueue != null && queueIndex < existingQueue.length) {
        final queueItem = existingQueue[queueIndex];
        if (_shouldUpdateDuration(queueItem.duration, resolvedDuration)) {
          final updatedQueue = List<MediaItem>.from(existingQueue);
          updatedQueue[queueIndex] = queueItem.copyWith(
            duration: resolvedDuration,
          );
          queue.add(updatedQueue);
        }
        return;
      }

      final rebuiltQueue = _buildQueueMediaItems();
      if (queueIndex < rebuiltQueue.length) {
        rebuiltQueue[queueIndex] = rebuiltQueue[queueIndex].copyWith(
          duration: resolvedDuration,
        );
      }
      queue.add(rebuiltQueue);
    } catch (e, stackTrace) {
      logger.log(
        'Error updating media item with duration',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void resetListeningStatsSession({
    bool countCurrentTick = false,
    bool flushStats = true,
  }) {
    listeningStatsService.finishListeningSession(
      countCurrentTick: countCurrentTick,
      flushStats: flushStats,
    );
  }

  void startListeningStatsSessionIfNeeded() {
    listeningStatsService.startListeningSessionIfNeeded(
      currentSong: currentSong,
      isPlaying: audioPlayer.playing,
    );
  }

  Future<void> _initialize() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      // Always set loop mode to off - we handle all repeating through _handleSongCompletion
      // This ensures ProcessingState.completed is always fired for song transitions
      await audioPlayer.setLoopMode(LoopMode.off);

      // Apply stored shuffle mode to audio player
      await audioPlayer.setShuffleModeEnabled(shuffleNotifier.value);

      // Initialize equalizer once at startup
      unawaited(_ensureEqualizerConfigured());
    } catch (e, stackTrace) {
      logger.log(
        'Error initializing audio session',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool> _ensureEqualizerConfigured({bool force = false}) async {
    if (Platform.isIOS) {
      return IosAudioEqualizer.isSupported;
    }
    if (!Platform.isAndroid || _androidEqualizer == null) return false;
    if (_equalizerInitialized) return true;

    final now = DateTime.now();
    if (!force && now.isBefore(_equalizerRetryNotBefore)) {
      return false;
    }

    if (!force && audioPlayer.audioSource == null) {
      return false;
    }

    final inFlight = _equalizerInitFuture;
    if (inFlight != null) {
      return inFlight;
    }

    _equalizerInitFuture = _configureEqualizer();
    try {
      return await _equalizerInitFuture!;
    } finally {
      _equalizerInitFuture = null;
    }
  }

  Future<bool> _configureEqualizer() async {
    final equalizer = _androidEqualizer;
    if (equalizer == null) return false;

    try {
      final params = await equalizer.parameters.timeout(
        const Duration(seconds: 3),
      );

      final savedGains = equalizerBandGains.value;
      if (savedGains.isNotEmpty) {
        for (var i = 0; i < params.bands.length && i < savedGains.length; i++) {
          final clamped = savedGains[i].clamp(
            params.minDecibels,
            params.maxDecibels,
          );
          await params.bands[i].setGain(clamped);
        }
      }

      await equalizer.setEnabled(equalizerEnabled.value);
      _equalizerInitialized = true;
      _equalizerRetryNotBefore = DateTime.fromMillisecondsSinceEpoch(0);
      return true;
    } catch (e, stackTrace) {
      _equalizerRetryNotBefore = DateTime.now().add(
        const Duration(seconds: 10),
      );
      logger.log(
        'Equalizer initialization deferred',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Equalizer is available on Android (ExoPlayer) and iOS (AVPlayer tap).
  bool get isEqualizerSupported =>
      (Platform.isAndroid && _androidEqualizer != null) ||
      IosAudioEqualizer.isSupported;

  Future<EqualizerParametersInfo?> getEqualizerParameters() async {
    if (Platform.isIOS) {
      return _getIosEqualizerParameters(restoreSettings: true);
    }

    final equalizer = _androidEqualizer;
    if (equalizer == null) return null;

    final initialized = await _ensureEqualizerConfigured();
    if (!initialized) return null;
    try {
      final params = await equalizer.parameters.timeout(
        const Duration(seconds: 2),
      );
      return EqualizerParametersInfo(
        minDecibels: params.minDecibels,
        maxDecibels: params.maxDecibels,
        bands: [
          for (var i = 0; i < params.bands.length; i++)
            EqualizerBandInfo(
              index: i,
              centerFrequency: params.bands[i].centerFrequency,
              gain: params.bands[i].gain,
            ),
        ],
      );
    } catch (e, stackTrace) {
      logger.log(
        'Failed to get equalizer parameters',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<EqualizerParametersInfo?> _getIosEqualizerParameters({
    bool restoreSettings = false,
  }) async {
    try {
      final raw = await IosAudioEqualizer.getParameters();
      if (raw == null) return null;

      final bandsRaw = raw['bands'];
      final bands = <EqualizerBandInfo>[];
      if (bandsRaw is List) {
        for (final entry in bandsRaw) {
          if (entry is! Map) continue;
          final map = Map<String, dynamic>.from(entry);
          bands.add(
            EqualizerBandInfo(
              index: (map['index'] as num?)?.toInt() ?? bands.length,
              centerFrequency:
                  (map['centerFrequency'] as num?)?.toDouble() ?? 0,
              gain: (map['gain'] as num?)?.toDouble() ?? 0,
            ),
          );
        }
      }

      final minDb = (raw['minDecibels'] as num?)?.toDouble() ?? -12;
      final maxDb = (raw['maxDecibels'] as num?)?.toDouble() ?? 12;

      if (restoreSettings) {
        final savedGains = equalizerBandGains.value;
        if (savedGains.isNotEmpty) {
          final clamped = [
            for (var i = 0; i < bands.length; i++)
              (i < savedGains.length ? savedGains[i] : 0.0).clamp(minDb, maxDb),
          ];
          await IosAudioEqualizer.setBandGains(clamped);
          for (var i = 0; i < bands.length; i++) {
            bands[i] = EqualizerBandInfo(
              index: bands[i].index,
              centerFrequency: bands[i].centerFrequency,
              gain: clamped[i],
            );
          }
        }
        await IosAudioEqualizer.setEnabled(equalizerEnabled.value);
      }

      return EqualizerParametersInfo(
        minDecibels: minDb,
        maxDecibels: maxDb,
        bands: bands,
      );
    } catch (e, stackTrace) {
      logger.log(
        'Failed to get iOS equalizer parameters',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    if (Platform.isIOS) {
      try {
        await IosAudioEqualizer.setEnabled(enabled);
        equalizerEnabled.value = enabled;
        unawaited(
          addOrUpdateData<bool>('settings', 'equalizerEnabled', enabled),
        );
      } catch (e, stackTrace) {
        logger.log(
          'Failed to set iOS equalizer enabled state',
          error: e,
          stackTrace: stackTrace,
        );
      }
      return;
    }

    final equalizer = _androidEqualizer;
    if (equalizer == null) return;

    final initialized = await _ensureEqualizerConfigured(force: true);
    if (!initialized) return;
    try {
      await equalizer.setEnabled(enabled);
      equalizerEnabled.value = enabled;
      unawaited(addOrUpdateData<bool>('settings', 'equalizerEnabled', enabled));
    } catch (e, stackTrace) {
      logger.log(
        'Failed to set equalizer enabled state',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> setEqualizerBandGain(int index, double gain) async {
    if (Platform.isIOS) {
      try {
        await IosAudioEqualizer.setBandGain(index, gain);
        final gains = List<double>.from(equalizerBandGains.value);
        while (gains.length <= index) {
          gains.add(0);
        }
        gains[index] = gain;
        equalizerBandGains.value = gains;
        unawaited(
          addOrUpdateData<List<double>>(
            'settings',
            'equalizerBandGains',
            gains,
          ),
        );
      } catch (e, stackTrace) {
        logger.log(
          'Failed to set iOS equalizer band gain',
          error: e,
          stackTrace: stackTrace,
        );
      }
      return;
    }

    final equalizer = _androidEqualizer;
    if (equalizer == null) return;

    final initialized = await _ensureEqualizerConfigured(force: true);
    if (!initialized) return;

    try {
      final params = await equalizer.parameters;
      if (index < 0 || index >= params.bands.length) {
        return;
      }

      final clamped = gain.clamp(params.minDecibels, params.maxDecibels);
      await params.bands[index].setGain(clamped);

      final gains = params.bands.map((band) => band.gain).toList();
      equalizerBandGains.value = gains;
      unawaited(
        addOrUpdateData<List<double>>('settings', 'equalizerBandGains', gains),
      );
    } catch (e, stackTrace) {
      logger.log(
        'Failed to set equalizer band gain',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> resetEqualizerBands() async {
    if (Platform.isIOS) {
      try {
        await IosAudioEqualizer.resetBands();
        final params = await IosAudioEqualizer.getParameters();
        final bandCount = (params?['bands'] as List?)?.length ?? 5;
        final gains = List<double>.filled(bandCount, 0);
        equalizerBandGains.value = gains;
        unawaited(
          addOrUpdateData<List<double>>(
            'settings',
            'equalizerBandGains',
            gains,
          ),
        );
      } catch (e, stackTrace) {
        logger.log(
          'Failed to reset iOS equalizer bands',
          error: e,
          stackTrace: stackTrace,
        );
      }
      return;
    }

    final equalizer = _androidEqualizer;
    if (equalizer == null) return;

    final initialized = await _ensureEqualizerConfigured(force: true);
    if (!initialized) return;

    try {
      final params = await equalizer.parameters;
      for (final band in params.bands) {
        await band.setGain(0);
      }
      final gains = List<double>.filled(params.bands.length, 0);
      equalizerBandGains.value = gains;
      unawaited(
        addOrUpdateData<List<double>>('settings', 'equalizerBandGains', gains),
      );
    } catch (e, stackTrace) {
      logger.log(
        'Failed to reset equalizer bands',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  bool _hasSignificantPositionChange(
    Duration currentPosition,
    Duration lastUpdatePosition,
    DateTime lastUpdateTime,
    DateTime now,
    double speed,
  ) {
    final expectedPosition =
        lastUpdatePosition + (now.difference(lastUpdateTime)) * speed;
    return (currentPosition - expectedPosition).abs() >
        const Duration(milliseconds: 500);
  }

  void _updatePlaybackState() {
    if (_isUpdatingState) {
      _pendingPlaybackStateUpdate = true;
      return;
    }

    _isUpdatingState = true;

    try {
      final now = DateTime.now();

      // After stop/dismiss, keep the session idle with no controls so the
      // system media notification stays dismissed.
      if (_mediaSessionDismissed ||
          (_queueList.isEmpty && mediaItem.valueOrNull == null)) {
        final currentState = playbackState.valueOrNull;
        if (currentState == null ||
            currentState.processingState != AudioProcessingState.idle ||
            currentState.playing ||
            currentState.controls.isNotEmpty) {
          playbackState.add(
            PlaybackState(
              controls: const [],
              systemActions: const {},
              processingState: AudioProcessingState.idle,
              playing: false,
              updateTime: now,
            ),
          );
        }
        return;
      }

      final currentPosition = audioPlayer.position;
      final isPlaying = audioPlayer.playing;
      final currentState = playbackState.valueOrNull;
      final newProcessingState =
          _processingStateMap[audioPlayer.processingState] ??
          AudioProcessingState.idle;
      final bufferedPosition = audioPlayer.bufferedPosition;

      final shouldEmitProgressTick =
          currentState != null &&
          isPlaying &&
          now.difference(currentState.updateTime) >= _playbackStateHeartbeat;
      final hasBufferedPositionChange =
          currentState == null ||
          (bufferedPosition - currentState.bufferedPosition).abs() >=
              const Duration(seconds: 1);

      final shouldUpdate =
          currentState == null ||
          currentState.playing != isPlaying ||
          currentState.processingState != newProcessingState ||
          currentState.queueIndex != _currentQueueIndex ||
          currentState.speed != audioPlayer.speed ||
          shouldEmitProgressTick ||
          hasBufferedPositionChange ||
          (_hasSignificantPositionChange(
            currentPosition,
            currentState.updatePosition,
            currentState.updateTime,
            now,
            currentState.speed,
          ));

      if (shouldUpdate) {
        playbackState.add(
          PlaybackState(
            controls: _controls(isPlaying),
            systemActions: const {
              MediaAction.seek,
              MediaAction.seekForward,
              MediaAction.seekBackward,
            },
            androidCompactActionIndices: const [0, 1, 3],
            processingState: newProcessingState,
            playing: isPlaying,
            updatePosition: currentPosition,
            bufferedPosition: bufferedPosition,
            speed: audioPlayer.speed,
            queueIndex:
                _currentQueueIndex >= 0 &&
                    _currentQueueIndex < _queueList.length
                ? _currentQueueIndex
                : null,
            updateTime: now,
          ),
        );
      }
    } catch (e, stackTrace) {
      logger.log(
        'Error updating playback state',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _isUpdatingState = false;
      if (_pendingPlaybackStateUpdate) {
        _pendingPlaybackStateUpdate = false;
        _updatePlaybackState();
      }
    }
  }

  void _handleProcessingStateChange(ProcessingState state) {
    try {
      if (state == ProcessingState.completed) {
        _requestSongCompletion();
      } else if (state == ProcessingState.ready) {
        // Do NOT clear _completionEventPending here. On iOS, AVPlayer can emit
        // ready immediately after completed (or while the completion microtask
        // is still queued). Clearing the flag would cancel skipToNext and the
        // queue would stall at the ended track.
        if (!_completionEventPending) {
          _completionHandlerLoadStarted = false;
          // Clear the expired flag so future song completions are not
          // blocked after a sleep timer fired in a previous session.
          // Do NOT touch sleepTimerEndOfSong here — 'ready' fires not
          // only for new songs but also on buffering recovery within the
          // same song, which would cancel an active "end of song" timer.
          sleepTimerExpired = false;
        }
      }
    } catch (e, stackTrace) {
      logger.log(
        'Error handling processing state change',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Fallback for platforms (notably iOS) that stall at end-of-track without
  /// always emitting [ProcessingState.completed].
  void _handleNearEndPosition(Duration position) {
    try {
      if (_completionEventPending || sleepTimerExpired) return;
      if (_mediaSessionDismissed) return;
      if (_currentLoadingIndex >= 0) return;

      final playerDuration = audioPlayer.duration;
      final known =
          parseSongDuration(currentSong?['duration']) ??
          mediaItem.valueOrNull?.duration;
      final duration = resolveReportedDuration(known, playerDuration ?? Duration.zero);
      if (duration <= Duration.zero) return;

      // Only trigger when we're actually near the end of a playing (or just
      // finished) track — not during seeks/scrubbing early in the song.
      final remaining = duration - position;
      if (remaining > const Duration(milliseconds: 600)) return;
      if (position < duration * 0.85 &&
          remaining > const Duration(milliseconds: 200)) {
        return;
      }

      final now = DateTime.now();
      if (_lastNearEndCompletionAt != null &&
          now.difference(_lastNearEndCompletionAt!) <
              const Duration(milliseconds: 1500)) {
        return;
      }

      final state = audioPlayer.processingState;
      final endedLikeState =
          state == ProcessingState.completed ||
          state == ProcessingState.ready ||
          state == ProcessingState.idle;
      if (!endedLikeState && audioPlayer.playing) {
        // Still actively playing through the last few hundred ms — wait for
        // either completed or playing to stop.
        if (remaining > const Duration(milliseconds: 250)) return;
      }

      _lastNearEndCompletionAt = now;
      _requestSongCompletion();
    } catch (e, stackTrace) {
      logger.log(
        'Error handling near-end position',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _requestSongCompletion() {
    if (sleepTimerEndOfSong) {
      sleepTimerExpired = true;
      sleepTimerEndOfSong = false;
      stop();
      sleepTimerNotifier.value = null;
      return;
    }

    listeningStatsService.finishListeningSession(
      countCurrentTick: true,
      wasPlaying: true,
    );

    if (sleepTimerExpired || _completionEventPending) return;

    _completionEventPending = true;
    final generation = ++_completionGeneration;

    Future.microtask(() async {
      try {
        if (sleepTimerExpired || generation != _completionGeneration) return;
        if (!_completionEventPending) return;
        await _handleSongCompletion();
      } finally {
        if (generation == _completionGeneration) {
          _completionEventPending = false;
          _completionHandlerLoadStarted = false;
        }
      }
    });
  }

  void _handlePlaybackError({bool notifyUser = true}) {
    logger.log('Playback request failed', error: _lastError);

    if (notifyUser && !_playbackFailureController.isClosed) {
      _playbackFailureController.add(null);
    }
  }

  void _setPlayRequestPending(bool pending) {
    if (isPlayRequestPending.value != pending) {
      isPlayRequestPending.value = pending;
    }
  }

  Future<void> _handleSongCompletion() async {
    try {
      if (_currentQueueIndex >= 0 && _currentQueueIndex < _queueList.length) {
        _addToHistory(_queueList[_currentQueueIndex]);
      }

      // Determine what to play next based on queue position and repeat mode
      if (repeatNotifier.value == AudioServiceRepeatMode.one) {
        // Repeat single song - play current song again
        await playAgain();
      } else {
        // For all other cases (next song, repeat all, auto-play), skipToNext handles it
        await skipToNext();
      }
    } catch (e, stackTrace) {
      logger.log(
        'Error handling song completion',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool> _backgroundAddSongsToQueue() async {
    // Don't require audioPlayer.playing — on iOS (and after completion) the
    // player is often already paused/stopped by the time this runs.
    if (!await _shouldAllowOnlinePlaybackSideEffects()) {
      return false;
    }

    try {
      final baseSong = _getCurrentSongForRecommendations();
      if (baseSong == null) return false;

      await getSimilarSong(baseSong['ytid']).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          logger.log('Background song fetch timed out');
        },
      );

      if (nextRecommendedSong == null) return false;

      final songToAdd = nextRecommendedSong as Map;
      nextRecommendedSong = null;
      await _insertRecommendedSong(songToAdd);
      return true;
    } catch (e, stackTrace) {
      logger.log(
        'Error in background song addition',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  bool? _cachedHasInternet;
  DateTime? _internetCheckedAt;

  /// Cached reachability probe so skip/preload paths don't DNS-lookup every time.
  Future<bool> _hasInternetAccessCached({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedHasInternet != null &&
        _internetCheckedAt != null &&
        now.difference(_internetCheckedAt!) < const Duration(seconds: 5)) {
      return _cachedHasInternet!;
    }

    _cachedHasInternet = await hasInternetAccess();
    _internetCheckedAt = now;
    return _cachedHasInternet!;
  }

  Future<bool> _canPlaySongWithoutNetwork(Map song) async {
    final ytid = song['ytid']?.toString();
    if (ytid == null || ytid.isEmpty) return false;
    if (!isSongAlreadyOffline(ytid)) return false;

    final offlineSong = getOfflineSongByYtid(ytid);
    final path = await FilePaths.resolveExistingAudioPath(
      ytid,
      storedPath:
          song['audioPath']?.toString() ?? offlineSong['audioPath']?.toString(),
    );
    return path != null;
  }

  /// Next/previous index that can play without streaming.
  ///
  /// When [wrap] is true (repeat-all), searches the whole queue circularly.
  Future<int?> _findOfflinePlayableIndex({
    required int fromIndex,
    required int direction,
    bool wrap = false,
  }) async {
    if (_queueList.isEmpty) return null;

    final length = _queueList.length;
    for (var step = 1; step <= length; step++) {
      final raw = fromIndex + (direction * step);
      late final int candidate;
      if (wrap) {
        candidate = (raw % length + length) % length;
      } else {
        if (raw < 0 || raw >= length) return null;
        candidate = raw;
      }

      if (await _canPlaySongWithoutNetwork(_queueList[candidate])) {
        return candidate;
      }

      if (wrap && step == length) break;
    }
    return null;
  }

  Future<void> _applyPlaybackContext(
    PlaybackContext context, {
    required bool replacingQueue,
  }) async {
    playbackContextNotifier.value = context;

    if (replacingQueue && !context.isOfflineFallback) {
      _offlineFallbackPlayedIds.clear();
    }

    // Do not force Repeat All here — respect the user's current repeat
    // preference. Starting a library playlist must not re-enable Repeat after
    // the user has turned it off.
  }

  Future<List<Map>> _collectPlayableOfflineSongs() async {
    final playable = <Map>[];
    for (final song in userOfflineSongs.value.whereType<Map>()) {
      if (await _canPlaySongWithoutNetwork(song)) {
        playable.add(cloneMap(song));
      }
    }
    return playable;
  }

  /// When offline and queue-repeat is off, build a shuffle cycle from downloaded
  /// songs. Avoids replaying a song until every offline track has been played.
  Future<bool> _startOfflineShuffleFallback() async {
    try {
      final playable = await _collectPlayableOfflineSongs();
      if (playable.isEmpty) return false;

      final currentId = currentSong?['ytid']?.toString();

      if (playable.length == 1) {
        final only = playable.first;
        final onlyId = only['ytid']?.toString();
        if (onlyId != null) _offlineFallbackPlayedIds.add(onlyId);
        await addPlaylistToQueue(
          [only],
          replace: true,
          startIndex: 0,
          context: PlaybackContext.offlineFallback(),
        );
        return true;
      }

      var candidates = playable.where((song) {
        final id = song['ytid']?.toString();
        return id != null && !_offlineFallbackPlayedIds.contains(id);
      }).toList();

      if (candidates.isEmpty) {
        _offlineFallbackPlayedIds.clear();
        candidates = List<Map>.from(playable);
      }

      if (candidates.length > 1 && currentId != null) {
        final withoutCurrent = candidates
            .where((song) => song['ytid']?.toString() != currentId)
            .toList();
        if (withoutCurrent.isNotEmpty) {
          candidates = withoutCurrent;
        }
      }

      candidates.shuffle(_random);

      for (final song in candidates) {
        final id = song['ytid']?.toString();
        if (id != null) _offlineFallbackPlayedIds.add(id);
      }

      await addPlaylistToQueue(
        candidates,
        replace: true,
        startIndex: 0,
        context: PlaybackContext.offlineFallback(),
      );
      return true;
    } catch (e, stackTrace) {
      logger.log(
        'Error starting offline shuffle fallback',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  void _clearPlaybackSessionState({bool clearContext = true}) {
    _offlineFallbackPlayedIds.clear();
    if (clearContext) {
      playbackContextNotifier.value = PlaybackContext.singleSong();
    }
  }

  /// Online preload / related-song fetches require real internet (and must not
  /// run in offline mode).
  Future<bool> _shouldAllowOnlinePlaybackSideEffects({
    bool forceRefresh = false,
  }) async {
    if (offlineMode.value) return false;
    return _hasInternetAccessCached(forceRefresh: forceRefresh);
  }

  Map? _getCurrentSongForRecommendations() {
    final currentMediaItem = mediaItem.valueOrNull;

    if (currentMediaItem == null || currentMediaItem.id.isEmpty) {
      logger.log('No current media item available');
      return null;
    }

    return mediaItemToMap(currentMediaItem);
  }

  void _addToHistory(Map song) {
    try {
      _historyList.insert(0, cloneMap(song));

      if (_historyList.length > _maxHistorySize) {
        _historyList.removeRange(_maxHistorySize, _historyList.length);
      }
    } catch (e, stackTrace) {
      logger.log('Error adding to history', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> addToQueue(Map song, {bool playNext = false}) async {
    try {
      if (song['ytid'] == null || song['ytid'].toString().isEmpty) {
        logger.log('Invalid song data for queue');
        return;
      }

      int insertIndex;

      if (playNext) {
        insertIndex = _currentQueueIndex + 1;
        if (insertIndex < 0) insertIndex = 0;
        if (insertIndex > _queueList.length) {
          insertIndex = _queueList.length;
        }
      } else {
        insertIndex = _queueList.length;
      }

      final queueSong = _queueEntryIds.createSong(song);
      queueSong['isManuallyAdded'] = true;
      _queueList.insert(insertIndex, queueSong);

      if (_currentQueueIndex < 0) {
        _currentQueueIndex = 0;
      }

      _updateQueueMediaItems();
      _cleanupOldPreloadedSongs();

      if (!audioPlayer.playing && _queueList.length == 1) {
        await _playFromQueue(0);
      }
    } catch (e, stackTrace) {
      logger.log('Error adding to queue', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _insertRecommendedSong(
    Map song, {
    bool forcePlayAtEnd = false,
  }) async {
    try {
      if (song['ytid'] == null || song['ytid'].toString().isEmpty) {
        logger.log('Invalid recommended song data for queue');
        return;
      }

      final insertIndex = _queueList.length;
      // iOS often leaves the player in ready/idle (not completed) after a
      // track ends. Treat a non-playing end-of-queue state as eligible too.
      final endedWithoutNext =
          audioPlayer.processingState == ProcessingState.completed ||
          ((audioPlayer.processingState == ProcessingState.ready ||
                  audioPlayer.processingState == ProcessingState.idle) &&
              !audioPlayer.playing);
      final shouldPlayInsertedSong =
          (playNextSongAutomatically.value || forcePlayAtEnd) &&
          !sleepTimerExpired &&
          _currentLoadingIndex == -1 &&
          endedWithoutNext &&
          _queueList.isNotEmpty &&
          _currentQueueIndex == _queueList.length - 1;
      final queueSong = _queueEntryIds.createSong(song);
      queueSong['isAutoPicked'] = true;
      _queueList.insert(insertIndex, queueSong);

      if (_currentQueueIndex < 0) {
        _currentQueueIndex = 0;
      }

      _updateQueueMediaItems();
      _cleanupOldPreloadedSongs();

      if (shouldPlayInsertedSong) {
        await _playFromQueue(insertIndex);
      } else if (!audioPlayer.playing && _queueList.length == 1) {
        await _playFromQueue(0);
      }
    } catch (e, stackTrace) {
      logger.log(
        'Error inserting recommended song',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  String? _normalizedGenre(Map song) {
    final rawGenre = song['genre'] ?? song['genres'] ?? song['category'];
    if (rawGenre is Iterable) {
      for (final value in rawGenre) {
        final normalized = value.toString().trim();
        if (normalized.isNotEmpty) return normalized;
      }
      return null;
    }
    final normalized = rawGenre?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  String? _genreFromPlaylist(Map<dynamic, dynamic> playlist) {
    final explicit = _normalizedGenre(playlist);
    if (explicit != null) return explicit;

    final searchable = [
      playlist['title'],
      playlist['description'],
      playlist['subtitle'],
    ].whereType<Object>().join(' ').toLowerCase();
    const knownGenres = <String, String>{
      'hip hop': 'Hip Hop',
      'hip-hop': 'Hip Hop',
      'r&b': 'R&B',
      'rhythm and blues': 'R&B',
      'electronic': 'Electronic',
      'edm': 'Electronic',
      'acoustic': 'Acoustic',
      'rock': 'Rock',
      'pop': 'Pop',
      'jazz': 'Jazz',
      'classical': 'Classical',
      'country': 'Country',
      'reggae': 'Reggae',
      'metal': 'Metal',
      'blues': 'Blues',
      'folk': 'Folk',
      'latin': 'Latin',
      'opm': 'OPM',
    };
    for (final entry in knownGenres.entries) {
      if (searchable.contains(entry.key)) return entry.value;
    }
    return null;
  }

  bool _hasSameGenre(Map song, String genre) {
    final songGenre = _normalizedGenre(song);
    return songGenre != null && songGenre.toLowerCase() == genre.toLowerCase();
  }

  Future<Map?> _selectGenreFallback(Map seedSong) async {
    final genre = _normalizedGenre(seedSong);
    final seedId = _songYtid(seedSong);
    if (genre == null || seedId == null) return null;

    final excludedIds = <String>{
      seedId,
      ..._queueList.map(_songYtid).whereType<String>(),
    };

    final offlineCandidates = userOfflineSongs.value
        .whereType<Map>()
        .where((song) => _hasSameGenre(song, genre))
        .where((song) => !excludedIds.contains(_songYtid(song)))
        .toList();
    if (offlineCandidates.isNotEmpty) {
      return cloneMap(
        offlineCandidates[_random.nextInt(offlineCandidates.length)],
      );
    }

    if (offlineMode.value) return null;

    final onlineSongs = await fetchSongsList(
      '$genre music',
    ).timeout(const Duration(seconds: 12), onTimeout: () => const []);
    final onlineCandidates = onlineSongs
        .whereType<Map>()
        .where((song) => !excludedIds.contains(_songYtid(song)))
        .map((song) => {...song, 'genre': genre})
        .toList();
    if (onlineCandidates.isEmpty) return null;
    return onlineCandidates[_random.nextInt(onlineCandidates.length)];
  }

  Future<void> _prepareGenreFallback() async {
    if (!await _shouldAllowOnlinePlaybackSideEffects()) {
      _preparedGenreFallback = null;
      _preparedGenreFallbackSeedId = null;
      return;
    }

    final seedSong = currentSong;
    final seedId = seedSong == null ? null : _songYtid(seedSong);
    if (seedSong == null ||
        seedId == null ||
        _normalizedGenre(seedSong) == null) {
      _preparedGenreFallback = null;
      _preparedGenreFallbackSeedId = null;
      return;
    }
    if (_preparedGenreFallbackSeedId == seedId &&
        (_preparedGenreFallback != null || _genreFallbackPreparation != null)) {
      await (_genreFallbackPreparation ?? Future<void>.value());
      return;
    }

    _preparedGenreFallback = null;
    _preparedGenreFallbackSeedId = seedId;
    final preparation = Future<void>(() async {
      final candidate = await _selectGenreFallback(seedSong);
      if (_preparedGenreFallbackSeedId != seedId) return;
      _preparedGenreFallback = candidate;
      if (candidate != null &&
          await _shouldAllowOnlinePlaybackSideEffects()) {
        await _preloadSingleSongControlled(candidate);
      }
    });
    _genreFallbackPreparation = preparation;
    await preparation.whenComplete(() {
      if (identical(_genreFallbackPreparation, preparation)) {
        _genreFallbackPreparation = null;
      }
    });
  }

  Future<void> _playGenreFallbackAtQueueEnd() async {
    if (!await _shouldAllowOnlinePlaybackSideEffects()) return;
    if (sleepTimerExpired ||
        _currentLoadingIndex != -1 ||
        _queueList.isEmpty ||
        _currentQueueIndex != _queueList.length - 1) {
      return;
    }

    final seedSong = currentSong;
    final seedId = seedSong == null ? null : _songYtid(seedSong);
    if (seedSong == null || seedId == null) return;

    if (_preparedGenreFallbackSeedId != seedId) {
      await _prepareGenreFallback();
    } else if (_genreFallbackPreparation != null) {
      await _genreFallbackPreparation;
    }

    final candidate =
        _preparedGenreFallback ?? await _selectGenreFallback(seedSong);
    _preparedGenreFallback = null;
    _preparedGenreFallbackSeedId = null;
    if (candidate == null) return;

    await _insertRecommendedSong(candidate, forcePlayAtEnd: true);
  }

  void _cleanupOldPreloadedSongs() {
    Future.microtask(() async {
      try {
        final queueYtIds = _queueList
            .map((song) => song['ytid']?.toString())
            .where((ytid) => ytid != null)
            .toSet();

        final oldPreloadedSongs = _preloadedYtIds
            .where((ytid) => !queueYtIds.contains(ytid))
            .toList();

        for (final ytid in oldPreloadedSongs) {
          _preloadedYtIds.remove(ytid);
        }

        final stalePreloadingEntries = _preloadingYtIds
            .where((ytid) => !queueYtIds.contains(ytid))
            .toList();

        for (final ytid in stalePreloadingEntries) {
          _preloadingYtIds.remove(ytid);
        }

        if (oldPreloadedSongs.isNotEmpty || stalePreloadingEntries.isNotEmpty) {
          logger.log(
            'Cleaned up ${oldPreloadedSongs.length + stalePreloadingEntries.length} old preload entries',
          );
        }
      } catch (e, stackTrace) {
        logger.log(
          'Error cleaning up preloaded songs',
          error: e,
          stackTrace: stackTrace,
        );
      }
    });
  }

  Future<void> addPlaylistToQueue(
    List<Map> songs, {
    bool replace = false,
    int? startIndex,
    PlaybackContext? context,
    bool enableShuffle = false,
  }) async {
    try {
      final manuallyAddedSongs = replace ? _getUnplayedManualSongs() : <Map>[];
      if (replace) {
        _queueList.clear();
        _originalQueueList.clear();
        _preparedGenreFallback = null;
        _preparedGenreFallbackSeedId = null;
        _currentQueueIndex = 0;
        // Invalidate any in-flight queue load so its finally block does not
        // clear a newer request, and release the pending lock so the next
        // _playFromQueue can take over after a user tap.
        _songTransitionCounter++;
        _currentLoadingIndex = -1;
        _currentLoadingTransitionId = -1;
        _setPlayRequestPending(false);
        _resetPreloadingState();

        final resolvedContext =
            context ??
            (songs.length <= 1
                ? PlaybackContext.singleSong(
                    id: songs.isNotEmpty ? songs.first['ytid']?.toString() : null,
                    title: songs.isNotEmpty
                        ? songs.first['title']?.toString()
                        : null,
                  )
                : const PlaybackContext(kind: PlaybackSourceKind.other));
        await _applyPlaybackContext(resolvedContext, replacingQueue: true);

        if (enableShuffle) {
          shuffleNotifier.value = true;
          unawaited(Hive.box('settings').put('shuffleEnabled', true));
          await audioPlayer.setShuffleModeEnabled(true);
        } else {
          shuffleNotifier.value = false;
          unawaited(Hive.box('settings').put('shuffleEnabled', false));
          await audioPlayer.setShuffleModeEnabled(false);
        }
      }

      int? targetQueueIndex;

      for (var i = 0; i < songs.length; i++) {
        final song = songs[i];
        if (song['ytid'] != null && song['ytid'].toString().isNotEmpty) {
          _queueList.add(_queueEntryIds.createSong(song));

          if (replace && startIndex == i) {
            targetQueueIndex = _queueList.length - 1;
          }
        }
      }

      if (replace && manuallyAddedSongs.isNotEmpty) {
        // Always insert after the starting song index
        final insertIndex = (targetQueueIndex ?? 0) + 1;
        final safeInsertIndex = insertIndex > _queueList.length
            ? _queueList.length
            : insertIndex;
        _queueList.insertAll(safeInsertIndex, manuallyAddedSongs);
      }

      if (replace && enableShuffle && _queueList.length > 1) {
        final startIndexForShuffle = targetQueueIndex ?? 0;
        if (startIndexForShuffle >= 0 &&
            startIndexForShuffle < _queueList.length) {
          _currentQueueIndex = startIndexForShuffle;
        }
        _enableShuffle(const [], {});
        targetQueueIndex = 0;
      }

      _hydrateQueueEntryIds();
      _updateQueueMediaItems();

      if (targetQueueIndex != null) {
        await _playFromQueue(targetQueueIndex);
      } else if (startIndex != null &&
          startIndex < _queueList.length &&
          !replace) {
        await _playFromQueue(startIndex);
      } else if (replace && _queueList.isNotEmpty) {
        await _playFromQueue(0);
      }
    } catch (e, stackTrace) {
      logger.log(
        'Error adding playlist to queue',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> removeFromQueue(int index) async {
    try {
      if (index < 0 || index >= _queueList.length) return;

      final removedSong = _queueList[index];
      final removedQueueEntryId = _queueEntryIds.ensureId(removedSong);
      _queueList.removeAt(index);

      if (shuffleNotifier.value && _originalQueueList.isNotEmpty) {
        _originalQueueList.removeWhere(
          (s) => _queueEntryIds.ensureId(s) == removedQueueEntryId,
        );
      }

      if (index == _currentLoadingIndex) {
        _currentLoadingIndex = -1;
        _currentLoadingTransitionId = -1;
      } else if (index < _currentLoadingIndex) {
        _currentLoadingIndex--;
      }

      if (index < _currentQueueIndex) {
        _currentQueueIndex--;
      } else if (index == _currentQueueIndex) {
        if (_queueList.isEmpty) {
          await stop();
        } else {
          if (_currentQueueIndex >= _queueList.length) {
            _currentQueueIndex = _queueList.length - 1;
          }
          await _playFromQueue(_currentQueueIndex);
        }
      }

      _hydrateQueueEntryIds();
      _updateQueueMediaItems();
    } catch (e, stackTrace) {
      logger.log('Error removing from queue', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    try {
      _queueEntryIds.ensureIds(_queueList);

      if (oldIndex < 0 ||
          oldIndex >= _queueList.length ||
          newIndex < 0 ||
          newIndex > _queueList.length - 1) {
        return;
      }

      final song = _queueList.removeAt(oldIndex);
      _queueList.insert(newIndex, song);

      if (oldIndex == _currentQueueIndex) {
        _currentQueueIndex = newIndex;
      } else if (oldIndex < _currentQueueIndex &&
          newIndex >= _currentQueueIndex) {
        _currentQueueIndex--;
      } else if (oldIndex > _currentQueueIndex &&
          newIndex <= _currentQueueIndex) {
        _currentQueueIndex++;
      }

      // Also update _currentLoadingIndex if the currently-loading song is being reordered
      if (oldIndex == _currentLoadingIndex) {
        _currentLoadingIndex = newIndex;
      } else if (oldIndex < _currentLoadingIndex &&
          newIndex >= _currentLoadingIndex) {
        _currentLoadingIndex--;
      } else if (oldIndex > _currentLoadingIndex &&
          newIndex <= _currentLoadingIndex) {
        _currentLoadingIndex++;
      }

      _updateQueueMediaItems();
    } catch (e, stackTrace) {
      logger.log('Error reordering queue', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> reorderQueueById(String queueEntryId, int targetIndex) async {
    try {
      _queueEntryIds.ensureIds(_queueList);

      final oldIndex = _queueList.indexWhere(
        (s) => _queueEntryIds.ensureId(s) == queueEntryId,
      );
      if (oldIndex == -1) return;

      // Clamp target index to valid range (allow insert at end)
      if (targetIndex < 0) targetIndex = 0;
      if (targetIndex > _queueList.length) targetIndex = _queueList.length;

      final song = _queueList.removeAt(oldIndex);
      var newIndex = targetIndex;
      if (newIndex > _queueList.length) newIndex = _queueList.length;
      _queueList.insert(newIndex, song);

      if (oldIndex == _currentQueueIndex) {
        _currentQueueIndex = newIndex;
      } else if (oldIndex < _currentQueueIndex &&
          newIndex >= _currentQueueIndex) {
        _currentQueueIndex--;
      } else if (oldIndex > _currentQueueIndex &&
          newIndex <= _currentQueueIndex) {
        _currentQueueIndex++;
      }

      if (oldIndex == _currentLoadingIndex) {
        _currentLoadingIndex = newIndex;
      } else if (oldIndex < _currentLoadingIndex &&
          newIndex >= _currentLoadingIndex) {
        _currentLoadingIndex--;
      } else if (oldIndex > _currentLoadingIndex &&
          newIndex <= _currentLoadingIndex) {
        _currentLoadingIndex++;
      }

      _updateQueueMediaItems();
    } catch (e, stackTrace) {
      logger.log(
        'Error reordering queue by id',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void clearQueue() {
    try {
      final currentSong =
          _currentQueueIndex >= 0 && _currentQueueIndex < _queueList.length
          ? cloneMap(_queueList[_currentQueueIndex])
          : null;

      _queueList.clear();
      _originalQueueList.clear();

      if (currentSong != null) {
        _queueList.add(currentSong);
        _originalQueueList.add(cloneMap(currentSong));
        playbackContextNotifier.value = PlaybackContext.singleSong(
          id: currentSong['ytid']?.toString(),
          title: currentSong['title']?.toString(),
        );
      } else {
        _clearPlaybackSessionState();
      }

      _currentQueueIndex = 0;
      _currentLoadingIndex = -1;
      _currentLoadingTransitionId = -1;
      _resetPreloadingState();
      _updateQueueMediaItems();
      _updatePlaybackState();
    } catch (e, stackTrace) {
      logger.log('Error clearing queue', error: e, stackTrace: stackTrace);
    }
  }

  void _updateQueueMediaItems() {
    try {
      _queueEntryIds.ensureIds(_queueList);

      final mediaItems = _buildQueueMediaItems();
      queue.add(mediaItems);

      _queueMapStream.add(List.unmodifiable(_queueList));

      if (_currentQueueIndex < mediaItems.length) {
        final currentMediaItem = mediaItems[_currentQueueIndex];
        mediaItem.add(currentMediaItem);
      }
    } catch (e, stackTrace) {
      logger.log(
        'Error updating queue media items',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _emitOptimisticLoadingState({
    Map? song,
    int? queueIndex,
    bool includeMediaItem = false,
    String? mediaId,
  }) {
    try {
      if (includeMediaItem && song != null) {
        var immediateMediaItem = mapToMediaItem(song);
        if (mediaId != null) {
          immediateMediaItem = immediateMediaItem.copyWith(id: mediaId);
        }
        Future.microtask(() {
          mediaItem.add(immediateMediaItem);
        });
      }

      playbackState.add(
        PlaybackState(
          controls: [
            MediaControl.skipToPrevious,
            MediaControl.pause,
            MediaControl.stop,
            MediaControl.skipToNext,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 1, 3],
          processingState: AudioProcessingState.loading,
          queueIndex:
              queueIndex ??
              (_currentQueueIndex < _queueList.length
                  ? _currentQueueIndex
                  : null),
          updateTime: DateTime.now(),
        ),
      );
    } catch (e, stackTrace) {
      logger.log(
        'Error emitting optimistic loading state',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _playFromQueue(int index) async {
    if (index < 0 || index >= _queueList.length) {
      logger.log('Invalid queue index: $index');
      return;
    }

    _mediaSessionDismissed = false;

    // Ignore duplicate taps for the same index while that load is in flight.
    if (_currentLoadingIndex == index && !_completionEventPending) {
      return;
    }

    if (_currentLoadingIndex >= 0 &&
        _completionEventPending &&
        !_completionHandlerLoadStarted) {
      _completionHandlerLoadStarted = true;
    } else if (_currentLoadingIndex >= 0 &&
        _completionEventPending &&
        _completionHandlerLoadStarted) {
      return;
    }

    // Start new transition (supersedes an in-flight load for a different song)
    _songTransitionCounter++;
    final currentTransitionId = _songTransitionCounter;
    _currentLoadingIndex = index;
    _currentLoadingTransitionId = currentTransitionId;
    _setPlayRequestPending(true);
    // Avoid an immediate near-end re-trigger against the previous track's
    // duration while the next source is still loading.
    _lastNearEndCompletionAt = DateTime.now();

    try {
      final previousQueueIndex = _currentQueueIndex;
      final previousMediaItem = mediaItem.valueOrNull;
      _currentQueueIndex = index;

      final currentSong = _queueList[_currentQueueIndex];
      final currentMediaItem = _getMediaItemForQueue(currentSong);
      final uniqueId = currentMediaItem.id;

      await Future.microtask(() {
        mediaItem.add(currentMediaItem);
      });

      _emitOptimisticLoadingState(
        queueIndex: _currentQueueIndex,
        mediaId: uniqueId,
      );

      final success = await playSong(
        _queueList[index],
        mediaId: uniqueId,
        transitionId: currentTransitionId,
      );

      // Only process result if this is still the current transition
      if (currentTransitionId == _currentLoadingTransitionId) {
        if (success) {
          if (await _shouldAllowOnlinePlaybackSideEffects()) {
            _preloadUpcomingSongs();
            // When Repeat All (or Repeat One) is active the queue must loop over
            // exactly the current playlist, so never prepare/append auto-picked
            // songs — that is reserved for the "auto picker, no repeat" mode.
            if (_isAutoPickerActive) {
              if (_currentQueueIndex == _queueList.length - 1) {
                unawaited(_prepareGenreFallback());
              }
              unawaited(_backgroundAddSongsToQueue());
            }
          }
        } else {
          _currentQueueIndex = previousQueueIndex;
          if (previousMediaItem != null) {
            mediaItem.add(previousMediaItem);
          }
          _updatePlaybackState();
          _handlePlaybackError();
        }
      }
    } catch (e, stackTrace) {
      logger.log('Error playing from queue', error: e, stackTrace: stackTrace);
      if (currentTransitionId == _currentLoadingTransitionId) {
        _handlePlaybackError();
      }
    } finally {
      // Only reset if this is still the transition that started it
      if (currentTransitionId == _currentLoadingTransitionId) {
        _currentLoadingIndex = -1;
        _currentLoadingTransitionId = -1;
        _setPlayRequestPending(false);
      }
    }
  }

  void _preloadUpcomingSongs() {
    Future.microtask(() async {
      try {
        if (!await _shouldAllowOnlinePlaybackSideEffects()) return;

        final songsToPreload = <Map>[];

        for (var i = 1; i <= _queueLookahead; i++) {
          final nextIndex = _currentQueueIndex + i;
          if (nextIndex < _queueList.length) {
            final nextSong = _queueList[nextIndex];
            final ytid = nextSong['ytid'];

            if (ytid != null &&
                !isSongAlreadyOffline(ytid) &&
                !_preloadedYtIds.contains(ytid) &&
                !_preloadingYtIds.contains(ytid)) {
              songsToPreload.add(nextSong);
            }
          }
        }

        await _preloadSongsSequentially(songsToPreload);
      } catch (e, stackTrace) {
        logger.log(
          'Error in _preloadUpcomingSongs',
          error: e,
          stackTrace: stackTrace,
        );
      }
    });
  }

  Future<void> _preloadSongsSequentially(List<Map> songsToPreload) async {
    for (final song in songsToPreload) {
      while (_activePreloadCount >= _maxConcurrentPreloads) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final ytid = song['ytid'];
      if (ytid == null || _preloadingYtIds.contains(ytid)) {
        continue;
      }

      unawaited(_preloadSingleSongControlled(song));
    }
  }

  Future<void> _preloadSingleSongControlled(Map nextSong) async {
    final ytid = nextSong['ytid'];
    if (ytid == null) return;

    _preloadingYtIds.add(ytid);
    _activePreloadCount++;
    String? preloadUrl;

    try {
      if (!await _shouldAllowOnlinePlaybackSideEffects()) {
        logger.log('Skipping online preload for $ytid');
        preloadUrl = null;
      } else {
        // fetchSongStreamUrl handles caching, freshness checks, and validation
        preloadUrl = await fetchSongStreamUrl(ytid, nextSong['isLive'] ?? false)
            .timeout(
              const Duration(seconds: 8),
              onTimeout: () {
                logger.log('Preload timeout for song $ytid');
                return null;
              },
            );
      }
    } catch (e, stackTrace) {
      logger.log(
        'Error preloading song $ytid',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _preloadingYtIds.remove(ytid);
      if (_activePreloadCount > 0) {
        _activePreloadCount--;
      }
      if (preloadUrl != null && preloadUrl.isNotEmpty) {
        _preloadedYtIds.add(ytid);
      }
    }
  }

  Stream<List<Map>> get queueAsMapStream => _queueMapStream.stream;
  int get currentQueueIndex => _currentQueueIndex;
  PlaybackContext get playbackContext => playbackContextNotifier.value;
  Map? get currentSong =>
      _currentQueueIndex >= 0 && _currentQueueIndex < _queueList.length
      ? _queueList[_currentQueueIndex]
      : null;

  bool get hasNext => _currentQueueIndex < _queueList.length - 1;

  bool get hasPrevious => _currentQueueIndex > 0 || _historyList.isNotEmpty;

  String _recentMediaId(String ytid) => '$_recentMediaIdPrefix$ytid';

  String? _ytidFromMediaId(String mediaId) {
    if (mediaId.startsWith(_recentMediaIdPrefix)) {
      return mediaId.substring(_recentMediaIdPrefix.length);
    }
    return mediaId.isEmpty ? null : mediaId;
  }

  String? _songYtid(Map song) {
    final ytid = song['ytid']?.toString();
    return ytid == null || ytid.isEmpty ? null : ytid;
  }

  Map? _firstPlayableSong(Iterable songs) {
    for (final song in songs.whereType<Map>()) {
      if (_songYtid(song) != null) {
        return song;
      }
    }
    return null;
  }

  Map? _findSongInList(Iterable songs, String ytid) {
    for (final song in songs.whereType<Map>()) {
      if (_songYtid(song) == ytid) {
        return song;
      }
    }
    return null;
  }

  Map? _findSongByYtid(String? ytid) {
    if (ytid == null || ytid.isEmpty) return null;

    final activeSong = currentSong;
    if (activeSong?['ytid']?.toString() == ytid) {
      return activeSong;
    }

    for (final source in [
      _queueList,
      userRecentlyPlayed.value,
      userOfflineSongs.value,
      userLikedSongsList.value,
    ]) {
      final song = _findSongInList(source, ytid);
      if (song != null) return song;
    }

    return null;
  }

  Map? _latestResumableSong() {
    final activeSong = currentSong;
    if (activeSong != null && _songYtid(activeSong) != null) {
      return activeSong;
    }

    final activeMediaItem = mediaItem.valueOrNull;
    final activeYtid = activeMediaItem?.extras?['ytid']?.toString();
    final activeMediaSong = _findSongByYtid(activeYtid);
    if (activeMediaSong != null) return activeMediaSong;
    if (activeYtid != null &&
        activeYtid.isNotEmpty &&
        activeMediaItem != null) {
      return mediaItemToMap(activeMediaItem);
    }

    return _firstPlayableSong(userRecentlyPlayed.value) ??
        _firstPlayableSong(userOfflineSongs.value) ??
        _firstPlayableSong(userLikedSongsList.value);
  }

  Map<String, dynamic>? _normaliseResumableSong(Map song) {
    final ytid = _songYtid(song);
    if (ytid == null) return null;

    final normalised = cloneMap(song);
    normalised['id'] = ytid;
    normalised['ytid'] = ytid;
    normalised['highResImage'] ??=
        normalised['image'] ?? normalised['lowResImage'] ?? '';
    normalised['lowResImage'] ??= normalised['highResImage'];
    normalised['isLive'] ??= false;
    return normalised;
  }

  MediaItem? _mediaItemForResumption(Map song) {
    final normalisedSong = _normaliseResumableSong(song);
    if (normalisedSong == null) return null;

    final ytid = normalisedSong['ytid'].toString();
    final artist = normalisedSong['artist']?.toString().trim() ?? '';
    return mapToMediaItem(normalisedSong).copyWith(
      id: _recentMediaId(ytid),
      displayTitle: normalisedSong['title']?.toString(),
      displaySubtitle: artist.isEmpty ? 'WiyaMusic' : artist,
    );
  }

  Future<void> _playResumableSong(Map song) async {
    final normalisedSong = _normaliseResumableSong(song);
    if (normalisedSong == null) return;

    await playPlaylistSong(
      playlist: {
        'title': 'WiyaMusic',
        'source': 'system-recent',
        'list': [normalisedSong],
      },
      songIndex: 0,
    );
  }

  static const _rootLiked = 'liked_songs';
  static const _rootOffline = 'offline_songs';
  static const _rootRecent = 'recently_played';
  static const _rootQueue = 'current_queue';

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    if (parentMediaId == AudioService.recentRootId) {
      final recentSong = _latestResumableSong();
      final recentItem = recentSong == null
          ? null
          : _mediaItemForResumption(recentSong);
      return recentItem == null ? [] : [recentItem];
    }

    if (parentMediaId == AudioService.browsableRootId) {
      return [
        const MediaItem(
          id: _rootQueue,
          title: 'Now Playing Queue',
          playable: false,
          extras: {'isBrowsable': true},
        ),
        const MediaItem(
          id: _rootLiked,
          title: 'Liked Songs',
          playable: false,
          extras: {'isBrowsable': true},
        ),
        const MediaItem(
          id: _rootOffline,
          title: 'Downloaded',
          playable: false,
          extras: {'isBrowsable': true},
        ),
        const MediaItem(
          id: _rootRecent,
          title: 'Recently Played',
          playable: false,
          extras: {'isBrowsable': true},
        ),
      ];
    }

    switch (parentMediaId) {
      case _rootQueue:
        return _queueList.map(_getMediaItemForQueue).toList();
      case _rootLiked:
        return userLikedSongsList.value
            .whereType<Map>()
            .map((s) => mapToMediaItem(s).copyWith(playable: true))
            .toList();
      case _rootOffline:
        return userOfflineSongs.value
            .whereType<Map>()
            .map((s) => mapToMediaItem(s).copyWith(playable: true))
            .toList();
      case _rootRecent:
        return userRecentlyPlayed.value
            .whereType<Map>()
            .map((s) => mapToMediaItem(s).copyWith(playable: true))
            .toList();
      default:
        return [];
    }
  }

  @override
  Future<void> playFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    if (query.trim().isEmpty) {
      // "Play music" with no specifics
      if (_queueList.isNotEmpty) {
        await play();
        return;
      }
      final recentSong = _latestResumableSong();
      if (recentSong != null) await _playResumableSong(recentSong);
      return;
    }

    final q = query.toLowerCase();
    final candidates = [
      ..._queueList,
      ...userLikedSongsList.value.whereType<Map>(),
      ...userOfflineSongs.value.whereType<Map>(),
      ...userRecentlyPlayed.value.whereType<Map>(),
    ];

    final match = candidates.firstWhere((s) {
      final title = s['title']?.toString().toLowerCase() ?? '';
      final artist = s['artist']?.toString().toLowerCase() ?? '';
      return title.contains(q) || artist.contains(q);
    }, orElse: () => const {});

    if (match.isNotEmpty) {
      await _playResumableSong(match);
    } else {
      logger.log('playFromSearch: no local match for "$query"');
    }
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final song = _findSongByYtid(_ytidFromMediaId(mediaId));
    return song == null ? null : _mediaItemForResumption(song);
  }

  @override
  Future<void> prepareFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final item = await getMediaItem(mediaId);
    if (item == null) return;

    _mediaSessionDismissed = false;
    mediaItem.add(item);
    queue.add([item]);
    playbackState.add(
      PlaybackState(
        controls: _controls(false),
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: AudioProcessingState.ready,
        queueIndex: 0,
        updateTime: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final song = _findSongByYtid(_ytidFromMediaId(mediaId));
    if (song == null) {
      logger.log('No resumable song found for media id: $mediaId');
      return;
    }
    await _playResumableSong(song);
  }

  @override
  Future<void> onTaskRemoved() async {
    try {
      await stop();
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (e, stackTrace) {
      logger.log('Error in onTaskRemoved', error: e, stackTrace: stackTrace);
    }
    await super.onTaskRemoved();
  }

  @override
  Future<void> onNotificationDeleted() async {
    // Swipe-away of the system media notification (Android).
    await stop();
  }

  @override
  Future<void> play() async {
    _mediaSessionDismissed = false;
    try {
      // Ignore rapid Play taps while a stream request is already in flight.
      if (isPlayRequestPending.value) {
        logger.log('Ignoring play(); a playback request is already pending');
        return;
      }

      if (audioPlayer.audioSource == null) {
        final recentSong = _latestResumableSong();
        if (recentSong != null) {
          await _playResumableSong(recentSong);
          return;
        }
      }
      // Do NOT await play(): its future only completes when playback pauses/
      // stops/finishes (just_audio semantics), which would defer the resume
      // below until the song ended - losing the whole session.
      unawaited(
        audioPlayer.play().catchError((Object e, StackTrace stackTrace) {
          logger.log(
            'Error starting playback',
            error: e,
            stackTrace: stackTrace,
          );
          _lastError = e.toString();
          _handlePlaybackError();
        }),
      );
      listeningStatsService.resumeListeningSession(currentSong: currentSong);
    } catch (e, stackTrace) {
      logger.log('Error in play()', error: e, stackTrace: stackTrace);
      _lastError = e.toString();
      _handlePlaybackError();
    }
  }

  @override
  Future<void> pause() async {
    try {
      listeningStatsService.recordListeningSessionProgress(
        wasPlaying: audioPlayer.playing,
      );
      unawaited(listeningStatsService.flush());
      await audioPlayer.pause();
    } catch (e, stackTrace) {
      logger.log('Error in pause()', error: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> stop() async {
    _debounceTimer?.cancel();
    _completionEventPending = false;
    _completionHandlerLoadStarted = false;
    _currentLoadingIndex = -1;
    _currentLoadingTransitionId = -1;
    _lastError = null;
    _setPlayRequestPending(false);
    _preparedGenreFallback = null;
    _preparedGenreFallbackSeedId = null;
    _genreFallbackPreparation = null;
    _mediaSessionDismissed = true;
    _pendingPlaybackStateUpdate = false;

    // Clear session first so player-stop events cannot revive the notification.
    _queueList.clear();
    _originalQueueList.clear();
    _currentQueueIndex = 0;
    _currentLoadingIndex = -1;
    _currentLoadingTransitionId = -1;
    _resetPreloadingState();
    _clearPlaybackSessionState();
    queue.add([]);
    _queueMapStream.add(const []);
    mediaItem.add(null);

    // Drop to paused+non-idle first when needed so Android can leave the
    // foreground service before we cancel the notification (required for
    // androidStopForegroundOnPause + cancel to work on modern Android).
    final wasPlaying =
        playbackState.valueOrNull?.playing ?? audioPlayer.playing;
    if (wasPlaying) {
      playbackState.add(
        PlaybackState(
          controls: const [],
          systemActions: const {},
          processingState: AudioProcessingState.ready,
          playing: false,
        ),
      );
    }

    playbackState.add(
      PlaybackState(
        controls: const [],
        systemActions: const {},
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );

    try {
      listeningStatsService.finishListeningSession(
        countCurrentTick: true,
        wasPlaying: audioPlayer.playing,
      );
      await audioPlayer.stop();
    } catch (e, stackTrace) {
      logger.log('Error in stop()', error: e, stackTrace: stackTrace);
    }

    await super.stop();
  }

  /// Stops playback and clears the current media so the mini player hides.
  Future<void> dismissPlayer() => stop();

  /// Auto picker only generates/appends recommended songs when Repeat is off.
  /// Under Repeat All/One the queue must loop over exactly the current playlist.
  bool get _isAutoPickerActive =>
      playNextSongAutomatically.value &&
      repeatNotifier.value == AudioServiceRepeatMode.none;

  /// Removes recommended (auto-picked) songs so the queue holds only the
  /// original playlist. The currently playing track is preserved even if it
  /// was auto-picked, so enabling Repeat All never interrupts playback.
  void _removeAutoPickedSongs() {
    if (_queueList.isEmpty) return;

    final currentId = _currentQueueIndex >= 0 &&
            _currentQueueIndex < _queueList.length
        ? _queueEntryIds.ensureId(_queueList[_currentQueueIndex])
        : null;

    var removed = false;
    final retained = <Map>[];
    for (final song in _queueList) {
      final isCurrent =
          currentId != null && _queueEntryIds.ensureId(song) == currentId;
      if (song['isAutoPicked'] == true && !isCurrent) {
        removed = true;
        continue;
      }
      retained.add(song);
    }

    if (!removed) return;

    _queueList
      ..clear()
      ..addAll(retained);

    if (currentId != null) {
      final newIndex = _queueList.indexWhere(
        (song) => _queueEntryIds.ensureId(song) == currentId,
      );
      _currentQueueIndex = newIndex == -1 ? 0 : newIndex;
    } else if (_currentQueueIndex >= _queueList.length) {
      _currentQueueIndex = _queueList.isEmpty ? 0 : _queueList.length - 1;
    }

    // Auto-picked songs also feed the pre-shuffle snapshot; drop them there too.
    if (_originalQueueList.isNotEmpty) {
      _originalQueueList.removeWhere((song) => song['isAutoPicked'] == true);
    }

    _preparedGenreFallback = null;
    _preparedGenreFallbackSeedId = null;
    _updateQueueMediaItems();
  }

  /// Returns unplayed manually added songs after the current queue index.
  List<Map> _getUnplayedManualSongs() {
    return _queueList
        .skip(_currentQueueIndex >= 0 ? _currentQueueIndex + 1 : 0)
        .where(
          (song) =>
              song['isManuallyAdded'] == true && song['isAutoPicked'] != true,
        )
        .toList();
  }

  void _resetPreloadingState() {
    _activePreloadCount = 0;
    _preloadingYtIds.clear();
    _preloadedYtIds.clear();
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      listeningStatsService.recordListeningSessionProgress(
        wasPlaying: audioPlayer.playing,
      );
      await audioPlayer.seek(position);
      unawaited(listeningStatsService.flush());
    } catch (e, stackTrace) {
      logger.log('Error in seek()', error: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> fastForward() {
    final target = audioPlayer.position + const Duration(seconds: 15);
    final trackDuration = audioPlayer.duration;
    final clamped = (trackDuration != null && target > trackDuration)
        ? trackDuration
        : target;
    return seek(clamped);
  }

  @override
  Future<void> rewind() {
    final target = audioPlayer.position - const Duration(seconds: 15);
    final clamped = target < Duration.zero ? Duration.zero : target;
    return seek(clamped);
  }

  Future<bool> _resolveOfflineAndSetPaths(Map songData) async {
    try {
      final ytid = songData['ytid']?.toString();
      if (ytid == null || ytid.isEmpty) return false;

      final offlineSong = getOfflineSongByYtid(ytid);
      final storedAudioPath =
          offlineSong['audioPath']?.toString() ??
          songData['audioPath']?.toString();

      // Downloaded songs must resolve against the current app container path.
      // Stale absolute paths (common on iOS after updates) previously made
      // offline tracks look missing and forced a googlevideo stream fallback.
      if (offlineSong.isNotEmpty ||
          (storedAudioPath != null && storedAudioPath.isNotEmpty)) {
        final audioPath = await FilePaths.resolveExistingAudioPath(
          ytid,
          storedPath: storedAudioPath,
        );
        if (audioPath != null) {
          songData['audioPath'] = audioPath;

          final artworkPath = await FilePaths.resolveExistingArtworkPath(
            ytid,
            storedPath:
                offlineSong['artworkPath']?.toString() ??
                songData['artworkPath']?.toString(),
          );
          if (artworkPath != null) {
            songData['artworkPath'] = artworkPath;
          }

          if (offlineSong.isNotEmpty) {
            unawaited(
              repairOfflineSongPathsForYtid(
                ytid,
                audioPath: audioPath,
                artworkPath: artworkPath,
              ),
            );
          }
          return true;
        }
      }
    } catch (e, st) {
      logger.log(
        'Error while checking offline songs',
        error: e,
        stackTrace: st,
      );
    }

    return false;
  }

  /// Check if the given transitionId is stale (outdated by a newer request).
  bool _isStaleTransition(int? transitionId) {
    return transitionId != null && transitionId != _currentLoadingTransitionId;
  }

  Future<bool> playSong(Map song, {String? mediaId, int? transitionId}) async {
    // Direct play calls (no queue transition) own their transition lock.
    // Always create a new transition so a user tap can supersede a slow
    // in-flight resolve (no internet / slow CDN) instead of being ignored.
    final ownsRequestLock = transitionId == null;

    if (ownsRequestLock) {
      _songTransitionCounter++;
      transitionId = _songTransitionCounter;
      _currentLoadingTransitionId = transitionId;
      _setPlayRequestPending(true);
    }

    try {
      final songData = cloneMap(song);

      if (songData['ytid'] == null || songData['ytid'].toString().isEmpty) {
        logger.log('Invalid song data: missing ytid');
        _lastError = 'Invalid song data';
        return false;
      }

      _lastError = null;
      if (audioPlayer.playing) {
        listeningStatsService.recordListeningSessionProgress(
          wasPlaying: audioPlayer.playing,
        );
        await audioPlayer.pause();
      }

      // Show loading immediately so rapid taps see a disabled Play state
      // before the stream URL network call returns.
      _emitOptimisticLoadingState(
        song: songData,
        includeMediaItem: true,
        mediaId: mediaId,
      );

      final playback = await _resolvePlaybackSource(songData);

      // Abort if a newer song was requested while we were fetching the stream URL.
      // This is the primary guard against the race condition where a slow streaming
      // load overrides a song the user already switched to.
      if (_isStaleTransition(transitionId)) {
        logger.log(
          'Song load superseded by newer request, aborting: ${songData['ytid']}',
        );
        return false;
      }

      if (playback == null) {
        _lastError = 'Failed to get song URL';
        if (ownsRequestLock) {
          _updatePlaybackState();
          _handlePlaybackError();
        }
        return false;
      }

      final audioSource = await buildAudioSource(
        songData,
        playback.songUrl,
        playback.isOffline,
        headers: playback.headers,
      );

      // Check again after building the audio source (SponsorBlock fetch can also be slow).
      if (_isStaleTransition(transitionId)) {
        logger.log(
          'Song load superseded after building audio source, aborting: ${songData['ytid']}',
        );
        return false;
      }

      if (audioSource == null) {
        logger.log('Failed to build audio source for ${songData['ytid']}');
        _lastError = 'Failed to build audio source';
        if (ownsRequestLock) {
          _updatePlaybackState();
          _handlePlaybackError();
        }
        return false;
      }

      final success = await _setAudioSourceAndPlay(
        songData,
        audioSource,
        playback.songUrl,
        playback.isOffline,
        mediaId: mediaId,
        transitionId: transitionId,
      );

      if (!success &&
          ownsRequestLock &&
          !_isStaleTransition(transitionId) &&
          _lastError != null) {
        _updatePlaybackState();
        _handlePlaybackError();
      }

      return success;
    } catch (e, stackTrace) {
      logger.log('Error playing song', error: e, stackTrace: stackTrace);
      _lastError = e.toString();
      if (ownsRequestLock && !_isStaleTransition(transitionId)) {
        _updatePlaybackState();
        _handlePlaybackError();
      }
      return false;
    } finally {
      if (ownsRequestLock && transitionId == _currentLoadingTransitionId) {
        _currentLoadingTransitionId = -1;
        _setPlayRequestPending(false);
      }
    }
  }

  Future<_PlaybackSource?> _resolvePlaybackSource(Map songData) async {
    final isOffline = await _resolveOfflineAndSetPaths(songData);
    final allowOnline = await _shouldAllowOnlinePlaybackSideEffects(
      forceRefresh: true,
    );

    if (isOffline) {
      final path = await _getOfflineSongUrl(songData);
      if (path != null && path.isNotEmpty) {
        return _PlaybackSource(
          songUrl: path,
          isOffline: true,
          headers: const {},
        );
      }

      if (!allowOnline) {
        logger.log(
          'Offline file missing and no internet for ${songData['ytid']}',
        );
        return null;
      }

      logger.log(
        'Offline file missing for ${songData['ytid']}, switching to online',
      );
    } else if (!allowOnline) {
      logger.log(
        'No local file and no internet for ${songData['ytid']}; skipping online stream',
      );
      return null;
    }

    final online = await resolveSongStream(
      songData['ytid'],
      songData['isLive'] ?? false,
    );

    if (online == null || online.url.isEmpty) {
      logger.log('Failed to get song URL for ${songData['ytid']}');
      return null;
    }

    return _PlaybackSource(
      songUrl: online.url,
      isOffline: false,
      headers: online.headers,
    );
  }

  Future<String?> _getOfflineSongUrl(Map song) async {
    final ytid = song['ytid']?.toString();
    if (ytid == null || ytid.isEmpty) {
      logger.log('Missing ytid for offline song');
      return null;
    }

    final resolved = await FilePaths.resolveExistingAudioPath(
      ytid,
      storedPath: song['audioPath']?.toString(),
    );
    if (resolved != null) {
      song['audioPath'] = resolved;
      return resolved;
    }

    logger.log('Offline audio file not found for $ytid');
    return null;
  }

  Future<bool> _setAudioSourceAndPlay(
    Map song,
    AudioSource audioSource,
    String songUrl,
    bool isOffline, {
    String? mediaId,
    int? transitionId,
    bool allowFreshUrlRetry = true,
  }) async {
    try {
      // Final staleness check before we touch the audio player.
      // If another song was requested between the URL fetch and here, abort.
      if (_isStaleTransition(transitionId)) {
        return false;
      }

      // Snapshot the pre-swap playing state now: by the time we're committed
      // to this transition (below), audioPlayer.playing reflects the new
      // source, not whatever session we're about to finish.
      final wasPlayingBeforeSwap = audioPlayer.playing;

      await audioPlayer
          .setAudioSource(audioSource)
          .timeout(_songTransitionTimeout);

      // Check once more after the async setAudioSource: a fast offline song
      // could have loaded and started playing while we were buffering/setting up.
      // If so, stop the source we just loaded and yield to the newer song.
      if (_isStaleTransition(transitionId)) {
        unawaited(audioPlayer.stop());
        return false;
      }

      if (audioPlayer.duration != null) {
        _updateCurrentMediaItemWithDuration(audioPlayer.duration!);
      }

      // Finish the old session and start the new one as one atomic pair, only
      // after every abort path above is cleared. Finishing before the staleness
      // re-check let a stale transition kill a newer transition's session.
      listeningStatsService
        ..finishListeningSession(
          countCurrentTick: true,
          wasPlaying: wasPlayingBeforeSwap,
        )
        ..startListeningSession(song, duration: audioPlayer.duration);

      // Do NOT await play(): its future only completes when playback pauses/
      // stops/finishes. Awaiting it would leave isPlayRequestPending stuck true
      // for the whole song (spinner never clears).
      unawaited(
        audioPlayer.play().catchError((Object e, StackTrace stackTrace) {
          logger.log(
            'Error starting playback',
            error: e,
            stackTrace: stackTrace,
          );
          _lastError = e.toString();
        }),
      );
      unawaited(updateRecentlyPlayed(song['ytid'], songFallback: song));

      _updatePlaybackState();

      if (!isOffline) {
        Future.delayed(const Duration(seconds: 2), _preloadUpcomingSongs);
      }

      return true;
    } catch (e, stackTrace) {
      logger.log(
        'Error setting audio source',
        error: e,
        stackTrace: stackTrace,
      );

      if (isOffline) {
        // If offline mode is explicitly enabled, do not attempt any online
        // fallback — respect the user's offline-only preference.
        if (offlineMode.value ||
            !await _shouldAllowOnlinePlaybackSideEffects(forceRefresh: true)) {
          return false;
        }

        return _attemptOfflineFallback(
          song,
          mediaId: mediaId,
          transitionId: transitionId,
        );
      }

      // One refresh within this same user Play tap for expired/403 CDN URLs.
      // Does not skip to another song or loop.
      if (allowFreshUrlRetry &&
          !offlineMode.value &&
          !_isStaleTransition(transitionId) &&
          await _shouldAllowOnlinePlaybackSideEffects()) {
        final songId = song['ytid']?.toString();
        if (songId != null && songId.isNotEmpty) {
          final refreshed = await resolveSongStream(
            songId,
            song['isLive'] ?? false,
            bypassCache: true,
          );

          if (refreshed != null &&
              refreshed.url.isNotEmpty &&
              refreshed.url != songUrl) {
            final refreshedSource = await buildAudioSource(
              song,
              refreshed.url,
              false,
              headers: refreshed.headers,
            );

            if (refreshedSource != null) {
              return _setAudioSourceAndPlay(
                song,
                refreshedSource,
                refreshed.url,
                false,
                mediaId: mediaId,
                transitionId: transitionId,
                allowFreshUrlRetry: false,
              );
            }
          }
        }
      }

      _lastError = e.toString();
      return false;
    }
  }

  Future<bool> _attemptOfflineFallback(
    Map song, {
    String? mediaId,
    int? transitionId,
  }) async {
    // Do not attempt any network calls when offline mode is enabled or the
    // device has no internet.
    if (!await _shouldAllowOnlinePlaybackSideEffects(forceRefresh: true)) {
      return false;
    }

    final online = await resolveSongStream(
      song['ytid'],
      song['isLive'] ?? false,
    );
    if (online != null && online.url.isNotEmpty) {
      final onlineSource = await buildAudioSource(
        song,
        online.url,
        false,
        headers: online.headers,
      );
      if (onlineSource != null) {
        return _setAudioSourceAndPlay(
          song,
          onlineSource,
          online.url,
          false,
          mediaId: mediaId,
          transitionId: transitionId,
        );
      }
    }
    return false;
  }

  Future<void> playNext(Map song) async {
    await addToQueue(song, playNext: true);
  }

  Future<void> playPlaylistSong({
    Map<dynamic, dynamic>? playlist,
    required int songIndex,
    PlaybackContext? context,
    bool enableShuffle = false,
  }) async {
    try {
      if (playlist != null && playlist['list'] != null) {
        final genre = _genreFromPlaylist(playlist);
        final songs = List<Map>.from(playlist['list']).map((song) {
          if (genre == null || genre.isEmpty || song['genre'] != null) {
            return song;
          }
          return <dynamic, dynamic>{...song, 'genre': genre};
        }).toList();

        final resolved = PlaybackContext.resolve(
          playlist: Map<dynamic, dynamic>.from(playlist),
          explicit: context,
        );

        await addPlaylistToQueue(
          songs,
          replace: true,
          startIndex: songIndex,
          context: resolved,
          enableShuffle: enableShuffle,
        );
      }
    } catch (e, stackTrace) {
      logger.log('Error playing playlist', error: e, stackTrace: stackTrace);
    }
  }

  /// Play a radio stream directly without queue management
  Future<bool> playRadioStream({
    required String id,
    required String name,
    required String streamUrl,
    required String image,
    String? genre,
  }) async {
    if (isPlayRequestPending.value) {
      logger.log(
        'Ignoring playRadioStream; a playback request is already pending',
      );
      return false;
    }

    _setPlayRequestPending(true);
    try {
      // Create a song-like map for the radio stream
      final radioSong = {
        'id': id,
        'ytid': id, // Use radio ID as ytid for compatibility
        'title': name,
        'artist': genre ?? 'Radio Station',
        'album': 'Live Stream',
        'highResImage': image,
        'lowResImage': image,
        'duration': null, // Radio streams are live
        'isLive': true,
      };

      _lastError = null;
      if (audioPlayer.playing) {
        listeningStatsService.recordListeningSessionProgress(
          wasPlaying: audioPlayer.playing,
        );
        await audioPlayer.pause();
      }

      await _applyPlaybackContext(
        PlaybackContext.radio(id: id, title: name),
        replacingQueue: true,
      );
      _queueList
        ..clear()
        ..add(_queueEntryIds.createSong(radioSong));
      _originalQueueList.clear();
      _currentQueueIndex = 0;

      // Update media item and queue for mini player visibility
      final mediaItem = mapToMediaItem(radioSong);
      this.mediaItem.add(mediaItem);
      queue.add([mediaItem]);
      _emitOptimisticLoadingState(song: radioSong, includeMediaItem: true);

      // Build audio source from stream URL
      final audioSource = await buildAudioSource(
        radioSong,
        streamUrl,
        false, // Radio streams are always online
      );

      if (audioSource == null) {
        logger.log('Failed to build audio source for radio stream: $id');
        _lastError = 'Failed to load radio stream';
        _updatePlaybackState();
        _handlePlaybackError();
        return false;
      }

      // Play the radio stream
      final wasPlayingBeforeSwap = audioPlayer.playing;

      await audioPlayer
          .setAudioSource(audioSource)
          .timeout(_songTransitionTimeout);

      listeningStatsService.finishListeningSession(
        countCurrentTick: true,
        wasPlaying: wasPlayingBeforeSwap,
      );

      // Same as song playback: do not await play() or the request lock sticks.
      unawaited(
        audioPlayer.play().catchError((Object e, StackTrace stackTrace) {
          logger.log(
            'Error starting radio playback',
            error: e,
            stackTrace: stackTrace,
          );
          _lastError = e.toString();
        }),
      );

      _updatePlaybackState();
      return true;
    } catch (e, stackTrace) {
      logger.log(
        'Error playing radio stream',
        error: e,
        stackTrace: stackTrace,
      );
      _lastError = e.toString();
      _updatePlaybackState();
      _handlePlaybackError();
      return false;
    } finally {
      _setPlayRequestPending(false);
    }
  }

  Future<AudioSource?> buildAudioSource(
    Map song,
    String songUrl,
    bool isOffline, {
    Map<String, String>? headers,
  }) async {
    try {
      final tag = mapToMediaItem(song);

      if (isOffline) {
        return AudioSource.file(songUrl, tag: tag);
      }

      final uri = Uri.parse(songUrl);
      final audioSource = AudioSource.uri(
        uri,
        headers: headers ?? youtubeStreamHeaders,
        tag: tag,
      );

      if (!sponsorBlockSupport.value) {
        return audioSource;
      }

      final spbAudioSource = await checkIfSponsorBlockIsAvailable(
        audioSource,
        song['ytid'],
      );
      return spbAudioSource ?? audioSource;
    } catch (e, stackTrace) {
      logger.log(
        'Error building audio source',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<AudioSource?> checkIfSponsorBlockIsAvailable(
    UriAudioSource audioSource,
    String songId,
  ) async {
    try {
      final segments = await getSkipSegments(songId);
      if (segments.isEmpty) return null;

      // Sort segments by start time
      segments.sort((a, b) => (a['start'] ?? 0).compareTo(b['start'] ?? 0));

      final children = <AudioSource>[];
      var lastEnd = 0;

      for (final segment in segments) {
        final start = segment['start'] ?? 0;
        final end = segment['end'] ?? 0;

        // Add the "good" part before this sponsor segment
        if (start > lastEnd) {
          children.add(
            ClippingAudioSource(
              child: audioSource,
              start: Duration(seconds: lastEnd),
              end: Duration(seconds: start),
            ),
          );
        }

        // Advance lastEnd, handling overlapping segments
        if (end > lastEnd) {
          lastEnd = end;
        }
      }

      // Add the final part from the last sponsor segment to the end of the song
      children.add(
        ClippingAudioSource(
          child: audioSource,
          start: Duration(seconds: lastEnd),
          // end: null means play until the end of the file
        ),
      );

      if (children.length == 1) {
        return children.first;
      }

      // ignore: deprecated_member_use
      return ConcatenatingAudioSource(children: children);
    } catch (e, stackTrace) {
      logger.log(
        'Error checking sponsor block',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> skipToSong(int newIndex) async {
    try {
      if (newIndex < 0 || newIndex >= _queueList.length) {
        logger.log('Invalid song index: $newIndex');
        return;
      }
      await _playFromQueue(newIndex);
    } catch (e, stackTrace) {
      logger.log('Error skipping to song', error: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) => skipToSong(index);

  @override
  Future<void> skipToNext() async {
    try {
      final allowOnline = await _shouldAllowOnlinePlaybackSideEffects(
        forceRefresh: true,
      );
      final wrap = repeatNotifier.value == AudioServiceRepeatMode.all;

      if (!allowOnline) {
        final nextOffline = await _findOfflinePlayableIndex(
          fromIndex: _currentQueueIndex,
          direction: 1,
          wrap: wrap,
        );
        if (nextOffline != null) {
          await _playFromQueue(nextOffline);
        } else if (!wrap) {
          // No internet + queue repeat disabled → seamless offline shuffle cycle.
          final started = await _startOfflineShuffleFallback();
          if (!started) {
            logger.log('No offline songs available to play next');
          }
        } else {
          logger.log('No offline songs available to play next');
        }
        _cleanupOldPreloadedSongs();
        return;
      }

      if (_currentQueueIndex < _queueList.length - 1) {
        await _playFromQueue(_currentQueueIndex + 1);
      } else if (wrap && _queueList.isNotEmpty) {
        // Repeat All: loop back to the first song of the current playlist.
        // Never append recommended songs here.
        await _playFromQueue(0);
      } else if (_isAutoPickerActive && _currentLoadingIndex == -1) {
        // Auto picker (no repeat): append a recommended/related song. If that
        // fails, fall back to a same-genre pick.
        final addedRelatedSong = await _backgroundAddSongsToQueue();
        if (!addedRelatedSong) {
          await _playGenreFallbackAtQueueEnd();
        } else if (_currentQueueIndex < _queueList.length - 1 &&
            !audioPlayer.playing) {
          // Related song was queued but not started (common on iOS when
          // ProcessingState.completed never sticks). Advance into it.
          await _playFromQueue(_currentQueueIndex + 1);
        }
      }
      // Auto picker OFF + Repeat OFF: stop at the end of the queue.

      _cleanupOldPreloadedSongs();
    } catch (e, stackTrace) {
      logger.log(
        'Error skipping to next song',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> skipToPrevious() async {
    try {
      final allowOnline = await _shouldAllowOnlinePlaybackSideEffects(
        forceRefresh: true,
      );

      if (!allowOnline) {
        final previousOffline = await _findOfflinePlayableIndex(
          fromIndex: _currentQueueIndex,
          direction: -1,
          wrap: repeatNotifier.value == AudioServiceRepeatMode.all,
        );
        if (previousOffline != null) {
          await _playFromQueue(previousOffline);
        } else if (_historyList.isNotEmpty) {
          // Only restore history items that are playable offline.
          for (var i = 0; i < _historyList.length; i++) {
            final candidate = _historyList[i];
            if (await _canPlaySongWithoutNetwork(candidate)) {
              final song = cloneMap(_historyList.removeAt(i));
              _queueList.insert(0, song);
              _currentQueueIndex = 0;
              _updateQueueMediaItems();
              await _playFromQueue(0);
              break;
            }
          }
        } else {
          logger.log('No offline songs available to play previous');
        }
        _cleanupOldPreloadedSongs();
        return;
      }

      if (_currentQueueIndex > 0) {
        await _playFromQueue(_currentQueueIndex - 1);
      } else if (repeatNotifier.value == AudioServiceRepeatMode.all &&
          _queueList.isNotEmpty) {
        // Stay inside the collection: wrap to the last track.
        await _playFromQueue(_queueList.length - 1);
      } else if (_historyList.isNotEmpty) {
        final lastSong = cloneMap(_historyList.removeLast());
        _queueList.insert(0, lastSong);
        _currentQueueIndex = 0;
        _updateQueueMediaItems();
        await _playFromQueue(0);
      }

      _cleanupOldPreloadedSongs();
    } catch (e, stackTrace) {
      logger.log(
        'Error skipping to previous song',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> playAgain() async {
    try {
      listeningStatsService.finishListeningSession(
        countCurrentTick: true,
        wasPlaying: audioPlayer.playing,
      );
      await audioPlayer.seek(Duration.zero);
      final song = currentSong;
      if (song != null) {
        listeningStatsService.startListeningSession(
          song,
          duration: audioPlayer.duration,
        );
        unawaited(updateRecentlyPlayed(song['ytid'], songFallback: song));
      }
    } catch (e, stackTrace) {
      logger.log('Error playing again', error: e, stackTrace: stackTrace);
    }
  }

  Map<Map, String> _buildIdMap(List<Map> songs) {
    return {for (final song in songs) song: _queueEntryIds.ensureId(song)};
  }

  void _enableShuffle(
    List<Map> unplayedManualSongs,
    Set<String> manualSongIds,
  ) {
    _originalQueueList
      ..clear()
      ..addAll(cloneMaps(_queueList));

    final currentSong = _queueList[_currentQueueIndex];
    final currentQueueEntryId = _queueEntryIds.ensureId(currentSong);

    final queueIdMap = _buildIdMap(_queueList);
    _queueList
      ..removeWhere((song) => manualSongIds.contains(queueIdMap[song]))
      ..shuffle();

    final newCurrentIndex = _queueList.indexWhere(
      (song) => _queueEntryIds.ensureId(song) == currentQueueEntryId,
    );

    if (newCurrentIndex != -1 && newCurrentIndex != 0) {
      _queueList
        ..removeAt(newCurrentIndex)
        ..insert(0, currentSong);
    }

    _queueList.insertAll(_queueList.isNotEmpty ? 1 : 0, unplayedManualSongs);

    _currentQueueIndex = 0;
    _updateQueueMediaItems();
  }

  void _disableShuffle(
    List<Map> unplayedManualSongs,
    Set<String> manualSongIds,
  ) {
    if (_originalQueueList.isEmpty) return;

    final currentSong = _queueList[_currentQueueIndex];
    final currentQueueEntryId = _queueEntryIds.ensureId(currentSong);

    final restoredQueue = cloneMaps(_originalQueueList);
    final restoredQueueIdMap = _buildIdMap(restoredQueue);
    restoredQueue.removeWhere(
      (song) => manualSongIds.contains(restoredQueueIdMap[song]),
    );

    _queueList
      ..clear()
      ..addAll(restoredQueue);

    _currentQueueIndex = _queueList.indexWhere(
      (song) => _queueEntryIds.ensureId(song) == currentQueueEntryId,
    );

    if (_currentQueueIndex == -1) {
      _currentQueueIndex = 0;
    }

    final insertIndex = _currentQueueIndex + 1;
    _queueList.insertAll(insertIndex, unplayedManualSongs);

    _originalQueueList.clear();
    _updateQueueMediaItems();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    try {
      final shuffleEnabled = shuffleMode != AudioServiceShuffleMode.none;
      final wasShuffled = shuffleNotifier.value;

      shuffleNotifier.value = shuffleEnabled;
      unawaited(Hive.box('settings').put('shuffleEnabled', shuffleEnabled));
      await audioPlayer.setShuffleModeEnabled(shuffleEnabled);

      if (_queueList.isEmpty) return;

      if (shuffleEnabled && !wasShuffled) {
        _hydrateQueueEntryIds();
        final unplayedManualSongs = _getUnplayedManualSongs();
        final manualSongIds = unplayedManualSongs
            .map(_queueEntryIds.ensureId)
            .toSet();
        _enableShuffle(unplayedManualSongs, manualSongIds);
      } else if (!shuffleEnabled && wasShuffled) {
        _hydrateQueueEntryIds();
        final unplayedManualSongs = _getUnplayedManualSongs();
        final manualSongIds = unplayedManualSongs
            .map(_queueEntryIds.ensureId)
            .toSet();
        _disableShuffle(unplayedManualSongs, manualSongIds);
      }
    } catch (e, stackTrace) {
      logger.log(
        'Error setting shuffle mode',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    try {
      repeatNotifier.value = repeatMode;
      unawaited(Hive.box('settings').put('repeatMode', repeatMode.index));

      // Repeat All must loop over only the current playlist. Strip any
      // recommended songs that the auto picker previously appended so no
      // orphaned/duplicate tracks remain when switching modes.
      if (repeatMode == AudioServiceRepeatMode.all) {
        _removeAutoPickedSongs();
      }

      // Always set loop mode to off - we handle all repeating through _handleSongCompletion
      // This ensures ProcessingState.completed is always fired for proper song transitions
      await audioPlayer.setLoopMode(LoopMode.off);
    } catch (e, stackTrace) {
      logger.log('Error setting repeat mode', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> setSleepTimer(Duration duration) async {
    try {
      _sleepTimer?.cancel();
      sleepTimerExpired = false;
      sleepTimerNotifier.value = duration;

      _sleepTimer = Timer(duration, () async {
        sleepTimerExpired = true;
        await stop();
        sleepTimerNotifier.value = null;
      });
    } catch (e, stackTrace) {
      logger.log('Error setting sleep timer', error: e, stackTrace: stackTrace);
    }
  }

  void cancelSleepTimer() {
    try {
      _sleepTimer?.cancel();
      _sleepTimer = null;
      sleepTimerExpired = false;
      sleepTimerEndOfSong = false;
      sleepTimerNotifier.value = Duration.zero;
    } catch (e, stackTrace) {
      logger.log(
        'Error canceling sleep timer',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> setSleepTimerEndOfSong() async {
    try {
      _sleepTimer?.cancel();
      sleepTimerExpired = false;
      sleepTimerEndOfSong = true;
      sleepTimerNotifier.value = const Duration(milliseconds: -1);
    } catch (e, stackTrace) {
      logger.log(
        'Error setting sleep timer end of song',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    try {
      switch (name) {
        case 'clearQueue':
          clearQueue();
          break;
        case 'addToQueue':
          if (extras?['song'] != null) {
            await addToQueue(
              extras!['song'] as Map,
              playNext: extras['playNext'] ?? false,
            );
          }
          break;
        case 'removeFromQueue':
          if (extras?['index'] != null) {
            await removeFromQueue(extras!['index'] as int);
          }
          break;
        case 'reorderQueue':
          if (extras?['oldIndex'] != null && extras?['newIndex'] != null) {
            await reorderQueue(
              extras!['oldIndex'] as int,
              extras['newIndex'] as int,
            );
          }
          break;
        default:
          await super.customAction(name, extras);
      }
    } catch (e, stackTrace) {
      logger.log(
        'Error in customAction: $name',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}

class _PlaybackSource {
  const _PlaybackSource({
    required this.songUrl,
    required this.isOffline,
    this.headers,
  });

  final String songUrl;
  final bool isOffline;
  final Map<String, String>? headers;
}
