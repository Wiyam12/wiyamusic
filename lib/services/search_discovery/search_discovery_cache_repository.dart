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
