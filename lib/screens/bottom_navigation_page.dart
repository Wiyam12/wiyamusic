import 'dart:async';

import 'package:animated_icon/animated_icon.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:simple_clean_navbar/simple_clean_navbar.dart';
import 'package:wiyamusic/constants/app_constants.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/services/router_service.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/theme/design_tokens.dart';
import 'package:wiyamusic/utilities/flutter_bottom_sheet.dart'
    show closeCurrentBottomSheet;
import 'package:wiyamusic/utilities/flutter_toast.dart';
import 'package:wiyamusic/widgets/app_navigation_sidebar.dart';
import 'package:wiyamusic/widgets/mini_player.dart';
import 'package:wiyamusic/widgets/wiya_animated_icon.dart';

class BottomNavigationPage extends StatefulWidget {
  const BottomNavigationPage({required this.child, super.key});

  final StatefulNavigationShell child;

  @override
  State<BottomNavigationPage> createState() => _BottomNavigationPageState();
}

class _BottomNavigationPageState extends State<BottomNavigationPage> {
  late final _miniPlayerVisibilityStream = audioHandler.mediaItem
      .map((mediaItem) => mediaItem != null)
      .distinct();

  StreamSubscription<void>? _playbackFailureSubscription;

  bool? _previousOfflineMode;

  /// Track the previously selected tab index to detect double-taps on the same tab.
  int? _previousTabIndex;

  @override
  void initState() {
    super.initState();
    _playbackFailureSubscription = audioHandler.playbackFailureStream.listen((
      _,
    ) {
      if (!mounted) return;
      showToast(
        context,
        context.l10n?.playbackRequestFailed ??
            'Something went wrong. Please check your internet connection and try again.',
        icon: FluentIcons.error_circle_24_regular,
      );
    });
  }

