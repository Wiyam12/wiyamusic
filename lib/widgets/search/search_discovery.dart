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
import 'package:skeletonizer/skeletonizer.dart';
import 'package:wiyamusic/services/artist_service.dart';
import 'package:wiyamusic/theme/design_tokens.dart';
import 'package:wiyamusic/utilities/artwork_provider.dart';
import 'package:wiyamusic/widgets/home/home_section_header.dart';

class SearchGenreItem {
  const SearchGenreItem({required this.name, this.imageAsset, this.imageUrl});

  final String name;
  final String? imageAsset;
  final String? imageUrl;
}

List<SearchGenreItem> buildBrowseGenres() {
  return const [
    SearchGenreItem(name: 'Pop', imageAsset: 'assets/images/pop.png'),
    SearchGenreItem(name: 'Hip Hop', imageAsset: 'assets/images/hiphop.png'),
    SearchGenreItem(name: 'Rock', imageAsset: 'assets/images/rock.png'),
    SearchGenreItem(name: 'R&B', imageAsset: 'assets/images/r&b.png'),
    SearchGenreItem(
      name: 'Electronic',
      imageAsset: 'assets/images/electronic.png',
    ),
    SearchGenreItem(
      name: 'Acoustic',
      imageAsset: 'assets/images/acoustic.png',
    ),
  ];
}

class SearchDiscoveryContent extends StatelessWidget {
  const SearchDiscoveryContent({
    super.key,
    required this.trendingSearches,
    required this.topArtists,
    required this.onTrendingTap,
    required this.onGenreTap,
    required this.onArtistTap,
    required this.onSeeAllArtists,
    this.onSeeAllGenres,
    this.isLoading = false,
    this.showEmpty = false,
    this.onRetry,
  });

  final List<String> trendingSearches;
  final List<Map<String, dynamic>> topArtists;
  final ValueChanged<String> onTrendingTap;
  final ValueChanged<String> onGenreTap;
  final ValueChanged<Map<String, dynamic>> onArtistTap;
  final VoidCallback? onSeeAllGenres;
  final VoidCallback onSeeAllArtists;
  final bool isLoading;
  final bool showEmpty;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final genres = buildBrowseGenres();
    final colorScheme = Theme.of(context).colorScheme;

    if (showEmpty && !isLoading) {
      return _DiscoveryEmptyState(onRetry: onRetry);
    }

    final trending = isLoading && trendingSearches.isEmpty
        ? List.generate(6, (i) => 'Loading artist $i')
        : trendingSearches.take(6).toList();
    final artists = isLoading && topArtists.isEmpty
        ? List.generate(
            4,
            (i) => <String, dynamic>{
              'title': 'Artist Name $i',
              'ytid': 'skeleton_$i',
              'image': null,
            },
          )
        : topArtists;

    return Skeletonizer(
      enabled: isLoading && trendingSearches.isEmpty && topArtists.isEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HomeSectionHeader(title: 'Trending Searches'),
          if (trending.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'No trending searches right now',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final query in trending.take(6))
                  _TrendingChip(
                    label: query,
                    onTap: () => onTrendingTap(query),
                  ),
              ],
            ),
          HomeSectionHeader(
            title: 'Browse by Genre',
            onAction: onSeeAllGenres,
          ),
          GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: genres.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.15,
            ),
            itemBuilder: (context, index) {
              final genre = genres[index];
              return _GenreCard(
                genre: genre,
                onTap: () => onGenreTap(genre.name),
              );
            },
          ),
          HomeSectionHeader(
            title: 'Top Artists',
            onAction: onSeeAllArtists,
            padding: const EdgeInsets.fromLTRB(2, 10, 2, 12),
          ),
          if (artists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No top artists available',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          else
            SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: artists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  final artist = artists[index];
                  return _TopArtistAvatar(
                    artist: artist,
                    onTap: () => onArtistTap(artist),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _DiscoveryEmptyState extends StatelessWidget {
  const _DiscoveryEmptyState({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
      child: Column(
        children: [
          Icon(
            FluentIcons.cloud_off_24_regular,
            size: 40,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Couldn’t load discovery content',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Check your connection and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(FluentIcons.arrow_clockwise_24_regular),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}

class SearchRecentTile extends StatelessWidget {
  const SearchRecentTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onRemove,
    this.isArtist = false,
    this.imageUrl,
  });

  final String title;
  final String subtitle;
  final String? imageUrl;
  final bool isArtist;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              _RecentLeading(imageUrl: imageUrl, isArtist: isArtist),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  FluentIcons.dismiss_24_regular,
                  color: colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendingChip extends StatelessWidget {
  const _TrendingChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
          child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: WiyaDesign.primaryBright.withValues(alpha: 0.18),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _GenreCard extends StatelessWidget {
  const _GenreCard({required this.genre, required this.onTap});

  final SearchGenreItem genre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: WiyaDesign.borderRadiusMedium,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: WiyaDesign.borderRadiusMedium,
            color: colorScheme.surfaceContainerHigh,
            border: Border.all(
              color: WiyaDesign.primaryBright.withValues(alpha: 0.22),
            ),
            boxShadow: WiyaDesign.softGlow(
              color: colorScheme.primary,
              blur: 14,
              opacity: 0.12,
            ),
          ),
          child: ClipRRect(
            borderRadius: WiyaDesign.borderRadiusMedium,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (genre.imageAsset != null)
                  Image.asset(
                    genre.imageAsset!,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  )
                else if (genre.imageUrl != null)
                  Image(
                    image: ArtworkProvider.get(genre.imageUrl!),
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                // Dark navy tint so white title stays readable.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF050B1B).withValues(alpha: 0.72),
                        const Color(0xFF0F172A).withValues(alpha: 0.45),
                        const Color(0xFF050B1B).withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      genre.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        shadows: [
                          Shadow(
                            color: Color(0x66000000),
                            blurRadius: 8,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopArtistAvatar extends StatelessWidget {
  const _TopArtistAvatar({required this.artist, required this.onTap});

  final Map<String, dynamic> artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = normalizeArtistDisplayTitle(
      artist['title']?.toString() ?? 'Artist',
    );
    final image = normalizeArtistThumbnailUrl(artist['image']?.toString());

    return SizedBox(
      width: 88,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: WiyaDesign.primaryBright.withValues(alpha: 0.7),
                  width: 2,
                ),
                boxShadow: WiyaDesign.softGlow(
                  color: colorScheme.primary,
                  blur: 14,
                  opacity: 0.28,
                ),
              ),
              child: ClipOval(
                child: image == null || image.isEmpty
                    ? ColoredBox(
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(
                          FluentIcons.person_24_filled,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Image(
                        image: ArtworkProvider.get(image),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => ColoredBox(
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            FluentIcons.person_24_filled,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentLeading extends StatelessWidget {
  const _RecentLeading({required this.isArtist, this.imageUrl});

  final bool isArtist;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const size = 52.0;
    final radius = isArtist ? 999.0 : 12.0;

    Widget fallback = ColoredBox(
      color: colorScheme.surfaceContainerHigh,
      child: Icon(
        isArtist
            ? FluentIcons.person_24_filled
            : FluentIcons.search_24_regular,
        color: colorScheme.onSurfaceVariant,
      ),
    );

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      try {
        fallback = Image(
          image: ArtworkProvider.get(imageUrl!),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        );
      } catch (_) {}
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: fallback),
    );
  }
}
