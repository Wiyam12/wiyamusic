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

import 'package:wiyamusic/main.dart' show logger;
import 'package:wiyamusic/models/search_discovery_models.dart';
import 'package:wiyamusic/services/artist_service.dart';
import 'package:youtube_music_explode_dart/youtube_music_explode_dart.dart';

/// Remote API for Search discovery (YouTube Music charts / explore).
class SearchDiscoveryApiService {
  SearchDiscoveryApiService({YoutubeMusicExplode? client})
    : _client = client ?? YoutubeMusicExplode();

  final YoutubeMusicExplode _client;

  /// Default country for charts / trending (Philippines).
  static const defaultCountry = 'PH';

  Future<SearchDiscoverySnapshot> fetchDiscovery({
    String country = defaultCountry,
  }) async {
    try {
      final charts = await _client.music.getCharts(country: country);
      final artists = charts.artists
          .where((a) => !looksUnofficialArtistName(a.name))
          .map(
            (a) => <String, dynamic>{
              'ytid': a.id,
              'title': normalizeArtistDisplayTitle(a.name),
              'sourceTitle': a.name,
              'image': normalizeArtistThumbnailUrl(a.thumbnailUrl),
              'source': 'youtube-artist',
              'isArtist': true,
              'isVerifiedArtist': true,
              'list': <dynamic>[],
            },
          )
          .toList();

      final trending = charts.trendingQueries
          .map((q) => q.trim())
          .where((q) => q.isNotEmpty)
          .take(6)
          .toList();

      return SearchDiscoverySnapshot(
        trendingSearches: trending,
        topArtists: artists,
        fetchedAt: DateTime.now(),
      );
    } catch (e, stackTrace) {
      logger.log(
        'SearchDiscoveryApiService.fetchDiscovery failed',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  void close() {
    _client.close();
  }
}
