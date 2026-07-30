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
