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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:wiyamusic/constants/clients.dart';
import 'package:wiyamusic/main.dart' show logger;
import 'package:wiyamusic/services/data_manager.dart';
import 'package:wiyamusic/services/io_service.dart';
import 'package:wiyamusic/services/lyrics_manager.dart';
import 'package:wiyamusic/services/playlists_manager.dart';
import 'package:wiyamusic/services/proxy_manager.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/utilities/app_utils.dart';
import 'package:wiyamusic/utilities/formatter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

List globalSongs = [];

ValueNotifier<List> userLikedSongsList = ValueNotifier<List>(
  Hive.box('user').get('likedSongs', defaultValue: []),
);

ValueNotifier<List<String>> userLikedRadioStations =
    ValueNotifier<List<String>>(
      List<String>.from(
        Hive.box('user').get('likedRadioStations', defaultValue: []),
      ),
    );

ValueNotifier<List> userRecentlyPlayed = ValueNotifier<List>(
  Hive.box('user').get('recentlyPlayedSongs', defaultValue: []),
);
ValueNotifier<List> userOfflineSongs = ValueNotifier<List>(
  Hive.box('userNoBackup').get('offlineSongs', defaultValue: []),
);

dynamic nextRecommendedSong;

var _songLikeUpdateToken = 0;
final _latestSongLikeUpdateTokens = <String, int>{};

final lyrics = ValueNotifier<String?>(null);
String? lastFetchedLyrics;

void reloadSongLibraryStateFromStorage() {
  final userBox = Hive.box('user');
  userLikedSongsList.value = List.from(
    userBox.get('likedSongs', defaultValue: []),
  );
  userRecentlyPlayed.value = List.from(
    userBox.get('recentlyPlayedSongs', defaultValue: []),
  );
}

// Timeouts and durations used across manifest fetching and cache validation.
const Duration _manifestTimeout = Duration(seconds: 30);
const Duration _cacheValidationDuration = Duration(hours: 1);

/// Fetches a stream manifest for a song from a single client.
Future<StreamManifest?> _fetchStreamManifestForClient(
  String songId,
  YoutubeApiClient client,
) async {
  if (useProxy.value) {
    // ProxyManager currently merges [customClients]; use direct client here
    // for UA matching. Proxy path still works via getSongManifest fallback.
    return ProxyManager()
        .getSongManifest(songId)
        .timeout(_manifestTimeout);
  }

  return ytClient.videos.streams
      .getManifest(songId, ytClients: [client])
      .timeout(_manifestTimeout);
}

/// Fetches a stream manifest trying [customClients] in order.
Future<StreamManifest?> _fetchStreamManifest(String songId) async {
  Object? lastError;
  for (final client in customClients) {
    try {
      final manifest = await _fetchStreamManifestForClient(songId, client);
      if (manifest != null) return manifest;
    } on RequestLimitExceededException catch (e) {
      // Rate limiting applies to the IP — trying more clients makes it worse.
      lastError = e;
      logger.log(
        'Rate limited fetching manifest for $songId — stopping client cascade',
        error: e,
      );
      break;
    } catch (e) {
      lastError = e;
      logger.log(
        'Manifest fetch failed for $songId '
        '(${client.payload['context']?['client']?['clientName']})',
        error: e,
      );
    }
  }
  if (lastError != null) {
    logger.log('All manifest clients failed for $songId', error: lastError);
  }
  return null;
}

/// Playable stream URL plus CDN headers that match the minting client.
class ResolvedSongStream {
  const ResolvedSongStream({
    required this.url,
    required this.headers,
  });

  final String url;
  final Map<String, String> headers;
}

/// Tries each YouTube client until a playable URL validates with matching headers.
Future<ResolvedSongStream?> _resolveFreshSongStream(String songId) async {
  if (useProxy.value) {
    try {
      final manifest = await ProxyManager()
          .getSongManifest(songId)
          .timeout(_manifestTimeout);
      if (manifest != null) {
        final url = selectPlayableStreamUrl(manifest);
        if (url != null && url.isNotEmpty) {
          final headers = youtubeStreamHeaders;
          if (await _validateStreamUrl(url, headers)) {
            return ResolvedSongStream(url: url, headers: headers);
          }
        }
      }
    } catch (e) {
      logger.log('Proxy manifest fetch failed for $songId', error: e);
    }
  }

  for (final client in customClients) {
    try {
      final manifest = await ytClient.videos.streams
          .getManifest(songId, ytClients: [client])
          .timeout(_manifestTimeout);
      final url = selectPlayableStreamUrl(manifest);
      if (url == null || url.isEmpty) continue;

      final headers = streamHeadersForClient(client);
      if (await _validateStreamUrl(url, headers)) {
        return ResolvedSongStream(url: url, headers: headers);
      }

      logger.log(
        'Stream URL from '
        '${client.payload['context']?['client']?['clientName']} '
        'failed CDN check for $songId',
      );
    } on RequestLimitExceededException catch (e) {
      logger.log(
        'Rate limited resolving stream for $songId — stopping client cascade',
        error: e,
      );
      break;
    } catch (e) {
      logger.log(
        'Stream resolve failed for $songId '
        '(${client.payload['context']?['client']?['clientName']})',
        error: e,
      );
    }
  }
  return null;
}

