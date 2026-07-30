import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wiyamusic/constants/app_constants.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

BorderRadius getItemBorderRadius(
  int index,
  int totalLength, {
  bool hasItemsBefore = false,
  bool hasItemsAfter = false,
}) {
  // Determine if this item is the absolute top or absolute bottom of the visual block
  final isAbsoluteFirst = index == 0 && !hasItemsBefore;
  final isAbsoluteLast = index == totalLength - 1 && !hasItemsAfter;

  if (isAbsoluteFirst && isAbsoluteLast) {
    return commonCustomBarRadius; // Single item in the entire block
  } else if (isAbsoluteFirst) {
    return commonCustomBarRadiusFirst; // Top of the block
  } else if (isAbsoluteLast) {
    return commonCustomBarRadiusLast; // Bottom of the block
  }
  return BorderRadius.zero; // Default for middle items
}

ValueKey<int> listItemKey(String scope, int index, [Object? item]) {
  return ValueKey<int>(Object.hash(scope, index, item));
}

/// Validates if a URL is a YouTube playlist URL
bool isYoutubePlaylistUrl(String url) {
  return _youtubePlaylistRegExp.hasMatch(url);
}

/// Extracts the playlist ID from a YouTube playlist URL
String? extractYoutubePlaylistId(String url) {
  if (!isYoutubePlaylistUrl(url)) {
    return null;
  }

  final match = _youtubePlaylistIdRegExp.firstMatch(url);
  return match?.group(1);
}

double getResponsiveTitleFontSize(Size size) {
  final isDesktop = size.width > 800;
  final isLandscape = size.width > size.height;
  if (isDesktop) return 28;
  if (isLandscape) return 22;
  if (size.width < 360) return 20;
  if (size.width < 400) return 22;
  return size.height * 0.028;
}

double getResponsiveArtistFontSize(Size size) {
  final isDesktop = size.width > 800;
  final isLandscape = size.width > size.height;
  if (isDesktop) return 18;
  if (isLandscape) return 15;
  if (size.width < 360) return 14;
  if (size.width < 400) return 15;
  return size.height * 0.018;
}

final RegExp _youtubePlaylistRegExp = RegExp(
  r'^(https?:\/\/)?(www\.|m\.|music\.)?(youtube\.com|youtu\.be)\/.*(list=([a-zA-Z0-9_-]+)).*$',
);

final RegExp _youtubePlaylistIdRegExp = RegExp('[&?]list=([a-zA-Z0-9_-]+)');

bool isSponsorshipAnnouncementUrl(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase();
  return host != null && (host == 'ko-fi.com' || host.endsWith('.ko-fi.com'));
}

/// Formats a [monthKey] (e.g. "2026-06") into a locale-aware month label
/// such as "June 2026". Falls back to [monthKey] if parsing fails.
String formatMonthPeriodLabel(Locale locale, String monthKey) {
  final parts = monthKey.split('-');
  if (parts.length != 2) return monthKey;

  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null) return monthKey;

  final label = DateFormat.yMMMM(locale.toString()).format(
    DateTime(year, month),
  );
  return label.isEmpty
      ? monthKey
      : '${label[0].toUpperCase()}${label.substring(1)}';
}

AudioOnlyStreamInfo selectAudioOnlyStreamForQuality(
  List<AudioOnlyStreamInfo> availableSources, {
  bool appleSafeOnly = false,
}) {
  final sortedByCompatibility = _sortAudioOnlyByCompatibility(availableSources);
  var compatibleSources = _filterCompatibleAudioOnlySources(
    sortedByCompatibility,
  );

  // Offline downloads on Apple must be AAC-in-MP4. Opus/Vorbis can be selected
  // as a streaming fallback on Android, but AVPlayer can't play those files.
  if (appleSafeOnly) {
    compatibleSources = compatibleSources
        .where(_isAppleSafeAudioOnlyStream)
        .toList();
    if (compatibleSources.isEmpty) {
      compatibleSources = sortedByCompatibility
          .where(_isAppleSafeAudioOnlyStream)
          .toList();
    }
    if (compatibleSources.isEmpty) {
      throw StateError('No Apple-safe AAC audio streams available');
    }
  }

  final selectionPool = compatibleSources.isNotEmpty
      ? compatibleSources
      : sortedByCompatibility;

  final qualitySetting = audioQualitySetting.value;

  if (qualitySetting == 'low') {
    return selectionPool.last;
  } else if (qualitySetting == 'medium') {
    return selectionPool[selectionPool.length ~/ 2];
  }

  return selectionPool.withHighestBitrate();
}

