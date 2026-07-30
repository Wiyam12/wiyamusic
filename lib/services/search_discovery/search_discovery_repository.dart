import 'package:wiyamusic/models/search_discovery_models.dart';
import 'package:wiyamusic/services/search_discovery/search_discovery_api_service.dart';
import 'package:wiyamusic/services/search_discovery/search_discovery_cache_repository.dart';

/// Coordinates remote fetch + local cache for Search discovery.
class SearchDiscoveryRepository {
  SearchDiscoveryRepository({
    SearchDiscoveryApiService? api,
    SearchDiscoveryCacheRepository? cache,
  }) : _api = api ?? SearchDiscoveryApiService(),
       _cache = cache ?? SearchDiscoveryCacheRepository();

  final SearchDiscoveryApiService _api;
  final SearchDiscoveryCacheRepository _cache;

  Future<SearchDiscoverySnapshot?> getCached({
    bool allowExpired = true,
  }) {
    return _cache.read(allowExpired: allowExpired);
  }

  Future<bool> isCacheFresh() => _cache.isFresh();

  /// Fetches from API and updates cache on success.
  Future<SearchDiscoverySnapshot> refreshFromApi({
    String country = SearchDiscoveryApiService.defaultCountry,
  }) async {
    final remote = await _api.fetchDiscovery(country: country);
    if (!remote.isEmpty) {
      await _cache.write(remote);
    }
    return remote;
  }
}
