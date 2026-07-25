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