  @override
  void dispose() {
    _playbackFailureSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.child.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;

        final currentIndex = widget.child.currentIndex;
        if (currentIndex != 0) {
          widget.child.goBranch(0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: ValueListenableBuilder<bool>(
        valueListenable: offlineMode,
        builder: (context, isOfflineMode, _) {
          if (_previousOfflineMode != null &&
              _previousOfflineMode != isOfflineMode) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              _handleOfflineModeChange(isOfflineMode);
            });
          }
          _previousOfflineMode = isOfflineMode;

          return LayoutBuilder(
            builder: (context, constraints) {
              final isTabletLayout =
                  MediaQuery.sizeOf(context).width >=
                  tabletNavigationBreakpoint;
              final colorScheme = Theme.of(context).colorScheme;
              final items = _getNavigationItems(isOfflineMode);
              final selectedIndex = _getCurrentIndex(items, isOfflineMode);

              return Scaffold(
                // Keep the floating nav / mini player pinned to the screen
                // bottom when the keyboard opens (instead of lifting with it).
                resizeToAvoidBottomInset: false,
                body: SafeArea(
                  bottom: false,
                  left: !isTabletLayout,
                  child: Row(
                    children: [
                      if (isTabletLayout)
                        AppNavigationSidebar(
                          isOfflineMode: isOfflineMode,
                          primarySelectedShellIndex: widget.child.currentIndex,
                          onPrimaryTabSelected: (shellIndex) {
                            final items = _getNavigationItems(isOfflineMode);
                            final uiIndex = items.indexWhere(
                              (item) => item.shellIndex == shellIndex,
                            );
                            if (uiIndex != -1) {
                              _onTabTapped(uiIndex, items);
                            } else {
                              closeCurrentBottomSheet();
                              widget.child.goBranch(shellIndex);
                            }
                          },
                          onNavigate: (route, {extra, shellIndex = 2}) {
                            closeCurrentBottomSheet();
                            if (widget.child.currentIndex != shellIndex) {
                              widget.child.goBranch(shellIndex);
                            }
                            if (extra != null) {
                              NavigationManager.router.go(route, extra: extra);
                            } else {
                              NavigationManager.router.go(route);
                            }
                          },
                        ),
                      Expanded(
                        child: StreamBuilder<bool>(
                          initialData: audioHandler.mediaItem.value != null,
                          stream: _miniPlayerVisibilityStream,
                          builder: (context, snapshot) {
                            final mediaQuery = MediaQuery.of(context);
                            final isMiniPlayerVisible = snapshot.data ?? false;
                            final safeBottom = mediaQuery.padding.bottom;
                            final bottomPadding = _contentBottomPadding(
                              safeBottom: safeBottom,
                              isTabletLayout: isTabletLayout,
                              isMiniPlayerVisible: isMiniPlayerVisible,
                            );

                            // Nav chrome ignores keyboard insets so it stays
                            // floating at the physical bottom of the screen.
                            final chromeMediaQuery = mediaQuery.copyWith(
                              viewInsets: EdgeInsets.zero,
                            );

                            return Stack(
                              children: [
                                MediaQuery(
                                  data: mediaQuery.copyWith(
                                    padding: mediaQuery.padding.copyWith(
                                      bottom: bottomPadding,
                                    ),
                                  ),
                                  child: widget.child,
                                ),
                                if (isMiniPlayerVisible)
                                  Positioned(
                                    left: isTabletLayout
                                        ? miniPlayerTabletHorizontalMargin
                                        : 8,
                                    right: isTabletLayout
                                        ? miniPlayerTabletHorizontalMargin
                                        : 8,
                                    bottom: isTabletLayout
                                        ? safeBottom +
                                              miniPlayerTabletBottomMargin
                                        : _floatingNavOccupiedHeight(8) +
                                              floatingNavMiniPlayerGap,
                                    child: MediaQuery(
                                      data: chromeMediaQuery,
                                      child: const MiniPlayer(),
                                    ),
                                  ),
                                if (!isTabletLayout)
                                  MediaQuery(
                                    data: chromeMediaQuery,
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: _buildFloatingNavBar(
                                        items: items,
                                        selectedIndex: selectedIndex,
                                        colorScheme: colorScheme,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Matches simple_clean_navbar floating layout: height 70 + margin 20.
  double _floatingNavOccupiedHeight(double safeBottom) {
    return floatingNavBarHeight + floatingNavBarMargin + safeBottom;
  }

  double _contentBottomPadding({
    required double safeBottom,
    required bool isTabletLayout,
    required bool isMiniPlayerVisible,
  }) {
    if (isTabletLayout) {
      return isMiniPlayerVisible
          ? safeBottom + miniPlayerTabletTotalHeight
          : safeBottom;
    }

    final navSpace = _floatingNavOccupiedHeight(safeBottom);
    final miniSpace = isMiniPlayerVisible
        ? MiniPlayer.playerHeight + floatingNavMiniPlayerGap
        : 0.0;

    return navSpace + miniSpace;
  }

  Widget _buildFloatingNavBar({
    required List<_NavigationItem> items,
    required int selectedIndex,
    required ColorScheme colorScheme,
  }) {
    final onlyShowSelectedLabels = languageSetting == const Locale('en', '');

    return SimpleCleanNavBar.advanced(
      currentIndex: selectedIndex,
      onTap: (index) => _onTabTapped(index, items),
      items: items
          .map(
            (item) => SimpleNavBarItem(
              label: item.label,
              customWidget: WiyaAnimatedIcon(
                icon: item.animatedIcon,
                size: 24,
                color: colorScheme.onSurfaceVariant,
                iconType: IconType.onlyIcon,
              ),
              activeCustomWidget: WiyaAnimatedIcon(
                icon: item.animatedIcon,
                size: 26,
                color: colorScheme.primary,
              ),
            ),
          )
          .toList(),
      backgroundColor: colorScheme.surfaceContainerHigh.withValues(alpha: 0.82),
      selectedColor: colorScheme.primary,
      unselectedColor: colorScheme.onSurfaceVariant,
      discColor:
          Color.lerp(colorScheme.primary, WiyaDesign.primaryDeep, 0.35) ??
          colorScheme.primary,
      isFloating: true,
      animationType: SimpleNavAnimType.float,
      textMode: onlyShowSelectedLabels
          ? SimpleNavTextMode.onSelect
          : SimpleNavTextMode.neverShow,
      // System UI is already handled in main.dart.
      updateSystemNavBar: false,
    );
  }

  List<_NavigationItem> _getNavigationItems(bool isOfflineMode) {
    final items = <_NavigationItem>[
      _NavigationItem(
        animatedIcon: AnimateIcons.home,
        label: context.l10n?.home ?? 'Home',
        route: '/home',
        shellIndex: 0,
      ),
    ];

    // Only add search tab in online mode
    if (!isOfflineMode) {
      items.add(
        _NavigationItem(
          animatedIcon: AnimateIcons.zoom,
          label: context.l10n?.search ?? 'Search',
          route: '/search',
          shellIndex: 1,
        ),
      );
    }

    items.addAll([
      _NavigationItem(
        animatedIcon: AnimateIcons.list,
        label: context.l10n?.library ?? 'Library',
        route: '/library',
        shellIndex: 2,
      ),
      _NavigationItem(
        animatedIcon: AnimateIcons.settings,
        label: context.l10n?.settings ?? 'Settings',
        route: '/settings',
        shellIndex: 3,
      ),
    ]);

    return items;
  }

  void _handleOfflineModeChange(bool isOfflineMode) {
    if (!mounted) return;

    final currentRoute = GoRouterState.of(context).matchedLocation;

    // If we're switching to offline mode and currently on search tab
    if (isOfflineMode && currentRoute.startsWith('/search')) {
      // Navigate to home
      widget.child.goBranch(0);
    }
  }

  void _onTabTapped(int index, List<_NavigationItem> items) {
    if (index < items.length) {
      final item = items[index];
      final isReselect = _previousTabIndex == index;

      // Close any open bottom sheet before switching tabs
      closeCurrentBottomSheet();

      // If user taps the same tab again, reset it to initial state.
      // Otherwise, preserve the branch state.
      if (isReselect) {
        widget.child.goBranch(item.shellIndex, initialLocation: true);
      } else {
        widget.child.goBranch(item.shellIndex);
      }

      _previousTabIndex = index;
    }
  }

  int _getCurrentIndex(List<_NavigationItem> items, bool isOfflineMode) {
    final currentShellIndex = widget.child.currentIndex;

    if (items.isEmpty) return 0;

    // Try to find the current shell index in the available items
    final matchedIndex = items.indexWhere(
      (item) => item.shellIndex == currentShellIndex,
    );
    if (matchedIndex != -1) return matchedIndex;

    // If the Search branch (1) is active but Search is hidden in offline mode,
    // fall back to the Home tab.
    if (isOfflineMode && currentShellIndex == 1) return 0;

    // Final fallback: return the first tab to keep UI in a valid state.
    return 0;
  }
}

class _NavigationItem {
  const _NavigationItem({
    required this.animatedIcon,
    required this.label,
    required this.route,
    required this.shellIndex,
  });

  final AnimateIcons animatedIcon;
  final String label;
  final String route;
  final int shellIndex;
}