/// Returns a cached song URL if present and still valid.
Future<ResolvedSongStream?> _getCachedSongStream(
  String cacheKey,
  Duration cacheDuration,
) async {
  final cached = await getData(
    'cache',
    cacheKey,
    cachingDuration: cacheDuration,
  );

  if (cached is! Map) return null;
  final url = cached['url']?.toString();
  final userAgent = cached['userAgent']?.toString();
  if (url == null || url.isEmpty || userAgent == null || userAgent.isEmpty) {
    return null;
  }

  final headers = <String, String>{
    'User-Agent': userAgent,
    'Accept': '*/*',
    'Referer': 'https://www.youtube.com/',
    'Origin': 'https://www.youtube.com',
  };

  final cacheBox = await Hive.openBox('cache');
  final cacheDate = cacheBox.get('${cacheKey}_date') as DateTime?;
  final now = DateTime.now();
  final isOld =
      cacheDate != null && now.difference(cacheDate) > _cacheValidationDuration;

  if (!isOld) {
    return ResolvedSongStream(url: url, headers: headers);
  }

  if (await _validateStreamUrl(url, headers)) {
    return ResolvedSongStream(url: url, headers: headers);
  }

  await deleteData('cache', cacheKey);
  await deleteData('cache', '${cacheKey}_date');
  return null;
}

Future<void> _cacheSongStream(
  String cacheKey,
  ResolvedSongStream stream,
) async {
  unawaited(
    addOrUpdateData<Map>('cache', cacheKey, {
      'url': stream.url,
      'userAgent': stream.headers['User-Agent'],
    }),
  );
}

/// Checks if a stream URL still responds successfully with the given headers.
Future<bool> _validateStreamUrl(
  String streamUrl,
  Map<String, String> headers,
) async {
  try {
    final response = await http.head(
      Uri.parse(streamUrl),
      headers: headers,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return true;
    }
    // Some googlevideo endpoints reject HEAD but allow ranged GET.
    if (response.statusCode == 403 || response.statusCode == 405) {
      final ranged = await http.get(
        Uri.parse(streamUrl),
        headers: {...headers, 'Range': 'bytes=0-1023'},
      );
      return ranged.statusCode == 200 || ranged.statusCode == 206;
    }
    return false;
  } catch (_) {
    return false;
  }
}

Future<List> fetchSongsList(String searchQuery) async {
  try {
    // If not in cache, perform the search
    final List<Video> searchResults = await ytClient.search.search(searchQuery);
    final songsList = searchResults
        .map((video) => returnSongLayout(0, video))
        .toList();

    return songsList;
  } catch (e, stackTrace) {
    logger.log('Error in fetchSongsList', error: e, stackTrace: stackTrace);
    return [];
  }
}

Future<List> getRecommendedSongs() async {
  try {
    if (externalRecommendations.value && userRecentlyPlayed.value.isNotEmpty) {
      return await _getRecommendationsFromRecentlyPlayed();
    } else {
      return await _getRecommendationsFromMixedSources();
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error in getRecommendedSongs',
      error: e,
      stackTrace: stackTrace,
    );
    return [];
  }
}

Future<List> _getRecommendationsFromRecentlyPlayed() async {
  final recent = (List.from(
    userRecentlyPlayed.value,
  )..shuffle()).take(5).toList();

  final scores = <String, double>{};
  final songMap = <String, Map>{};

  final futures = recent.asMap().entries.map((entry) async {
    final seedIndex = entry.key;
    final songData = entry.value;
    try {
      final song = await ytClient.videos.get(songData['ytid']);
      final related = await ytClient.videos.getRelatedVideos(song) ?? [];
      for (var i = 0; i < related.length && i < 8; i++) {
        final s = returnSongLayout(0, related[i]);
        final id = s['ytid'];
        final positionWeight = 1.0 - (i / 8);
        final recencyWeight = 1.0 - (seedIndex / recent.length);
        scores[id] = (scores[id] ?? 0) + positionWeight * recencyWeight;
        songMap[id] = s;
      }
    } catch (e, st) {
      logger.log(
        'related videos error for ${songData['ytid']}',
        error: e,
        stackTrace: st,
      );
    }
  }).toList();

  await Future.wait(futures);

  final sorted = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(15).map((e) => songMap[e.key]!).toList();
}

