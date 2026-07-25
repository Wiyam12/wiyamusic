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
import 'package:wiyamusic/services/common_services.dart';
import 'package:wiyamusic/services/io_service.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/utilities/artwork_provider.dart';

Map mediaItemToMap(MediaItem mediaItem) {
  final extras = mediaItem.extras;
  return {
    'id': mediaItem.id,
    'ytid': extras?['ytid'],
    'album': mediaItem.album.toString(),
    'artist': mediaItem.artist.toString(),
    'title': mediaItem.title,
    'artistId': extras?['artistId'],
    'videoAuthor': extras?['videoAuthor'],
    'genre': extras?['genre'],
    'highResImage': extras?['highResImage'] ?? mediaItem.artUri.toString(),
    'lowResImage': extras?['lowResImage'],
    'isLive': extras?['isLive'] ?? false,
  };
}

MediaItem mapToMediaItem(Map song) {
  final ytid = song['ytid']?.toString();
  final offlineSong = ytid != null
      ? getOfflineSongByYtid(ytid)
      : <String, dynamic>{};
  final isOffline = offlineSong.isNotEmpty;

  final localArtwork = _resolveLocalArtworkPath(
    ytid: ytid,
    song: song,
    offlineSong: offlineSong,
  );
  final hasLocalArtwork = localArtwork != null;

  // Never attach remote artwork for offline/downloaded playback. On iOS,
  // audio_service tries to fetch artUri and fails hard without network
  // (img.youtube.com host lookup), which contributes to stuck loading UI.
  final Uri? artUri;
  if (hasLocalArtwork) {
    artUri = Uri.file(localArtwork);
  } else if (isOffline || offlineMode.value) {
    artUri = null;
  } else {
    final remote =
        (song['highResImage'] ??
                offlineSong['highResImage'] ??
                song['lowResImage'] ??
                '')
            .toString();
    artUri = remote.isEmpty ? null : Uri.tryParse(remote);
  }

  return MediaItem(
    id: song['id'].toString(),
    artist: song['artist'].toString().trim(),
    title: song['title'].toString(),
    artUri: artUri,
    duration: song['duration'] != null
        ? Duration(seconds: song['duration'])
        : null,
    extras: {
      'lowResImage': song['lowResImage'],
      'ytid': song['ytid'],
      'artistId': song['artistId'],
      'videoAuthor': song['videoAuthor'],
      'genre': song['genre'],
      'isLive': song['isLive'],
      'highResImage': song['highResImage'],
      'artWorkPath': hasLocalArtwork
          ? localArtwork
          : (song['highResImage']?.toString() ?? ''),
    },
  );
}

String? _resolveLocalArtworkPath({
  required String? ytid,
  required Map song,
  required Map<String, dynamic> offlineSong,
}) {
  final candidates = <String?>[
    song['artworkPath']?.toString(),
    offlineSong['artworkPath']?.toString(),
    if (ytid != null && ytid.isNotEmpty) FilePaths.getArtworkPath(ytid),
  ];

  for (final candidate in candidates) {
    if (candidate == null || candidate.isEmpty) continue;
    if (ArtworkProvider.localFileExists(candidate)) {
      return candidate.replaceFirst('file://', '');
    }
  }
  return null;
}

/// Compares two Duration objects with tolerance for minor differences.
///
/// This prevents unnecessary updates when duration values have minor variations
/// (e.g., due to buffering or precision differences).
bool durationEquals(Duration? prev, Duration? curr) {
  if (prev == curr) return true;
  if (prev == null || curr == null) return prev == curr;

  // Consider durations equal if they differ by less than 1 second
  return (prev - curr).abs() < const Duration(seconds: 1);
}
