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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wiyamusic/services/router_service.dart';
import 'package:wiyamusic/theme/design_tokens.dart';

/// Coordinates Home → Search “enter search mode” transitions.
abstract final class SearchNavigation {
  /// Bumped whenever Search should autofocus its field and open the keyboard.
  static final ValueNotifier<int> autofocusToken = ValueNotifier<int>(0);

  static void requestAutofocus() {
    autofocusToken.value++;
  }

  /// Opens the Search tab, optionally playing a lightweight expand preview
  /// from [origin] (the tapped search entry’s global rect).
  static Future<void> openSearch(
    BuildContext context, {
    Rect? origin,
  }) async {
    requestAutofocus();

    if (origin != null && context.mounted) {
      // Start morph immediately; navigation follows so the destination
      // can fade in under the preview without a hard cut.
      unawaited(_playExpandPreview(context, origin));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    if (!context.mounted) return;
    context.go(NavigationManager.searchPath);
  }

  static Future<void> _playExpandPreview(BuildContext context, Rect origin) {
    final overlay = Overlay.of(context);
    final mediaQuery = MediaQuery.of(context);
    final topInset = mediaQuery.padding.top;
    // Approximate destination: under a typical app bar + search padding.
    final end = Rect.fromLTWH(
      10,
      topInset + 56 + 8,
      mediaQuery.size.width - 20,
      origin.height,
    );

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return IgnorePointer(
          child: _SearchExpandPreview(
            begin: origin,
            end: end,
            onCompleted: () {
              entry.remove();
            },
          ),
        );
      },
    );

    overlay.insert(entry);
    return Future<void>.delayed(const Duration(milliseconds: 260));
  }
}

class _SearchExpandPreview extends StatefulWidget {
  const _SearchExpandPreview({
    required this.begin,
    required this.end,
    required this.onCompleted,
  });

  final Rect begin;
  final Rect end;
  final VoidCallback onCompleted;

  @override
  State<_SearchExpandPreview> createState() => _SearchExpandPreviewState();
}

class _SearchExpandPreviewState extends State<_SearchExpandPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;
  late final Animation<Rect?> _rect;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _rect = RectTween(begin: widget.begin, end: widget.end).animate(_curve);
    _opacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.55, 1, curve: Curves.easeOut),
      ),
    );
    _controller.forward().whenComplete(widget.onCompleted);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final rect = _rect.value ?? widget.begin;
        return Stack(
          children: [
            Positioned(
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: Opacity(
                opacity: _opacity.value,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: WiyaDesign.borderRadius,
                    color: colorScheme.surfaceContainerHigh.withValues(
                      alpha: 0.92,
                    ),
                    border: Border.all(
                      color: WiyaDesign.primaryBright.withValues(alpha: 0.28),
                    ),
                    boxShadow: WiyaDesign.softGlow(
                      color: colorScheme.primary,
                      blur: 18,
                      opacity: 0.22,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
