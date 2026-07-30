import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:wiyamusic/models/song_lyrics.dart';

class LyricsManager {
  static const _lrclibClient = 'WiyaMusic (https://github.com/Wiyam12/wiyamusic)';

  Future<SongLyrics?> fetchLyrics(
    String artistName,
    String title, {
    String? albumName,
    Duration? duration,
  }) async {
    // Remove Lyrics/Karaoke only from end of title
    if (title.endsWith(' Lyrics')) {
      title = title.substring(0, title.length - 7).trim();
    } else if (title.endsWith(' Karaoke')) {
      title = title.substring(0, title.length - 8).trim();
    }

    if (title.isEmpty || artistName.isEmpty) {
      return null;
    }

    final fromLrclib = await _fetchFromLrclib(
      artistName: artistName,
      title: title,
      albumName: albumName,
      duration: duration,
    );
    if (fromLrclib != null && !fromLrclib.isEmpty) {
      return fromLrclib;
    }

    final lyricsFromLyricsOvh = await _fetchLyricsFromLyricsOvh(
      artistName,
      title,
    );
    if (lyricsFromLyricsOvh != null) {
      return SongLyrics(plain: lyricsFromLyricsOvh);
    }

    final lyricsFromParolesNet = await _fetchLyricsFromParolesNet(
      artistName.split(',')[0],
      title,
    );
    if (lyricsFromParolesNet != null) {
      return SongLyrics(plain: lyricsFromParolesNet);
    }

    final lyricsFromLyricsMania1 = await _fetchLyricsFromLyricsMania1(
      artistName,
      title,
    );
    if (lyricsFromLyricsMania1 != null) {
      return SongLyrics(plain: lyricsFromLyricsMania1);
    }
    return null;
  }

