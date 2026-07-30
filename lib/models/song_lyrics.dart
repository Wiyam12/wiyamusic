class LyricWord {
  const LyricWord({required this.text, required this.start});

  final String text;
  final Duration start;
}

class LyricLine {
  const LyricLine({
    required this.start,
    required this.text,
    this.words = const [],
  });

  final Duration start;
  final String text;
  final List<LyricWord> words;

  bool get hasWordTimings => words.length > 1;
}

class SongLyrics {
  const SongLyrics({this.plain, this.syncedLines = const [], this.syncedRaw});

  final String? plain;
  final List<LyricLine> syncedLines;

  /// Original LRC payload, kept so lyrics can be cached for offline use.
  final String? syncedRaw;

  bool get hasSynced => syncedLines.isNotEmpty;
  bool get isEmpty =>
      (plain == null || plain!.trim().isEmpty) && syncedLines.isEmpty;

  String get displayPlain {
    if (plain != null && plain!.trim().isNotEmpty) return plain!;
    return syncedLines.map((l) => l.text).join('\n');
  }

  Map<String, dynamic> toJson() => {
    if (plain != null) 'plain': plain,
    if (syncedRaw != null) 'synced': syncedRaw,
  };
}
