/*
 * Multi-band equalizer bridge for iOS (AVPlayer audio-mix tap).
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class IosAudioEqualizer {
  IosAudioEqualizer._();

  static const MethodChannel _channel = MethodChannel(
    'com.wiyamusic/ios_audio_equalizer',
  );

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<Map<String, dynamic>?> getParameters() async {
    if (!isSupported) return null;
    final result = await _channel.invokeMethod<dynamic>('getParameters');
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return null;
  }

  static Future<void> setEnabled(bool enabled) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
  }

  static Future<void> setBandGain(int index, double gainDb) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('setBandGain', {
      'index': index,
      'gain': gainDb,
    });
  }

  static Future<void> setBandGains(List<double> gainsDb) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('setBandGains', {'gains': gainsDb});
  }

  static Future<void> resetBands() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('resetBands');
  }
}