  /// Prefer LRCLIB for timed (LRC) lyrics used for active-line highlighting.
  Future<SongLyrics?> _fetchFromLrclib({
    required String artistName,
    required String title,
    String? albumName,
    Duration? duration,
  }) async {
    try {
      final artist = artistName.split(',').first.trim();
      final query = <String, String>{
        'track_name': title,
        'artist_name': artist,
      };
      if (albumName != null && albumName.trim().isNotEmpty) {
        query['album_name'] = albumName.trim();
      }

      final searchUri = Uri.https('lrclib.net', '/api/search', query);
      final searchResponse = await http
          .get(searchUri, headers: {'Lrclib-Client': _lrclibClient})
          .timeout(const Duration(seconds: 10));

      if (searchResponse.statusCode != 200) return null;

      final results = jsonDecode(searchResponse.body);
      if (results is! List || results.isEmpty) return null;

      Map<String, dynamic>? best;
      var bestScore = -1;
      final durationSeconds = duration?.inSeconds;

      for (final raw in results) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final synced = item['syncedLyrics'] as String?;
        final plain = item['plainLyrics'] as String?;
        if ((synced == null || synced.isEmpty) &&
            (plain == null || plain.isEmpty)) {
          continue;
        }

        var score = 0;
        if (synced != null && synced.isNotEmpty) score += 100;
        if (plain != null && plain.isNotEmpty) score += 10;

        final itemDuration = item['duration'];
        if (durationSeconds != null && itemDuration is num) {
          final diff = (itemDuration.round() - durationSeconds).abs();
          if (diff <= 2) {
            score += 50;
          } else if (diff <= 5) {
            score += 25;
          } else if (diff <= 15) {
            score += 5;
          } else {
            score -= 20;
          }
        }

        if (score > bestScore) {
          bestScore = score;
          best = item;
        }
      }

      if (best == null) return null;

      final syncedRaw = best['syncedLyrics'] as String?;
      final plainRaw = best['plainLyrics'] as String?;
      final syncedLines = syncedRaw != null && syncedRaw.isNotEmpty
          ? parseLrc(syncedRaw)
          : const <LyricLine>[];

      var plain = plainRaw;
      if (plain != null && plain.isNotEmpty) {
        plain = addCopyright(plain, 'lrclib.net');
      } else if (syncedLines.isNotEmpty) {
        plain = addCopyright(
          syncedLines.map((l) => l.text).join('\n'),
          'lrclib.net',
        );
      }

      return SongLyrics(
        plain: plain,
        syncedLines: syncedLines,
        syncedRaw: syncedLines.isNotEmpty ? syncedRaw : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchLyricsFromLyricsOvh(
    String artistName,
    String title,
  ) async {
    try {
      final artistFormatted = _lyricsUrl(artistName.split(',')[0]);
      final titleFormatted = _lyricsUrl(title);
      final uri = Uri.parse(
        'https://api.lyrics.ovh/v1/$artistFormatted/$titleFormatted',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final lyrics = json['lyrics'] as String?;
        if (lyrics != null && lyrics.isNotEmpty) {
          return addCopyright(lyrics, 'lyrics.ovh');
        }
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  Future<String?> _fetchLyricsFromParolesNet(
    String artistName,
    String title,
  ) async {
    try {
      final uri = Uri.parse(
        'https://www.paroles.net/${_lyricsUrl(artistName)}/paroles-${_lyricsUrl(title)}',
      );
      final response = await http
          .get(uri)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => http.Response('', 408),
          );

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        final songTextElements = document.querySelectorAll('.song-text');

        if (songTextElements.isNotEmpty) {
          final lyricsLines = songTextElements.first.text.split('\n');
          if (lyricsLines.length > 1) {
            lyricsLines.removeAt(0);

            final finalLyrics = addCopyright(
              lyricsLines.join('\n'),
              'www.paroles.net',
            );
            return _removeSpaces(finalLyrics);
          }
        }
      }
    } catch (e) {
      return null;
    }

    return null;
  }

  Future<String?> _fetchLyricsFromLyricsMania1(
    String artistName,
    String title,
  ) async {
    try {
      final uri = Uri.parse(
        'https://www.lyricsmania.com/${_lyricsManiaUrl(title)}_lyrics_${_lyricsManiaUrl(artistName)}.html',
      );
      final response = await http
          .get(uri)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => http.Response('', 408),
          );

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        final lyricsBodyElements = document.querySelectorAll('.lyrics-body');

        if (lyricsBodyElements.isNotEmpty) {
          return addCopyright(
            lyricsBodyElements.first.text,
            'www.lyricsmania.com',
          );
        }
      }
    } catch (e) {
      return null;
    }

    return null;
  }

  String _lyricsUrl(String input) {
    var result = input.replaceAll(' ', '-').toLowerCase();
    result = result.replaceAll(RegExp('[^a-z0-9-]'), '');
    result = result.replaceAll(RegExp('-+'), '-');
    if (result.isNotEmpty && result.endsWith('-')) {
      result = result.substring(0, result.length - 1);
    }
    if (result.isNotEmpty && result.startsWith('-')) {
      result = result.substring(1);
    }
    return result;
  }

  String _lyricsManiaUrl(String input) {
    var result = input.replaceAll(' ', '_').toLowerCase();
    if (result.isNotEmpty && result.startsWith('_')) {
      result = result.substring(1);
    }
    if (result.isNotEmpty && result.endsWith('_')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  String _removeSpaces(String input) {
    return input.replaceAll(RegExp(' {2,}'), ' ');
  }

  String addCopyright(String input, String copyright) {
    return '$input\n\n© $copyright';
  }
}

/// Parses standard and enhanced (word-timed) LRC into [LyricLine]s.
List<LyricLine> parseLrc(String lrc) {
  final lineTag = RegExp(
    r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]',
  );
  final wordTag = RegExp(
    r'<(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?>',
  );

  final lines = <LyricLine>[];

  for (final rawLine in lrc.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    // Skip metadata tags like [ar:], [ti:], [length:]
    if (RegExp(r'^\[[a-zA-Z]+:').hasMatch(line)) continue;

    final timestamps = lineTag.allMatches(line).toList();
    if (timestamps.isEmpty) continue;

    final contentStart = timestamps.last.end;
    final content = line.substring(contentStart).trim();
    if (content.isEmpty) continue;

    final words = <LyricWord>[];
    final wordMatches = wordTag.allMatches(content).toList();
    if (wordMatches.isNotEmpty) {
      for (var i = 0; i < wordMatches.length; i++) {
        final match = wordMatches[i];
        final end = i + 1 < wordMatches.length
            ? wordMatches[i + 1].start
            : content.length;
        final wordText = content.substring(match.end, end).trim();
        if (wordText.isEmpty) continue;
        words.add(
          LyricWord(text: wordText, start: _parseLrcTime(match)),
        );
      }
    }

    final plainText = content.replaceAll(wordTag, '').replaceAll(
      RegExp(r'\s+'),
      ' ',
    ).trim();
    if (plainText.isEmpty) continue;

    for (final tag in timestamps) {
      lines.add(
        LyricLine(
          start: _parseLrcTime(tag),
          text: plainText,
          words: words,
        ),
      );
    }
  }

  lines.sort((a, b) => a.start.compareTo(b.start));
  return lines;
}

Duration _parseLrcTime(RegExpMatch match) {
  final minutes = int.parse(match.group(1)!);
  final seconds = int.parse(match.group(2)!);
  final fraction = match.group(3);
  var milliseconds = 0;
  if (fraction != null) {
    // Support .1, .12, .123 and also centiseconds-style values.
    final padded = fraction.length >= 3
        ? fraction.substring(0, 3)
        : fraction.padRight(3, '0');
    milliseconds = int.parse(padded);
  }
  return Duration(
    minutes: minutes,
    seconds: seconds,
    milliseconds: milliseconds,
  );
}
