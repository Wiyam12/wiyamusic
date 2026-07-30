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
