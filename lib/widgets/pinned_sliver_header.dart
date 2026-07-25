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

import 'package:flutter/material.dart';

/// A fixed-height pinned header for [CustomScrollView].
class PinnedSliverHeader extends StatelessWidget {
  const PinnedSliverHeader({
    super.key,
    required this.height,
    required this.child,
    this.backgroundColor,
  });

  final double height;
  final Widget child;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final color =
        backgroundColor ?? Theme.of(context).scaffoldBackgroundColor;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PinnedHeaderDelegate(
        height: height,
        backgroundColor: color,
        child: child,
      ),
    );
  }
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedHeaderDelegate({
    required this.height,
    required this.backgroundColor,
    required this.child,
  });

  final double height;
  final Color backgroundColor;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Must fill the declared extent exactly — if the child is shorter,
    // SliverGeometry asserts (layoutExtent > paintExtent).
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ColoredBox(
        color: backgroundColor,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) {
    return height != oldDelegate.height ||
        backgroundColor != oldDelegate.backgroundColor ||
        child != oldDelegate.child;
  }
}
