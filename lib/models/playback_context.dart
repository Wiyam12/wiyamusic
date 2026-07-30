/// Where the active queue was started from.
enum PlaybackSourceKind {
  likedSongs,
  playlist,
  album,
  artist,
  offlineSongs,
  recentlyPlayed,
  search,
  home,
  singleSong,
  offlineFallback,
  radio,
  other,
}

/// Session metadata describing the origin of the current playback queue.
class PlaybackContext {
  const PlaybackContext({required this.kind, this.id, this.title});

  factory PlaybackContext.fromMap(Map? map) {
    if (map == null) return PlaybackContext.singleSong();
    final kindName = map['kind']?.toString();
    final kind = PlaybackSourceKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => PlaybackSourceKind.other,
    );
    return PlaybackContext(
      kind: kind,
      id: map['id']?.toString(),
      title: map['title']?.toString(),
    );
  }

  factory PlaybackContext.singleSong({String? id, String? title}) =>
      PlaybackContext(
        kind: PlaybackSourceKind.singleSong,
        id: id,
        title: title,
      );

  factory PlaybackContext.offlineFallback() => const PlaybackContext(
    kind: PlaybackSourceKind.offlineFallback,
    title: 'Offline',
  );

  factory PlaybackContext.radio({String? id, String? title}) =>
      PlaybackContext(kind: PlaybackSourceKind.radio, id: id, title: title);

  /// Builds context from a playlist map and/or an explicit kind hint.
  ///
  /// Callers should prefer setting `playlist['playbackKind']` (or passing
  /// [explicit]) for library pages so liked/offline/recents are not ambiguous.
  factory PlaybackContext.resolve({
    Map? playlist,
    PlaybackContext? explicit,
    PlaybackSourceKind? kindHint,
  }) {
    if (explicit != null) return explicit;

    final rawKind = kindHint?.name ?? playlist?['playbackKind']?.toString();
    if (rawKind != null && rawKind.isNotEmpty) {
      final matched = PlaybackSourceKind.values.where((k) => k.name == rawKind);
      if (matched.isNotEmpty) {
        return PlaybackContext(
          kind: matched.first,
          id: playlist?['ytid']?.toString(),
          title: playlist?['title']?.toString(),
        );
      }
    }

    if (playlist == null) {
      return PlaybackContext.singleSong();
    }

    final source = playlist['source']?.toString();
    final title = playlist['title']?.toString();
    final id = playlist['ytid']?.toString();
    final isAlbum = playlist['isAlbum'] == true;
    final isArtist = playlist['isArtist'] == true || source == 'youtube-artist';

    if (isArtist) {
      return PlaybackContext(
        kind: PlaybackSourceKind.artist,
        id: id,
        title: title,
      );
    }
    if (isAlbum) {
      return PlaybackContext(
        kind: PlaybackSourceKind.album,
        id: id,
        title: title,
      );
    }

    // Known playlist-like sources from library / YouTube.
    if (source == 'user-created' ||
        source == 'user-youtube' ||
        source == 'youtube' ||
        (id != null && id.isNotEmpty)) {
      return PlaybackContext(
        kind: PlaybackSourceKind.playlist,
        id: id,
        title: title,
      );
    }

    final list = playlist['list'];
    if (list is List && list.length > 1) {
      return PlaybackContext(
        kind: PlaybackSourceKind.other,
        id: id,
        title: title,
      );
    }

    return PlaybackContext.singleSong(id: id, title: title);
  }

  final PlaybackSourceKind kind;
  final String? id;
  final String? title;

  /// Library (and library-like) collections that should loop as a queue.
  bool get isLibraryCollection => switch (kind) {
    PlaybackSourceKind.likedSongs ||
    PlaybackSourceKind.playlist ||
    PlaybackSourceKind.album ||
    PlaybackSourceKind.artist ||
    PlaybackSourceKind.offlineSongs ||
    PlaybackSourceKind.recentlyPlayed => true,
    _ => false,
  };

  bool get isOfflineFallback => kind == PlaybackSourceKind.offlineFallback;

  bool get isSingleSong => kind == PlaybackSourceKind.singleSong;

  PlaybackContext copyWith({
    PlaybackSourceKind? kind,
    String? id,
    String? title,
  }) {
    return PlaybackContext(
      kind: kind ?? this.kind,
      id: id ?? this.id,
      title: title ?? this.title,
    );
  }

  Map<String, dynamic> toMap() => {
    'kind': kind.name,
    if (id != null) 'id': id,
    if (title != null) 'title': title,
  };

  @override
  String toString() => 'PlaybackContext(kind: $kind, id: $id, title: $title)';
}
