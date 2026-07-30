import 'package:animated_icon/animated_icon.dart';
import 'package:flutter/material.dart';

/// Themed wrapper around [AnimateIcon] for consistent brand usage.
class WiyaAnimatedIcon extends StatelessWidget {
  const WiyaAnimatedIcon({
    super.key,
    required this.icon,
    this.size = 48,
    this.color,
    this.iconType = IconType.continueAnimation,
    this.onTap,
  });

  final AnimateIcons icon;
  final double size;
  final Color? color;
  final IconType iconType;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? Theme.of(context).colorScheme.primary;

    final animated = AnimateIcon(
      key: ValueKey('wiya-animated-${icon.name}-$size'),
      iconType: iconType,
      animateIcon: icon,
      height: size,
      width: size,
      color: resolvedColor,
      onTap: onTap ?? () {},
    );

    // AnimateIcon always installs its own gesture detector. When this widget is
    // decorative (nav icons, spinners, playing indicators), ignore those
    // gestures so parent taps still work.
    if (onTap == null) {
      // AnimateIcon builds an InkWell, which asserts on a missing Material
      // ancestor. Decorative usages such as spinners can render outside one
      // (bare dialogs, image placeholders), so supply a transparent Material.
      return IgnorePointer(
        child: Material(type: MaterialType.transparency, child: animated),
      );
    }
    return animated;
  }
}
