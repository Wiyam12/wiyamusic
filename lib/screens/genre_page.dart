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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:wiyamusic/main.dart' show logger;
import 'package:wiyamusic/services/search_discovery/genre_detail_service.dart';
import 'package:wiyamusic/theme/design_tokens.dart';
import 'package:wiyamusic/utilities/artwork_provider.dart';
import 'package:wiyamusic/widgets/mini_player_bottom_space.dart';
import 'package:wiyamusic/widgets/search/search_discovery.dart';

class GenrePage extends StatefulWidget {
  const GenrePage({super.key, required this.genreName});

  final String genreName;

  @override
  State<GenrePage> createState() => _GenrePageState();
}

class _GenrePageState extends State<GenrePage> {
  final GenreDetailService _service = GenreDetailService();
  GenreDetailSnapshot _snapshot = const GenreDetailSnapshot(sections: []);
  bool _loading = true;
  String? _error;

  String get _genre => widget.genreName.trim();

  SearchGenreItem? get _genreMeta {
    for (final genre in buildBrowseGenres()) {
      if (genre.name.toLowerCase() == _genre.toLowerCase()) return genre;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final snapshot = await _service.load(_genre);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (e, stackTrace) {
      logger.log(
        'GenrePage load failed for "$_genre"',
        error: e,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load $_genre';
      });
    }
  }

  Future<void> _share() async {
    await SharePlus.instance.share(
      ShareParams(text: 'Explore $_genre on WiyaMusic'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _genreAccent(_genre);
    final expandedHeight = MediaQuery.sizeOf(context).height * 0.34;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: RefreshIndicator(
        color: colorScheme.primary,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: expandedHeight,
              pinned: true,
              stretch: true,
              backgroundColor: colorScheme.surface,
              foregroundColor: Colors.white,
              leading: IconButton(
                icon: const Icon(FluentIcons.arrow_left_24_regular),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              actions: [
                IconButton(
                  icon: const Icon(FluentIcons.share_24_regular),
                  onPressed: _share,
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                title: Text(
                  _genre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1,
                  ),
                ),
                background: _GenreHeaderBackground(
                  accent: accent,
                  imageAsset: _genreMeta?.imageAsset,
                ),
              ),
            ),
            if (_loading)
              SliverToBoxAdapter(
                child: Skeletonizer(
                  child: _GenreSections(
                    genre: _genre,
                    sections: List.generate(
                      3,
                      (i) => GenreDetailSection(
                        title: 'Loading section $i',
                        items: List.generate(
                          4,
                          (j) => GenreDetailItem(
                            title: 'Playlist $j',
                            ytid: 'skeleton_$i$j',
                            subtitle: 'Playlist',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _GenreEmptyState(message: _error!, onRetry: _load),
              )
            else if (_snapshot.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _GenreEmptyState(
                  message: 'No playlists found for this genre',
                ),
              )
            else
              SliverToBoxAdapter(
                child: _GenreSections(
                  genre: _genre,
                  sections: _snapshot.sections,
                ),
              ),
            const SliverToBoxAdapter(child: MiniPlayerBottomSpace()),
          ],
        ),
      ),
    );
  }
}

class _GenreHeaderBackground extends StatelessWidget {
  const _GenreHeaderBackground({required this.accent, this.imageAsset});

  final Color accent;
  final String? imageAsset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (imageAsset != null)
          Image.asset(
            imageAsset!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                accent.withValues(alpha: imageAsset == null ? 0.95 : 0.72),
                WiyaDesign.primaryDeep.withValues(alpha: 0.85),
                WiyaDesign.background.withValues(alpha: 0.98),
                WiyaDesign.background,
              ],
              stops: const [0, 0.45, 0.82, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                WiyaDesign.primaryBright.withValues(alpha: 0.35),
                Colors.transparent,
                accent.withValues(alpha: 0.25),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GenreSections extends StatelessWidget {
  const _GenreSections({required this.genre, required this.sections});

  final String genre;
  final List<GenreDetailSection> sections;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in sections) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
            child: Text(
              section.title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          SizedBox(
            height: 222,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: section.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                return _GenreMediaCard(
                  genre: genre,
                  item: section.items[index],
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

class _GenreMediaCard extends StatelessWidget {
  const _GenreMediaCard({required this.genre, required this.item});

  final String genre;
  final GenreDetailItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 148,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: WiyaDesign.borderRadiusMedium,
          onTap: () {
            if (item.ytid.isEmpty) return;
            context.push(
              '/home/playlist/${item.ytid}',
              extra: {
                'ytid': item.ytid,
                'title': item.title,
                'image': item.image,
                'isAlbum': item.isAlbum,
                'genre': genre,
              },
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: WiyaDesign.borderRadiusMedium,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      boxShadow: WiyaDesign.softGlow(
                        color: colorScheme.primary,
                        blur: 16,
                        opacity: 0.12,
                      ),
                    ),
                    child: item.image != null && item.image!.isNotEmpty
                        ? Image(
                            image: ArtworkProvider.get(item.image!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _ArtworkFallback(isAlbum: item.isAlbum),
                          )
                        : _ArtworkFallback(isAlbum: item.isAlbum),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                (item.subtitle ?? (item.isAlbum ? 'Album' : 'Playlist'))
                    .toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.isAlbum});

  final bool isAlbum;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WiyaDesign.surfaceHigh,
      child: Center(
        child: Icon(
          isAlbum ? FluentIcons.album_24_regular : FluentIcons.list_24_regular,
          color: WiyaDesign.primaryBright.withValues(alpha: 0.7),
          size: 36,
        ),
      ),
    );
  }
}

class _GenreEmptyState extends StatelessWidget {
  const _GenreEmptyState({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.music_note_2_24_regular,
              size: 40,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

Color _genreAccent(String genre) {
  switch (genre.trim().toLowerCase()) {
    case 'pop':
      return const Color(0xFFE879F9);
    case 'hip hop':
      return const Color(0xFFF59E0B);
    case 'rock':
      return const Color(0xFFF43F5E);
    case 'r&b':
      return const Color(0xFFA78BFA);
    case 'electronic':
      return WiyaDesign.primaryBright;
    case 'acoustic':
      return const Color(0xFF34D399);
    default:
      return WiyaDesign.primary;
  }
}
