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
