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