Future<List> _getRecommendationsFromMixedSources() async {
  final playlistSongs = [
    ...userLikedSongsList.value,
    ...userRecentlyPlayed.value,
  ];

  if (globalSongs.isEmpty) {
    const playlistId = 'PLgzTt0k8mXzEk586ze4BjvDXR7c-TUSnx';
    globalSongs = await getSongsFromPlaylist(playlistId);
  }
  playlistSongs.addAll(globalSongs.take(10));

  if (userCustomPlaylists.value.isNotEmpty) {
    for (final userPlaylist in userCustomPlaylists.value) {
      final _list = List.from(userPlaylist['list'] as List)..shuffle();
      playlistSongs.addAll(_list.take(5));
    }
  }

  return _deduplicateAndShuffle(playlistSongs);
}

List _deduplicateAndShuffle(List playlistSongs) {
  final seenYtIds = <String>{};
  final uniqueSongs = <Map>[];

  playlistSongs.shuffle();

  for (final song in playlistSongs) {
    if (song['ytid'] != null && seenYtIds.add(song['ytid'])) {
      uniqueSongs.add(song);
      // Early exit when we have enough songs
      if (uniqueSongs.length >= 15) break;
    }
  }

  return uniqueSongs;
}

Future<void> updateSongLikeStatus(
  dynamic songId,
  bool add, {
  Map? songData,
}) async {
  try {
    // Prefer ytid from song data — MediaItem.id may be a local queue entry id.
    final songDataYtid = songData?['ytid']?.toString().trim();
    var normalizedSongId = songId?.toString().trim() ?? '';
    if (_isQueueEntryId(normalizedSongId) &&
        songDataYtid != null &&
        songDataYtid.isNotEmpty) {
      normalizedSongId = songDataYtid;
    } else if (normalizedSongId.isEmpty &&
        songDataYtid != null &&
        songDataYtid.isNotEmpty) {
      normalizedSongId = songDataYtid;
    }

    if (normalizedSongId.isEmpty || _isQueueEntryId(normalizedSongId)) return;

    final updateToken = ++_songLikeUpdateToken;
    _latestSongLikeUpdateTokens[normalizedSongId] = updateToken;

    final songToAdd = add
        ? await _resolveSongForLikedStatus(normalizedSongId, songData)
        : null;

    if (_latestSongLikeUpdateTokens[normalizedSongId] != updateToken) {
      return;
    }

    final updatedLikedSongs = _deduplicateLikedSongs(userLikedSongsList.value);

    if (add) {
      if (songToAdd != null &&
          !updatedLikedSongs.any(
            (song) => song['ytid']?.toString() == normalizedSongId,
          )) {
        updatedLikedSongs.insert(0, songToAdd);
      }
    } else {
      updatedLikedSongs.removeWhere(
        (song) => song['ytid']?.toString() == normalizedSongId,
      );
    }

    if (_likedSongIdsAreEqual(userLikedSongsList.value, updatedLikedSongs))
      return;

    userLikedSongsList.value = updatedLikedSongs;
    unawaited(
      addOrUpdateData<List>('user', 'likedSongs', userLikedSongsList.value),
    );
  } catch (e, stackTrace) {
    logger.log(
      'Error updating song like status',
      error: e,
      stackTrace: stackTrace,
    );
  }
}

Future<Map?> _resolveSongForLikedStatus(String songId, Map? songData) async {
  final songDataYtid = songData?['ytid']?.toString().trim();
  if (songData != null &&
      songDataYtid != null &&
      songDataYtid.isNotEmpty &&
      !_isQueueEntryId(songDataYtid)) {
    final resolved = Map<String, dynamic>.from(songData);
    resolved['ytid'] = songDataYtid;
    return resolved;
  }

  if (_isQueueEntryId(songId)) return null;

  final cachedSong = _findSongById(userLikedSongsList.value, songId);
  if (cachedSong != null) return Map<String, dynamic>.from(cachedSong);

  return getSongDetails(userLikedSongsList.value.length, songId);
}

bool _isQueueEntryId(String? id) =>
    id != null && id.startsWith('queue-');

Map? _findSongById(Iterable<dynamic> songs, String songId) {
  for (final song in songs) {
    if (song is Map && song['ytid']?.toString() == songId) return song;
  }

  return null;
}