/// Picks a stream URL that the current platform's audio player can open.
///
/// On Apple platforms, just_audio / AVPlayer cannot open YouTube DASH
/// audio-only streams and fails with `(-11828) Cannot Open`. Prefer progressive
/// muxed MP4 or HLS there instead.
String? selectPlayableStreamUrl(StreamManifest manifest) {
  final preferAppleCompatible = Platform.isIOS || Platform.isMacOS;

  if (preferAppleCompatible) {
    if (manifest.muxed.isNotEmpty) {
      return manifest.muxed.withHighestBitrate().url.toString();
    }

    final hlsAudio = manifest.hls.whereType<HlsAudioStreamInfo>();
    if (hlsAudio.isNotEmpty) {
      return hlsAudio.first.url.toString();
    }
    if (manifest.hls.isNotEmpty) {
      return manifest.hls.first.url.toString();
    }
  }

  final audioStreams = manifest.audioOnly;
  if (audioStreams.isNotEmpty) {
    return selectAudioOnlyStreamForQuality(
      audioStreams.sortByBitrate(),
    ).url.toString();
  }

  if (manifest.muxed.isNotEmpty) {
    return manifest.muxed.withHighestBitrate().url.toString();
  }

  if (manifest.hls.isNotEmpty) {
    return manifest.hls.first.url.toString();
  }

  return null;
}

/// Cache key for a song stream URL. Includes platform so iOS/Android do not
/// reuse incompatible stream formats.
String songStreamCacheKey(String songId) {
  final platformKey = Platform.isIOS
      ? 'ios'
      : Platform.isMacOS
      ? 'macos'
      : 'android';
  // v3: per-client UA stored with URL; ANDROID_VR preferred on Android
  return 'song_${songId}_${audioQualitySetting.value}_${platformKey}_v3_url';
}

List<AudioOnlyStreamInfo> _filterCompatibleAudioOnlySources(
  List<AudioOnlyStreamInfo> sources,
) {
  return sources.where((stream) {
    final codec = stream.codec.toString().toLowerCase();
    final container = stream.container.name.toLowerCase();

    if (_isDolbyCodec(codec)) {
      return false;
    }

    return _isPreferredAudioOnlyCodec(codec, container);
  }).toList();
}

List<AudioOnlyStreamInfo> _sortAudioOnlyByCompatibility(
  List<AudioOnlyStreamInfo> sources,
) {
  final sorted = List<AudioOnlyStreamInfo>.from(sources)
    ..sort((a, b) {
      final aScore = _audioOnlyCompatibilityScore(a);
      final bScore = _audioOnlyCompatibilityScore(b);
      return bScore.compareTo(aScore);
    });
  return sorted;
}

int _audioOnlyCompatibilityScore(AudioOnlyStreamInfo stream) {
  final codec = stream.codec.toString().toLowerCase();
  final container = stream.container.name.toLowerCase();

  if (_isDolbyCodec(codec)) {
    return 0;
  }

  if ((codec.contains('mp4a') || codec.contains('aac')) &&
      (container == 'mp4' || container == 'm4a')) {
    return 3;
  }

  if (codec.contains('opus') || codec.contains('vorbis')) {
    return 2;
  }

  return 1;
}

bool _isDolbyCodec(String codec) {
  return codec.contains('ec-3') ||
      codec.contains('ac-3') ||
      codec.contains('eac3') ||
      codec.contains('dolby');
}

bool _isPreferredAudioOnlyCodec(String codec, String container) {
  if ((codec.contains('mp4a') || codec.contains('aac')) &&
      (container == 'mp4' || container == 'm4a')) {
    return true;
  }

  return codec.contains('opus') || codec.contains('vorbis');
}

bool _isAppleSafeAudioOnlyStream(AudioOnlyStreamInfo stream) {
  final codec = stream.codec.toString().toLowerCase();
  final container = stream.container.name.toLowerCase();
  return (codec.contains('mp4a') || codec.contains('aac')) &&
      (container == 'mp4' || container == 'm4a');
}
