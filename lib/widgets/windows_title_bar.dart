import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wiyamusic/theme/design_tokens.dart';

/// Height of the custom Windows chrome (Spotify-like compact bar).
const double windowsTitleBarHeight = 36;

/// Whether the app should paint custom desktop window chrome.
bool get usesCustomWindowChrome => Platform.isWindows;

/// Wraps [child] with a Spotify-style custom title bar on Windows.
class WindowsDesktopShell extends StatelessWidget {
  const WindowsDesktopShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!usesCustomWindowChrome) return child;

    return DragToResizeArea(
      child: Column(
        children: [
          const WindowsTitleBar(),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Compact custom title bar: logo + drag region + window controls.
class WindowsTitleBar extends StatefulWidget {
  const WindowsTitleBar({super.key});

  @override
  State<WindowsTitleBar> createState() => _WindowsTitleBarState();
}

class _WindowsTitleBarState extends State<WindowsTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_syncMaximized());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted && maximized != _isMaximized) {
      setState(() => _isMaximized = maximized);
    }
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: WiyaDesign.surface.withValues(alpha: 0.97),
      child: SizedBox(
        height: windowsTitleBarHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: DragToMoveArea(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTap: _toggleMaximize,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Row(
                        children: [
                          Image.asset(
                            'assets/icons/wiyamusic_icon.png',
                            width: 18,
                            height: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'WiyaMusic',
                            style: TextStyle(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.92,
                              ),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _WindowButton(
                tooltip: 'Minimize',
                onPressed: windowManager.minimize,
                child: const Icon(Icons.remove, size: 16),
              ),
              _WindowButton(
                tooltip: _isMaximized ? 'Restore' : 'Maximize',
                onPressed: _toggleMaximize,
                child: Icon(
                  _isMaximized ? Icons.filter_none : Icons.crop_square_rounded,
                  size: _isMaximized ? 12 : 15,
                ),
              ),
              _WindowButton(
                tooltip: 'Close',
                isClose: true,
                onPressed: windowManager.close,
                child: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.isClose = false,
  });

  final String tooltip;
  final Future<void> Function() onPressed;
  final Widget child;
  final bool isClose;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color background;
    final Color foreground;

    if (widget.isClose && _hovered) {
      background = const Color(0xFFE81123);
      foreground = Colors.white;
    } else if (_pressed) {
      background = colorScheme.onSurface.withValues(alpha: 0.14);
      foreground = colorScheme.onSurface;
    } else if (_hovered) {
      background = colorScheme.onSurface.withValues(alpha: 0.08);
      foreground = colorScheme.onSurface;
    } else {
      background = Colors.transparent;
      foreground = colorScheme.onSurfaceVariant;
    }

    return Semantics(
      button: true,
      label: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () => unawaited(widget.onPressed()),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: 46,
            height: windowsTitleBarHeight,
            color: background,
            alignment: Alignment.center,
            child: IconTheme(
              data: IconThemeData(color: foreground, size: 16),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
