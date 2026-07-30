import 'package:flutter/foundation.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:wiyamusic/models/equalizer_models.dart';

/// Windows (mpv / media_kit) equalizer using ffmpeg `equalizer` audio filters.
///
/// Band centers match the iOS equalizer so presets and saved gains stay compatible.
class WindowsAudioEqualizer {
  WindowsAudioEqualizer._();

  static const double minDecibels = -12;
  static const double maxDecibels = 12;

  /// Same centers as the iOS AVAudioUnitEQ configuration.
  static const List<double> bandCentersHz = [60, 230, 910, 3600, 14000];

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool _enabled = false;
  static List<double> _gains = List<double>.filled(bandCentersHz.length, 0);

  static EqualizerParametersInfo getParameters() {
    return EqualizerParametersInfo(
      minDecibels: minDecibels,
      maxDecibels: maxDecibels,
      bands: [
        for (var i = 0; i < bandCentersHz.length; i++)
          EqualizerBandInfo(
            index: i,
            centerFrequency: bandCentersHz[i],
            gain: i < _gains.length ? _gains[i] : 0,
          ),
      ],
    );
  }

  static Future<void> setEnabled(bool enabled) async {
    if (!isSupported) return;
    _enabled = enabled;
    await _apply();
  }

  static Future<void> setBandGain(int index, double gainDb) async {
    if (!isSupported) return;
    if (index < 0 || index >= bandCentersHz.length) return;
    while (_gains.length < bandCentersHz.length) {
      _gains.add(0);
    }
    _gains[index] = gainDb.clamp(minDecibels, maxDecibels);
    await _apply();
  }

  static Future<void> setBandGains(List<double> gainsDb) async {
    if (!isSupported) return;
    _gains = [
      for (var i = 0; i < bandCentersHz.length; i++)
        (i < gainsDb.length ? gainsDb[i] : 0.0).clamp(minDecibels, maxDecibels),
    ];
    await _apply();
  }

  static Future<void> resetBands() async {
    if (!isSupported) return;
    _gains = List<double>.filled(bandCentersHz.length, 0);
    await _apply();
  }

  /// Restores persisted settings and pushes them to the active mpv players.
  static Future<void> restore({
    required bool enabled,
    required List<double> gains,
  }) async {
    if (!isSupported) return;
    _enabled = enabled;
    _gains = [
      for (var i = 0; i < bandCentersHz.length; i++)
        (i < gains.length ? gains[i] : 0.0).clamp(minDecibels, maxDecibels),
    ];
    await _apply();
  }

  static Future<void> _apply() async {
    if (!isSupported) return;
    if (!_enabled) {
      await JustAudioMediaKit.setAudioFilter('');
      return;
    }

    // One ffmpeg equalizer node per band (octave width ≈ graphic EQ).
    final filters = <String>[
      for (var i = 0; i < bandCentersHz.length; i++)
        'equalizer=f=${bandCentersHz[i].toStringAsFixed(2)}:t=o:w=1:g=${_gains[i].toStringAsFixed(2)}',
    ];
    await JustAudioMediaKit.setAudioFilter(filters.join(','));
  }
}