List _deduplicateLikedSongs(Iterable<dynamic> likedSongs) {
  final seenSongIds = <String>{};
  final deduplicatedSongs = [];

  for (final song in likedSongs) {
    if (song is! Map) {
      deduplicatedSongs.add(song);
      continue;
    }

    final songId = song['ytid']?.toString();
    if (songId == null || songId.isEmpty) {
      deduplicatedSongs.add(song);
      continue;
    }

    if (seenSongIds.add(songId)) {
      deduplicatedSongs.add(song);
    }
  }

  return deduplicatedSongs;
}

bool _likedSongIdsAreEqual(List previous, List updated) {
  if (previous.length != updated.length) return false;

  for (var i = 0; i < previous.length; i++) {
    final previousSong = previous[i];
    final updatedSong = updated[i];
    if (previousSong is! Map || updatedSong is! Map) {
      if (previousSong != updatedSong) return false;
      continue;
    }

    if (previousSong['ytid']?.toString() != updatedSong['ytid']?.toString()) {
      return false;
    }
  }

  return true;
}

Future<void> renameSongInLikedSongs(
  dynamic songId,
  String newTitle,
  String newArtist,
) async {
  try {
    final songIndex = userLikedSongsList.value.indexWhere(
      (song) => song['ytid'] == songId,
    );

    if (songIndex != -1) {
      final updatedList = List.from(userLikedSongsList.value);
      updatedList[songIndex] = Map.from(updatedList[songIndex] as Map)
        ..['title'] = newTitle
        ..['artist'] = newArtist;
      userLikedSongsList.value = updatedList;

      unawaited(
        addOrUpdateData<List>('user', 'likedSongs', userLikedSongsList.value),
      );
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error renaming song in liked songs',
      error: e,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}

bool isSongAlreadyLiked(songIdToCheck) {
  final songId = songIdToCheck?.toString();
  return userLikedSongsList.value.any(
    (song) => song['ytid']?.toString() == songId,
  );
}

bool isPlaylistAlreadyLiked(playlistIdToCheck) {
  final playlistId = playlistIdToCheck?.toString();
  if (playlistId == null || playlistId.isEmpty) return false;
  return userLikedPlaylists.value.any(
    (playlist) => playlist['ytid']?.toString() == playlistId,
  );
}

bool isRadioStationLiked(String radioStationId) {
  return userLikedRadioStations.value.contains(radioStationId);
}

Future<void> addRadioStationToLiked(String radioStationId) async {
  if (!userLikedRadioStations.value.contains(radioStationId)) {
    final updatedList = List<String>.from(userLikedRadioStations.value)
      ..add(radioStationId);
    userLikedRadioStations.value = updatedList;
    await addOrUpdateData<List<String>>(
      'user',
      'likedRadioStations',
      updatedList,
    );
  }
}

Future<void> removeRadioStationFromLiked(String radioStationId) async {
  if (userLikedRadioStations.value.contains(radioStationId)) {
    final updatedList = List<String>.from(userLikedRadioStations.value)
      ..remove(radioStationId);
    userLikedRadioStations.value = updatedList;
    unawaited(
      addOrUpdateData<List<String>>('user', 'likedRadioStations', updatedList),
    );
  }
}

bool isSongAlreadyOffline(songIdToCheck) =>
    userOfflineSongs.value.any((song) => song['ytid'] == songIdToCheck);

/// Per-song download progress (`null` = idle, `0.0`–`1.0` = downloading).
final Map<String, ValueNotifier<double?>> songDownloadProgressNotifiers = {};

/// In-flight offline downloads (claimed synchronously before any await).
final Set<String> _activeSongDownloads = {};

class _SongDownloadSession {
  bool cancelled = false;
}

final Map<String, _SongDownloadSession> _songDownloadSessions = {};

ValueNotifier<double?> songDownloadProgressNotifier(String ytid) {
  return songDownloadProgressNotifiers.putIfAbsent(
    ytid,
    () => ValueNotifier<double?>(null),
  );
}

bool isSongDownloading(String ytid) => _activeSongDownloads.contains(ytid);

void _setSongDownloadProgress(String ytid, double? progress) {
  songDownloadProgressNotifier(ytid).value = progress;
}

void _clearSongDownloadProgress(String ytid) {
  final notifier = songDownloadProgressNotifiers[ytid];
  if (notifier == null) return;
  notifier.value = null;
}

/// Cancels an in-progress single-song offline download, if any.
void cancelSongDownload(String ytid) {
  final session = _songDownloadSessions[ytid];
  if (session != null) {
    session.cancelled = true;
  }
}

class SongOfflineDownloadCancelled implements Exception {
  @override
  String toString() => 'Song offline download cancelled';
}

class SongOfflineRateLimited implements Exception {
  @override
  String toString() => 'Song offline download rate limited by YouTube';
}

bool isPlaylistFullyOffline(List songs) {
  if (songs.isEmpty) return false;
  final offlineIds = userOfflineSongs.value.map((s) => s['ytid']).toSet();
  return songs.every((s) => offlineIds.contains(s['ytid']));
}

Map<String, dynamic> getOfflineSongByYtid(String ytid) {
  try {
    final song = userOfflineSongs.value.firstWhere(
      (s) => s['ytid'] == ytid,
      orElse: () => <String, dynamic>{},
    );
    return Map<String, dynamic>.from(song);
  } catch (_) {
    return <String, dynamic>{};
  }
}

Future<List<String>> getSearchSuggestions(String query) async {
  // Custom implementation:

  // const baseUrl = 'https://suggestqueries.google.com/complete/search';
  // final parameters = {
  //   'client': 'firefox',
  //   'ds': 'yt',
  //   'q': query,
  // };

  // final uri = Uri.parse(baseUrl).replace(queryParameters: parameters);

  // try {
  //   final response = await http.get(
  //     uri,
  //     headers: {
  //       'User-Agent':
  //           'Mozilla/5.0 (Windows NT 10.0; rv:96.0) Gecko/20100101 Firefox/96.0',
  //     },
  //   );

  //   if (response.statusCode == 200) {
  //     final suggestions = jsonDecode(response.body)[1] as List<dynamic>;
  //     final suggestionStrings = suggestions.cast<String>().toList();
  //     return suggestionStrings;
  //   }
  // } catch (e, stackTrace) {
  //   logger.log('Error in getSearchSuggestions:$e\n$stackTrace');
  // }

  // Built-in implementation:

  final suggestions = await ytClient.search.getQuerySuggestions(query);

  return suggestions;
}

Future<List<Map<String, int>>> getSkipSegments(String id) async {
  try {
    final res = await ProxyManager().getProxiedResponse(
      Uri(
        scheme: 'https',
        host: 'sponsor.ajay.app',
        path: '/api/skipSegments',
        queryParameters: {
          'videoID': id,
          'category': [
            'sponsor',
            'selfpromo',
            'interaction',
            'intro',
            'outro',
            'music_offtopic',
          ],
          'actionType': 'skip',
        },
      ),
    );
    if (res.statusCode == 200 && res.body != 'Not Found') {
      final data = jsonDecode(res.body);
      final segments = data.map((obj) {
        return Map.castFrom<String, dynamic, String, int>({
          'start': obj['segment'].first.toInt(),
          'end': obj['segment'].last.toInt(),
        });
      }).toList();
      return List.castFrom<dynamic, Map<String, int>>(segments);
    } else {
      return [];
    }
  } catch (e, stackTrace) {
    logger.log('Error in getSkipSegments', error: e, stackTrace: stackTrace);
    return [];
  }
}

Future<void> getSimilarSong(String songYtId) async {
  try {
    final song = await ytClient.videos.get(songYtId);
    final relatedSongs = await ytClient.videos.getRelatedVideos(song) ?? [];

    if (relatedSongs.isNotEmpty) {
      nextRecommendedSong = returnSongLayout(0, relatedSongs[0]);
    } else {
      logger.log('No related songs found for $songYtId');
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error while fetching next similar song:',
      error: e,
      stackTrace: stackTrace,
    );
  }
}

/// Fetches the best available audio stream for a song.
Future<AudioOnlyStreamInfo?> fetchBestAudioStream(String? songId) async {
  try {
    if (songId == null || songId.isEmpty) {
      logger.log('fetchBestAudioStream: songId is null or empty');
      return null;
    }

    final manifest = await _fetchStreamManifest(songId);
    final audioStream = manifest?.audioOnly;
    if (audioStream == null || audioStream.isEmpty) {
      logger.log('fetchBestAudioStream: no audio streams for $songId');
      return null;
    }
    return selectAudioOnlyStreamForQuality(audioStream.sortByBitrate());
  } on TimeoutException catch (_) {
    logger.log('fetchBestAudioStream request timed out for $songId');
    return null;
  } catch (e, stackTrace) {
    logger.log(
      'Error while fetching best audio stream',
      error: e,
      stackTrace: stackTrace,
    );
    return null;
  }
}

/// Resolves a playable stream URL for a song (cached when possible).
Future<String?> fetchSongStreamUrl(
  String songId,
  bool isLive, {
  bool bypassCache = false,
}) async {
  final resolved = await resolveSongStream(
    songId,
    isLive,
    bypassCache: bypassCache,
  );
  return resolved?.url;
}

/// Resolves a playable stream URL + matching CDN headers (cached when possible).
Future<ResolvedSongStream?> resolveSongStream(
  String songId,
  bool isLive, {
  bool bypassCache = false,
}) async {
  try {
    if (songId.isEmpty) {
      logger.log('resolveSongStream: songId is empty');
      return null;
    }
    if (isLive) {
      final streamInfo = await ytClient.videos.streamsClient
          .getHttpLiveStreamUrl(VideoId(songId));
      return ResolvedSongStream(
        url: streamInfo,
        headers: youtubeStreamHeaders,
      );
    }

    const _cacheDuration = Duration(hours: 3);
    final cacheKey = songStreamCacheKey(songId);

    if (!bypassCache) {
      final cached = await _getCachedSongStream(cacheKey, _cacheDuration);
      if (cached != null) return cached;
    } else {
      await deleteData('cache', cacheKey);
      await deleteData('cache', '${cacheKey}_date');
    }

    final resolved = await _resolveFreshSongStream(songId);
    if (resolved == null) {
      logger.log('resolveSongStream: no playable streams for $songId');
      return null;
    }

    unawaited(_cacheSongStream(cacheKey, resolved));
    return resolved;
  } on TimeoutException catch (_) {
    logger.log('resolveSongStream request timed out for $songId');
    return null;
  } catch (e, stackTrace) {
    logger.log(
      'Error in resolveSongStream for $songId:',
      error: e,
      stackTrace: stackTrace,
    );
    return null;
  }
}

Future<Map<String, dynamic>> getSongDetails(
  int songIndex,
  String songId,
) async {
  try {
    final song = await ytClient.videos.get(songId);
    return returnSongLayout(songIndex, song);
  } catch (e, stackTrace) {
    logger.log(
      'Error while getting song details',
      error: e,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}

Future<String?> getSongLyrics(String? artist, String title) async {
  if (artist == null) return null;
  if (lastFetchedLyrics != '$artist - $title') {
    lyrics.value = null;
    var _lyrics = await LyricsManager().fetchLyrics(artist, title);
    if (_lyrics != null) {
      _lyrics = _lyrics.replaceAll(RegExp(r'\n{4}'), '\n\n');
      _lyrics = _lyrics.replaceAll(RegExp(r'\n{2}'), '\n');
      lyrics.value = _lyrics;
    } else {
      return null;
    }

    lastFetchedLyrics = '$artist - $title';
    return _lyrics;
  }

  return lyrics.value;
}

Future<bool> makeSongOffline(
  dynamic song, {
  void Function(double progress)? onProgress,
  bool cancelExisting = true,
}) async {
  String? ytid;
  _SongDownloadSession? session;
  try {
    ytid = song['ytid']?.toString();

    if (ytid == null || ytid.isEmpty) {
      logger.log('makeSongOffline: song["ytid"] is null or empty');
      return false;
    }

    if (isSongAlreadyOffline(ytid)) {
      final existingPath = FilePaths.getAudioPath(ytid);
      if (await File(existingPath).exists()) {
        onProgress?.call(1);
        return true;
      }
    }

    // Cancel any previous in-flight download for this song, then claim the slot.
    if (_activeSongDownloads.contains(ytid)) {
      if (!cancelExisting) {
        logger.log('makeSongOffline: download already in progress for $ytid');
        return false;
      }
      cancelSongDownload(ytid);
      // Wait briefly for the previous session to release the lock.
      for (var i = 0; i < 40 && _activeSongDownloads.contains(ytid); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (_activeSongDownloads.contains(ytid)) {
        logger.log('makeSongOffline: previous download did not stop for $ytid');
        return false;
      }
    }

    if (!_activeSongDownloads.add(ytid)) {
      logger.log('makeSongOffline: failed to claim download lock for $ytid');
      return false;
    }

    session = _SongDownloadSession();
    _songDownloadSessions[ytid] = session;
    _setSongDownloadProgress(ytid, 0);
    onProgress?.call(0);

    final offlineSong = Map<String, dynamic>.from(song as Map);

    final audioPath = FilePaths.getAudioPath(ytid);
    final audioFile = File(audioPath);
    final artworkPath = FilePaths.getArtworkPath(ytid);

    await audioFile.parent.create(recursive: true);

    IOSink? fileStream;
    try {
      if (session.cancelled) throw SongOfflineDownloadCancelled();

      final audioManifest = await fetchBestAudioStream(ytid);
      if (session.cancelled) throw SongOfflineDownloadCancelled();

      if (audioManifest == null) {
        logger.log('makeSongOffline: audioManifest is null for $ytid');
        return false;
      }

      final totalBytes = audioManifest.size.totalBytes;
      var downloadedBytes = 0;
      void reportProgress() {
        final progress = totalBytes > 0
            ? (downloadedBytes / totalBytes).clamp(0.0, 1.0)
            : (1 - (1_000_000 / (downloadedBytes + 1_000_000)))
                .clamp(0.0, 0.95);
        _setSongDownloadProgress(ytid!, progress);
        onProgress?.call(progress);
      }

      final stream = ytClient.videos.streamsClient.get(audioManifest);
      fileStream = audioFile.openWrite();
      await for (final chunk in stream) {
        if (session.cancelled) throw SongOfflineDownloadCancelled();
        fileStream.add(chunk);
        downloadedBytes += chunk.length;
        reportProgress();
      }
      await fileStream.flush();
      await fileStream.close();
      fileStream = null;
      _setSongDownloadProgress(ytid, 1);
      onProgress?.call(1);
    } on SongOfflineDownloadCancelled {
      try {
        await fileStream?.close();
      } catch (_) {}
      if (await audioFile.exists()) {
        await audioFile.delete();
      }
      logger.log('makeSongOffline: cancelled download for $ytid');
      return false;
    } on RequestLimitExceededException catch (e, stackTrace) {
      logger.log(
        'makeSongOffline: rate limited for $ytid',
        error: e,
        stackTrace: stackTrace,
      );
      try {
        await fileStream?.close();
      } catch (_) {}
      if (await audioFile.exists()) {
        await audioFile.delete();
      }
      throw SongOfflineRateLimited();
    } catch (e, stackTrace) {
      logger.log(
        'Error downloading audio file',
        error: e,
        stackTrace: stackTrace,
      );
      try {
        await fileStream?.close();
      } catch (_) {}
      if (await audioFile.exists()) {
        await audioFile.delete();
      }
      return false;
    }

    if (session.cancelled) {
      if (await audioFile.exists()) {
        await audioFile.delete();
      }
      return false;
    }

    try {
      if (offlineSong['highResImage'] != null &&
          offlineSong['highResImage'].toString().isNotEmpty) {
        final _artworkFile = await _downloadAndSaveArtworkFile(
          offlineSong['highResImage'],
          artworkPath,
        );

        if (_artworkFile != null && await _artworkFile.exists()) {
          offlineSong['artworkPath'] = artworkPath;
        } else {
          logger.log(
            'Artwork download failed or file does not exist for $ytid',
          );
          offlineSong['artworkPath'] = null;
        }
      }
    } catch (e, stackTrace) {
      logger.log('Error downloading artwork', error: e, stackTrace: stackTrace);
      offlineSong['artworkPath'] = null;
    }

    offlineSong['audioPath'] = audioFile.path;
    offlineSong['dateAdded'] = DateTime.now().millisecondsSinceEpoch;

    try {
      final existingIndex = userOfflineSongs.value.indexWhere(
        (s) => s['ytid'] == ytid,
      );

      final updatedOfflineSongs = List.from(userOfflineSongs.value);
      if (existingIndex != -1) {
        updatedOfflineSongs[existingIndex] = offlineSong;
      } else {
        updatedOfflineSongs.add(offlineSong);
      }
      userOfflineSongs.value = updatedOfflineSongs;

      unawaited(
        addOrUpdateData<List>(
          'userNoBackup',
          'offlineSongs',
          userOfflineSongs.value,
        ),
      );
    } catch (e, st) {
      logger.log(
        'Error updating global offline songs list',
        error: e,
        stackTrace: st,
      );
    }

    return true;
  } on SongOfflineRateLimited {
    rethrow;
  } catch (e, stackTrace) {
    logger.log('Error making song offline', error: e, stackTrace: stackTrace);
    return false;
  } finally {
    if (ytid != null &&
        ytid.isNotEmpty &&
        identical(_songDownloadSessions[ytid], session)) {
      _songDownloadSessions.remove(ytid);
      _activeSongDownloads.remove(ytid);
      _clearSongDownloadProgress(ytid);
    }
  }
}

Future<bool> removeSongFromOffline(dynamic songId) async {
  try {
    final audioPath = FilePaths.getAudioPath(songId);
    final audioFile = File(audioPath);
    final artworkPath = FilePaths.getArtworkPath(songId);
    final artworkFile = File(artworkPath);

    try {
      if (await audioFile.exists()) await audioFile.delete(recursive: true);
    } catch (e, stackTrace) {
      logger.log('Error deleting audio file', error: e, stackTrace: stackTrace);
    }

    try {
      if (await artworkFile.exists()) await artworkFile.delete(recursive: true);
    } catch (e, stackTrace) {
      logger.log(
        'Error deleting artwork file',
        error: e,
        stackTrace: stackTrace,
      );
    }

    try {
      userOfflineSongs.value = List.from(userOfflineSongs.value)
        ..removeWhere((song) => song['ytid'] == songId);
      unawaited(
        addOrUpdateData<List>(
          'userNoBackup',
          'offlineSongs',
          userOfflineSongs.value,
        ),
      );
    } catch (e, st) {
      logger.log(
        'Error updating offline songs registry after removal',
        error: e,
        stackTrace: st,
      );
    }

    return true;
  } catch (e, stackTrace) {
    logger.log(
      'Error removing song from offline storage',
      error: e,
      stackTrace: stackTrace,
    );
    return false;
  }
}

Future<File?> _downloadAndSaveArtworkFile(String url, String filePath) async {
  try {
    final response = await ProxyManager().getProxiedResponse(Uri.parse(url));

    if (response.statusCode == 200) {
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);

      // Validate that the file was actually written
      if (await file.exists() && await file.length() > 0) {
        return file;
      } else {
        logger.log('Artwork file was not written properly: $filePath');
        return null;
      }
    } else {
      logger.log(
        'Failed to download file. Status code: ${response.statusCode}',
      );
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error downloading and saving file',
      error: e,
      stackTrace: stackTrace,
    );
  }

  return null;
}

const recentlyPlayedSongsLimit = 100;

/// Updates the recently played list and listening count for [songId].
///
/// When [songFallback] is provided, its metadata is used to seed the history
/// entry if the song has never been played before. This avoids a network
/// request when registering offline songs whose metadata is already available
/// locally (e.g. from [userOfflineSongs]).
Future<void> updateRecentlyPlayed(dynamic songId, {Map? songFallback}) async {
  try {
    final now = DateTime.now();

    if (userRecentlyPlayed.value.isNotEmpty &&
        userRecentlyPlayed.value[0]['ytid'] == songId) {
      final updatedList = List.from(userRecentlyPlayed.value);
      final existing = Map.from(updatedList[0] as Map);
      existing['listeningCount'] = (existing['listeningCount'] ?? 0) + 1;
      existing['lastPlayed'] = now;
      updatedList[0] = existing;
      userRecentlyPlayed.value = updatedList;
      unawaited(
        addOrUpdateData<List>(
          'user',
          'recentlyPlayedSongs',
          userRecentlyPlayed.value,
        ),
      );
      return;
    }

    final existingIndex = userRecentlyPlayed.value.indexWhere(
      (song) => song['ytid'] == songId,
    );

    final updatedList = List.from(userRecentlyPlayed.value);

    if (existingIndex == -1 && updatedList.length >= recentlyPlayedSongsLimit) {
      updatedList.removeLast();
    }

    if (existingIndex != -1) {
      final song = Map.from(updatedList.removeAt(existingIndex) as Map);
      song['listeningCount'] = (song['listeningCount'] ?? 0) + 1;
      song['lastPlayed'] = now;
      updatedList.insert(0, song);
    } else {
      final dynamic fetchedSongDetails = songFallback != null
          ? Map<String, dynamic>.from(songFallback)
          : await getSongDetails(0, songId);

      if (fetchedSongDetails is! Map) {
        logger.log('Failed to update recently played: invalid song details');
        return;
      }

      final newSongDetails = Map<String, dynamic>.from(fetchedSongDetails);
      newSongDetails['ytid'] ??= songId;
      newSongDetails['listeningCount'] = 1;
      newSongDetails['lastPlayed'] = now;
      updatedList.insert(0, newSongDetails);
    }

    userRecentlyPlayed.value = updatedList;
    unawaited(
      addOrUpdateData<List>(
        'user',
        'recentlyPlayedSongs',
        userRecentlyPlayed.value,
      ),
    );
  } catch (e, stackTrace) {
    logger.log(
      'Error updating recently played',
      error: e,
      stackTrace: stackTrace,
    );
  }
}

Future<void> removeFromRecentlyPlayed(dynamic songId) async {
  if (userRecentlyPlayed.value.any((song) => song['ytid'] == songId)) {
    userRecentlyPlayed.value = List.from(userRecentlyPlayed.value)
      ..removeWhere((song) => song['ytid'] == songId);
    unawaited(
      addOrUpdateData<List>(
        'user',
        'recentlyPlayedSongs',
        userRecentlyPlayed.value,
      ),
    );
  }
}
