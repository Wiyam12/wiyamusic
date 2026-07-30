import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wiyamusic/theme/design_tokens.dart';
import 'package:wiyamusic/utilities/artwork_provider.dart';
import 'package:wiyamusic/widgets/home/home_neon_play_button.dart';
import 'package:wiyamusic/widgets/no_artwork_cube.dart';

class HomeMediaCard extends StatelessWidget {
  const HomeMediaCard({
    super.key,
    required this.title,
    required this.onTap,
    required this.onPlay,
    this.imageUrl,
    this.subtitle,
    this.width = 148,
    this.showForYouBadge = false,
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final double width;
  final bool showForYouBadge;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final artworkSize = width;
    final isCompact = width < 130;
    final playButtonSize = isCompact ? 28.0 : 36.0;
    final playIconSize = isCompact ? 14.0 : 18.0;
    final playInset = isCompact ? 8.0 : 10.0;
    final titleSize = isCompact ? 12.5 : 14.0;
    final subtitleSize = isCompact ? 11.0 : 12.0;

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: WiyaDesign.borderRadius,
              child: Ink(
                width: artworkSize,
                height: artworkSize,
                decoration: BoxDecoration(
                  borderRadius: WiyaDesign.borderRadius,
                  boxShadow: WiyaDesign.softGlow(
                    color: colorScheme.primary,
                    blur: isCompact ? 12 : 18,
                    opacity: isCompact ? 0.12 : 0.18,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: WiyaDesign.borderRadius,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _Artwork(imageUrl: imageUrl, size: artworkSize),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              WiyaDesign.background.withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                      ),
                      if (showForYouBadge)
                        const Positioned(
                          top: 0,
                          left: 0,
                          child: _ForYouBadge(),
                        ),
                      Positioned(
                        right: playInset,
                        bottom: playInset,
                        child: HomeNeonPlayButton(
                          onPressed: onPlay,
                          size: playButtonSize,
                          iconSize: playIconSize,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: isCompact ? 6 : 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: titleSize,
              height: 1.15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: subtitleSize,
                height: 1.15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.imageUrl, required this.size});

  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return SizedBox.expand(
        child: NullArtworkWidget(
          size: size,
          borderRadius: WiyaDesign.cornerRadius,
        ),
      );
    }

    try {
      return SizedBox.expand(
        child: Image(
          image: ArtworkProvider.get(url),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => NullArtworkWidget(
            size: size,
            borderRadius: WiyaDesign.cornerRadius,
          ),
        ),
      );
    } catch (_) {
      return SizedBox.expand(
        child: NullArtworkWidget(
          size: size,
          borderRadius: WiyaDesign.cornerRadius,
        ),
      );
    }
  }
}

class _ForYouBadge extends StatelessWidget {
  const _ForYouBadge();

  static const double _size = 84;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: _size,
      height: _size,
      child: CustomPaint(painter: _ForYouRibbonPainter()),
    );
  }
}

class _ForYouRibbonPainter extends CustomPainter {
  const _ForYouRibbonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Parallelogram band inset from the corner so text clears the card's
    // rounded ClipRRect (radius 28) and stays fully inside the ribbon.
    const inner = 26.0;
    const outer = 52.0;

    final ribbon = Path()
      ..moveTo(0, inner)
      ..lineTo(0, outer)
      ..lineTo(outer, 0)
      ..lineTo(inner, 0)
      ..close();

    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          WiyaDesign.primaryBright,
          WiyaDesign.primary,
          WiyaDesign.primaryDeep,
        ],
      ).createShader(Offset.zero & size);

    canvas.drawPath(ribbon, paint);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'For You',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    // Center of the ribbon band along the diagonal.
    final mid = const Offset((inner + outer) / 4, (inner + outer) / 4);
    canvas
      ..save()
      ..translate(mid.dx, mid.dy)
      ..rotate(-math.pi / 4);
    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
