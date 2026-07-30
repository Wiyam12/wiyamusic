import 'package:hive/hive.dart';
import 'package:wiyamusic/models/search_discovery_models.dart';
import 'package:wiyamusic/services/data_manager.dart';

/// Local Hive cache for Search discovery payloads.
class SearchDiscoveryCacheRepository {
  /// YouTube Music PH charts discovery cache.
  static const cacheKey = 'search_discovery_v5_yt_ph';
  static const cacheDuration = Duration(hours: 6);

  /// Returns cached discovery even if expired (for offline fallback).
  Future<SearchDiscoverySnapshot?> read({bool allowExpired = true}) async {
    final box = await Hive.openBox('cache');
    final raw = box.get(cacheKey);
    if (raw is! Map) return null;

    final snapshot = SearchDiscoverySnapshot.fromCacheMap(raw);
    if (snapshot.isEmpty) return null;

    if (!allowExpired) {
      final date = box.get('${cacheKey}_date');
      if (date is! DateTime) return null;
      if (DateTime.now().difference(date) > cacheDuration) return null;
    }

    return snapshot;
  }

  Future<bool> isFresh() async {
    final box = await Hive.openBox('cache');
    final date = box.get('${cacheKey}_date');
    if (date is! DateTime) return false;
    return DateTime.now().difference(date) <= cacheDuration;
  }

  Future<void> write(SearchDiscoverySnapshot snapshot) async {
    await addOrUpdateData<Map>('cache', cacheKey, snapshot.toCacheMap());
  }
}
