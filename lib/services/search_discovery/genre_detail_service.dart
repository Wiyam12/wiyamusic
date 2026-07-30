import 'package:wiyamusic/main.dart' show logger;
import 'package:wiyamusic/services/playlists_manager.dart';

class GenreDetailItem {
  const GenreDetailItem({
    required this.title,
    required this.ytid,
    this.image,
    this.subtitle,
    this.isAlbum = false,
  });

  factory GenreDetailItem.fromPlaylistMap(Map map) {
    final isAlbum = map['isAlbum'] == true;
    return GenreDetailItem(
      title: map['title']?.toString() ?? 'Untitled',
      ytid: map['ytid']?.toString() ?? '',
      image: map['image']?.toString(),
      subtitle: isAlbum ? 'Album' : 'Playlist',
      isAlbum: isAlbum,
    );
  }

  final String title;
  final String ytid;
  final String? image;
  final String? subtitle;
  final bool isAlbum;
}

class GenreDetailSection {
  const GenreDetailSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<GenreDetailItem> items;
}

class GenreDetailSnapshot {
  const GenreDetailSnapshot({required this.sections});

  final List<GenreDetailSection> sections;

  bool get isEmpty =>
      sections.every((section) => section.items.isEmpty);
}

/// Loads YouTube playlist/album rows for a genre detail page.
class GenreDetailService {
  Future<GenreDetailSnapshot> load(String genre) async {
    final normalized = genre.trim();
    if (normalized.isEmpty) {
      return const GenreDetailSnapshot(sections: []);
    }

    try {
      final results = await Future.wait([
        getPlaylists(query: '$normalized Philippines', type: 'playlist'),
        getPlaylists(query: 'best $normalized', type: 'playlist'),
        getPlaylists(query: normalized, type: 'album'),
      ]);

      final regional = _mapItems(results[0]);
      final allThings = _mapItems(results[1], excludeIds: {
        for (final item in regional) item.ytid,
      });
      final releases = _mapItems(results[2], excludeIds: {
        for (final item in [...regional, ...allThings]) item.ytid,
      });

      final sections = <GenreDetailSection>[
        GenreDetailSection(
          title: '$normalized in the Philippines',
          items: regional.take(12).toList(growable: false),
        ),
        GenreDetailSection(
          title: 'All Things $normalized',
          items: allThings.take(12).toList(growable: false),
        ),
        GenreDetailSection(
          title: 'New $normalized Releases',
          items: releases.take(12).toList(growable: false),
        ),
      ].where((section) => section.items.isNotEmpty).toList(growable: false);

      return GenreDetailSnapshot(sections: sections);
    } catch (e, stackTrace) {
      logger.log(
        'GenreDetailService.load failed for "$normalized"',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  List<GenreDetailItem> _mapItems(
    List raw, {
    Set<String> excludeIds = const {},
  }) {
    final items = <GenreDetailItem>[];
    final seen = <String>{...excludeIds};

    for (final entry in raw) {
      if (entry is! Map) continue;
      final item = GenreDetailItem.fromPlaylistMap(
        Map<String, dynamic>.from(entry),
      );
      if (item.ytid.isEmpty || item.title.isEmpty) continue;
      if (!seen.add(item.ytid)) continue;
      items.add(item);
    }
    return items;
  }
}
