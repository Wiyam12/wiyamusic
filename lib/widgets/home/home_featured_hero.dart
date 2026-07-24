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

import 'dart:ui';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/theme/design_tokens.dart';
import 'package:wiyamusic/utilities/artwork_provider.dart';
import 'package:wiyamusic/widgets/home/home_neon_play_button.dart';
import 'package:wiyamusic/widgets/no_artwork_cube.dart';

class HomeFeaturedHero extends StatefulWidget {
  const HomeFeaturedHero({
    super.key,
    required this.playlists,
    required this.onOpen,
    required this.onPlay,
  });

  final List<dynamic> playlists;
  final ValueChanged<Map> onOpen;
  final ValueChanged<Map> onPlay;

  @override
  State<HomeFeaturedHero> createState() => _HomeFeaturedHeroState();
}

class _HomeFeaturedHeroState extends State<HomeFeaturedHero> {
  late final PageController _pageController;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.94);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.playlists.take(5).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    final height = MediaQuery.sizeOf(context).height * 0.34;
    final clampedHeight = height.clamp(220.0, 300.0);

    return Column(
      children: [
        SizedBox(
          height: clampedHeight,
          child: PageView.builder(
            controller: _pageController,
            itemCount: items.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, index) {
              final playlist = Map<String, dynamic>.from(items[index] as Map);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _HeroCard(
                  playlist: playlist,
                  onOpen: () => widget.onOpen(playlist),
                  onPlay: () => widget.onPlay(playlist),
                ),
              );
            },
          ),
        ),
        if (items.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(items.length, (i) {
              final selected = i == _index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: selected ? 8 : 6,
                height: selected ? 8 : 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.28),
                  boxShadow: selected
                      ? WiyaDesign.softGlow(
                          color: WiyaDesign.primaryBright,
                          blur: 10,
                          opacity: 0.4,
                        )
                      : null,
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.playlist,
    required this.onOpen,
    required this.onPlay,
  });

  final Map playlist;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = playlist['title']?.toString() ?? '';
    final image = playlist['image']?.toString();
    final isAlbum = playlist['isAlbum'] == true;
    final typeLabel = (isAlbum
            ? context.l10n?.album
            : context.l10n?.playlist)
        ?.toUpperCase();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: WiyaDesign.borderRadius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: WiyaDesign.borderRadius,
            boxShadow: WiyaDesign.softGlow(
              color: colorScheme.primary,
              blur: 28,
            ),
          ),
          child: ClipRRect(
            borderRadius: WiyaDesign.borderRadius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _HeroArtwork(imageUrl: image),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        WiyaDesign.background.withValues(alpha: 0.15),
                        WiyaDesign.background.withValues(alpha: 0.35),
                        WiyaDesign.primaryDeep.withValues(alpha: 0.55),
                        WiyaDesign.background.withValues(alpha: 0.92),
                      ],
                      stops: const [0, 0.35, 0.7, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 18,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      WiyaDesign.cornerRadiusMedium,
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: WiyaDesign.blurSigma * 0.35,
                        sigmaY: WiyaDesign.blurSigma * 0.35,
                      ),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(
                            WiyaDesign.cornerRadiusMedium,
                          ),
                          border: Border.all(
                            color: WiyaDesign.primaryBright.withValues(
                              alpha: 0.22,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              typeLabel ?? 'DISCOVER',
                              style: const TextStyle(
                                color: WiyaDesign.primaryBright,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isAlbum
                                  ? (context.l10n?.album ?? 'Album')
                                  : (context.l10n?.suggestedPlaylists ??
                                        'Suggested playlists'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _PlayNowButton(
                                    label: context.l10n?.play ?? 'Play',
                                    onPressed: onPlay,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                HomeNeonPlayButton(
                                  onPressed: onPlay,
                                  size: 46,
                                  iconSize: 22,
                                ),
                              ],
                            ),
                          ],
                        ),
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

class _PlayNowButton extends StatelessWidget {
  const _PlayNowButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: const LinearGradient(
              colors: [
                WiyaDesign.primaryBright,
                WiyaDesign.primary,
                WiyaDesign.primaryDeep,
              ],
            ),
            boxShadow: WiyaDesign.softGlow(
              color: WiyaDesign.primary,
              blur: 18,
              opacity: 0.42,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                FluentIcons.play_24_filled,
                size: 18,
                color: WiyaDesign.onPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                '$label Now',
                style: const TextStyle(
                  color: WiyaDesign.onPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroArtwork extends StatelessWidget {
  const _HeroArtwork({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return const ColoredBox(
        color: WiyaDesign.surface,
        child: NullArtworkWidget(size: 280, borderRadius: WiyaDesign.cornerRadius),
      );
    }

    try {
      return Image(
        image: ArtworkProvider.get(url),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: WiyaDesign.surface,
          child: NullArtworkWidget(
            size: 280,
            borderRadius: WiyaDesign.cornerRadius,
          ),
        ),
      );
    } catch (_) {
      return const ColoredBox(
        color: WiyaDesign.surface,
        child: NullArtworkWidget(
          size: 280,
          borderRadius: WiyaDesign.cornerRadius,
        ),
      );
    }
  }
}
