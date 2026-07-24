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

class SearchDiscoverySnapshot {
  const SearchDiscoverySnapshot({
    required this.trendingSearches,
    required this.topArtists,
    this.fetchedAt,
    this.fromCache = false,
  });

  final List<String> trendingSearches;
  final List<Map<String, dynamic>> topArtists;
  final DateTime? fetchedAt;
  final bool fromCache;

  bool get isEmpty => trendingSearches.isEmpty && topArtists.isEmpty;

  SearchDiscoverySnapshot copyWith({
    List<String>? trendingSearches,
    List<Map<String, dynamic>>? topArtists,
    DateTime? fetchedAt,
    bool? fromCache,
  }) {
    return SearchDiscoverySnapshot(
      trendingSearches: trendingSearches ?? this.trendingSearches,
      topArtists: topArtists ?? this.topArtists,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      fromCache: fromCache ?? this.fromCache,
    );
  }

  Map<String, dynamic> toCacheMap() {
    return {
      'trendingSearches': trendingSearches,
      'topArtists': topArtists,
      'fetchedAt': (fetchedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory SearchDiscoverySnapshot.fromCacheMap(
    Map<dynamic, dynamic> map, {
    bool fromCache = true,
  }) {
    final trending = (map['trendingSearches'] as List? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
    final artists = (map['topArtists'] as List? ?? const [])
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
    final fetchedRaw = map['fetchedAt']?.toString();
    return SearchDiscoverySnapshot(
      trendingSearches: trending,
      topArtists: artists,
      fetchedAt: fetchedRaw == null ? null : DateTime.tryParse(fetchedRaw),
      fromCache: fromCache,
    );
  }
}

enum SearchDiscoveryStatus { initial, loading, success, empty, error }

class SearchDiscoveryState {
  const SearchDiscoveryState({
    this.status = SearchDiscoveryStatus.initial,
    this.snapshot = const SearchDiscoverySnapshot(
      trendingSearches: [],
      topArtists: [],
    ),
    this.errorMessage,
  });

  final SearchDiscoveryStatus status;
  final SearchDiscoverySnapshot snapshot;
  final String? errorMessage;

  bool get isLoading => status == SearchDiscoveryStatus.loading;
  bool get showSkeleton =>
      isLoading && snapshot.trendingSearches.isEmpty && snapshot.topArtists.isEmpty;

  SearchDiscoveryState copyWith({
    SearchDiscoveryStatus? status,
    SearchDiscoverySnapshot? snapshot,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SearchDiscoveryState(
      status: status ?? this.status,
      snapshot: snapshot ?? this.snapshot,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
