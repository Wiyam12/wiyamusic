import 'dart:async';

import 'package:animated_icon/animated_icon.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/services/data_manager.dart';
import 'package:wiyamusic/services/playlists_manager.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/theme/design_tokens.dart';
import 'package:wiyamusic/utilities/artwork_provider.dart';
import 'package:wiyamusic/utilities/playlist_utils.dart';
import 'package:wiyamusic/widgets/wiya_animated_icon.dart';

/// Expanded width of the tablet/iPad navigation sidebar.
const double appNavigationSidebarExpandedWidth = 248;

/// Collapsed (icon-only) width of the tablet/iPad navigation sidebar.
const double appNavigationSidebarCollapsedWidth = 76;

/// Legacy alias for the expanded width.
const double appNavigationSidebarWidth = appNavigationSidebarExpandedWidth;

const Duration _sidebarAnimDuration = Duration(milliseconds: 240);
const Curve _sidebarAnimCurve = Curves.easeOutCubic;

/// A single flat destination (used by legacy callers / tests).
class AppNavigationDestination {
  const AppNavigationDestination({
    required this.animatedIcon,
    required this.label,
  });

  final AnimateIcons animatedIcon;
  final String label;
}

/// Callback used when a tablet sidebar leaf route should open.
typedef TabletSidebarNavigate =
    void Function(String route, {Object? extra, int shellIndex});

/// Permanent left navigation used on tablets / large screens.
///
/// Supports width collapse and hierarchical Library / Playlists groups.
class AppNavigationSidebar extends StatefulWidget {
  const AppNavigationSidebar({
    required this.onNavigate,
    required this.onPrimaryTabSelected,
    required this.primarySelectedShellIndex,
    required this.isOfflineMode,
    this.destinations = const [],
    this.selectedIndex = 0,
    this.onDestinationSelected,
    super.key,
  });

  /// Hierarchical tablet navigation (preferred).
  final TabletSidebarNavigate onNavigate;
  final ValueChanged<int> onPrimaryTabSelected;
  final int primarySelectedShellIndex;
  final bool isOfflineMode;

  /// Legacy flat API kept for compatibility; ignored when [onNavigate] is used.
  final List<AppNavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;

  @override
  State<AppNavigationSidebar> createState() => _AppNavigationSidebarState();
}

class _AppNavigationSidebarState extends State<AppNavigationSidebar> {
  String? _lastAutoExpandRoute;

  void _toggleSidebarWidth() {
    final next = !tabletSidebarExpanded.value;
    tabletSidebarExpanded.value = next;
    unawaited(
      addOrUpdateData<bool>('settings', 'tabletSidebarExpanded', next),
    );
  }

  void _toggleLibraryGroup() {
    final next = !tabletLibraryNavExpanded.value;
    tabletLibraryNavExpanded.value = next;
    unawaited(
      addOrUpdateData<bool>('settings', 'tabletLibraryNavExpanded', next),
    );
  }

  void _togglePlaylistsGroup() {
    final next = !tabletPlaylistsNavExpanded.value;
    tabletPlaylistsNavExpanded.value = next;
    unawaited(
      addOrUpdateData<bool>('settings', 'tabletPlaylistsNavExpanded', next),
    );
  }

  void _ensureSidebarWidthExpanded() {
    if (tabletSidebarExpanded.value) return;
    tabletSidebarExpanded.value = true;
    unawaited(
      addOrUpdateData<bool>('settings', 'tabletSidebarExpanded', true),
    );
  }

  /// Expand parent groups only when the route *changes* to a nested leaf —
  /// never re-force expand after the user intentionally collapses a group.
  void _maybeAutoExpandForRoute(String matched) {
    if (_lastAutoExpandRoute == matched) return;
    _lastAutoExpandRoute = matched;

    final isNestedLibrary =
        matched.startsWith('/library/') &&
        matched != '/library' &&
        !matched.startsWith('/library/radioStations');
    if (!isNestedLibrary) return;

    if (!tabletLibraryNavExpanded.value) {
      tabletLibraryNavExpanded.value = true;
      unawaited(
        addOrUpdateData<bool>('settings', 'tabletLibraryNavExpanded', true),
      );
    }

    final isPlaylistLeaf =
        matched.contains('/library/playlist/') ||
        matched == '/library/userSongs/liked';
    if (isPlaylistLeaf && !tabletPlaylistsNavExpanded.value) {
      tabletPlaylistsNavExpanded.value = true;
      unawaited(
        addOrUpdateData<bool>('settings', 'tabletPlaylistsNavExpanded', true),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final goState = GoRouterState.of(context);
    final routeLocation = goState.uri.toString();
    final matched = goState.matchedLocation;
    final activePlaylistId =
        _decodePathParam(goState.pathParameters['playlistId']) ??
        _playlistIdFromPath(matched) ??
        _playlistIdFromPath(goState.uri.path);
    _maybeAutoExpandForRoute(matched);

    return ValueListenableBuilder<bool>(
      valueListenable: tabletSidebarExpanded,
      builder: (context, sidebarExpanded, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: tabletLibraryNavExpanded,
          builder: (context, libraryExpanded, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: tabletPlaylistsNavExpanded,
              builder: (context, playlistsExpanded, _) {
                final colorScheme = Theme.of(context).colorScheme;
                final isDark =
                    Theme.of(context).brightness == Brightness.dark;

                return AnimatedContainer(
                  duration: _sidebarAnimDuration,
                  curve: _sidebarAnimCurve,
                  width: sidebarExpanded
                      ? appNavigationSidebarExpandedWidth
                      : appNavigationSidebarCollapsedWidth,
                  decoration: BoxDecoration(
                    color: isDark
                        ? colorScheme.surfaceContainerHigh.withValues(
                            alpha: 0.92,
                          )
                        : colorScheme.surfaceContainerLow,
                    border: Border(
                      right: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
                  ),
                  child: SafeArea(
                    right: false,
                    child: ClipRect(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SidebarHeader(
                            expanded: sidebarExpanded,
                            onToggle: _toggleSidebarWidth,
                          ),
                          Expanded(
                            child: AnimatedBuilder(
                              animation: Listenable.merge([
                                userCustomPlaylists,
                                userLikedPlaylists,
                                userPlaylistFolders,
                              ]),
                              builder: (context, _) {
                                return ListView(
                                  padding: EdgeInsets.fromLTRB(
                                    sidebarExpanded ? 12 : 10,
                                    4,
                                    sidebarExpanded ? 12 : 10,
                                    16,
                                  ),
                                  children: _buildItems(
                                    context,
                                    sidebarExpanded: sidebarExpanded,
                                    libraryExpanded: libraryExpanded,
                                    playlistsExpanded: playlistsExpanded,
                                    matched: matched,
                                    routeLocation: routeLocation,
                                    activePlaylistId: activePlaylistId,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  List<Widget> _buildItems(
    BuildContext context, {
    required bool sidebarExpanded,
    required bool libraryExpanded,
    required bool playlistsExpanded,
    required String matched,
    required String routeLocation,
    required String? activePlaylistId,
  }) {
    final l10n = context.l10n;
    final items = <Widget>[];

    void addPrimary({
      required AnimateIcons icon,
      required String label,
      required int shellIndex,
      required bool selected,
      VoidCallback? onTap,
      IconData? fluentIcon,
    }) {
      items.add(
        _SidebarNavTile(
          label: label,
          selected: selected,
          expanded: sidebarExpanded,
          indent: 0,
          animatedIcon: icon,
          fluentIcon: fluentIcon,
          onTap: onTap ?? () => widget.onPrimaryTabSelected(shellIndex),
        ),
      );
      items.add(const SizedBox(height: 4));
    }

    addPrimary(
      icon: AnimateIcons.home,
      label: l10n?.home ?? 'Home',
      shellIndex: 0,
      selected: widget.primarySelectedShellIndex == 0,
    );

    if (!widget.isOfflineMode) {
      addPrimary(
        icon: AnimateIcons.zoom,
        label: l10n?.search ?? 'Search',
        shellIndex: 1,
        selected: widget.primarySelectedShellIndex == 1,
      );
    }

    // Library group — header only expands/collapses; Overview opens /library.
    items.add(
      _SidebarGroupHeader(
        label: l10n?.library ?? 'Library',
        selected: false,
        expanded: sidebarExpanded,
        groupExpanded: libraryExpanded,
        animatedIcon: AnimateIcons.list,
        onHeaderTap: () {
          if (!sidebarExpanded) {
            _ensureSidebarWidthExpanded();
            return;
          }
          _toggleLibraryGroup();
        },
        onChevronTap: () {
          if (!sidebarExpanded) {
            _ensureSidebarWidthExpanded();
            return;
          }
          _toggleLibraryGroup();
        },
      ),
    );
    items.add(const SizedBox(height: 4));

    if (sidebarExpanded && libraryExpanded) {
      items.add(
        _SidebarNavTile(
          label: 'Overview',
          selected: matched == '/library' &&
              !routeLocation.contains('section='),
          expanded: true,
          indent: 1,
          fluentIcon: FluentIcons.grid_24_regular,
          onTap: () => widget.onNavigate('/library', shellIndex: 2),
        ),
      );
      items.add(const SizedBox(height: 4));

      // Playlists subgroup — header navigates; chevron only toggles.
      items.add(
        _SidebarGroupHeader(
          label: l10n?.playlists ?? 'Playlists',
          selected: matched == '/library' &&
              routeLocation.contains('section=playlists'),
          expanded: true,
          groupExpanded: playlistsExpanded,
          fluentIcon: FluentIcons.list_24_regular,
          indent: 1,
          onHeaderTap: () {
            widget.onNavigate('/library?section=playlists', shellIndex: 2);
          },
          onChevronTap: _togglePlaylistsGroup,
        ),
      );
      items.add(const SizedBox(height: 4));

      if (playlistsExpanded) {
        items.add(
          _SidebarNavTile(
            label: l10n?.likedSongs ?? 'Liked Songs',
            selected: matched == '/library/userSongs/liked',
            expanded: true,
            indent: 2,
            fluentIcon: FluentIcons.heart_24_regular,
            onTap: () => widget.onNavigate(
              '/library/userSongs/liked',
              shellIndex: 2,
            ),
          ),
        );
        items.add(const SizedBox(height: 4));

        for (final playlist in _collectSidebarPlaylists()) {
          final id = playlist['ytid']?.toString() ?? '';
          final title = playlist['title']?.toString().trim().isNotEmpty == true
              ? playlist['title'].toString().trim()
              : (l10n?.playlist ?? 'Playlist');
          final selected =
              activePlaylistId != null && activePlaylistId == id;
          items.add(
            _SidebarNavTile(
              label: title,
              selected: selected,
              expanded: true,
              indent: 2,
              fluentIcon: FluentIcons.music_note_2_24_regular,
              imageUrl: _playlistArtworkUrl(playlist),
              onTap: () => widget.onNavigate(
                '/library/playlist/${Uri.encodeComponent(id)}',
                extra: playlist,
                shellIndex: 2,
              ),
            ),
          );
          items.add(const SizedBox(height: 4));
        }
      }

      items.add(
        _SidebarNavTile(
          label: l10n?.recentlyPlayed ?? 'Recently Played',
          selected: matched == '/library/userSongs/recents',
          expanded: true,
          indent: 1,
          fluentIcon: FluentIcons.history_24_regular,
          onTap: () => widget.onNavigate(
            '/library/userSongs/recents',
            shellIndex: 2,
          ),
        ),
      );
      items.add(const SizedBox(height: 4));

      items.add(
        _SidebarNavTile(
          label: l10n?.artists ?? 'Artists',
          selected: routeLocation.contains('section=artists'),
          expanded: true,
          indent: 1,
          fluentIcon: FluentIcons.person_24_regular,
          onTap: () => widget.onNavigate(
            '/library?section=artists',
            shellIndex: 2,
          ),
        ),
      );
      items.add(const SizedBox(height: 4));

      items.add(
        _SidebarNavTile(
          label: l10n?.albums ?? 'Albums',
          selected: routeLocation.contains('section=albums'),
          expanded: true,
          indent: 1,
          fluentIcon: FluentIcons.album_24_regular,
          onTap: () =>
              widget.onNavigate('/library?section=albums', shellIndex: 2),
        ),
      );
      items.add(const SizedBox(height: 4));

      items.add(
        _SidebarNavTile(
          label: l10n?.songs ?? 'Songs',
          selected: routeLocation.contains('section=songs'),
          expanded: true,
          indent: 1,
          fluentIcon: FluentIcons.music_note_1_24_regular,
          onTap: () =>
              widget.onNavigate('/library?section=songs', shellIndex: 2),
        ),
      );
      items.add(const SizedBox(height: 4));

      items.add(
        _SidebarNavTile(
          label: l10n?.offlineSongs ?? 'Offline Songs',
          selected: matched == '/library/userSongs/offline',
          expanded: true,
          indent: 1,
          fluentIcon: FluentIcons.cloud_off_24_regular,
          onTap: () => widget.onNavigate(
            '/library/userSongs/offline',
            shellIndex: 2,
          ),
        ),
      );
      items.add(const SizedBox(height: 4));
    }

    // Radio Stations — top-level
    if (!widget.isOfflineMode) {
      addPrimary(
        icon: AnimateIcons.activity,
        label: l10n?.radioStations ?? 'Radio Stations',
        shellIndex: 2,
        selected: matched == '/library/radioStations',
        fluentIcon: FluentIcons.live_24_regular,
        onTap: () =>
            widget.onNavigate('/library/radioStations', shellIndex: 2),
      );
    }

    addPrimary(
      icon: AnimateIcons.settings,
      label: l10n?.settings ?? 'Settings',
      shellIndex: 3,
      selected: widget.primarySelectedShellIndex == 3,
    );

    if (items.isNotEmpty && items.last is SizedBox) {
      items.removeLast();
    }
    return items;
  }

  List<Map> _collectSidebarPlaylists() {
    final seen = <String>{};
    final result = <Map>[];

    void consider(dynamic raw) {
      if (raw is! Map) return;
      if (raw['isAlbum'] == true) return;
      if (PlaylistUtils.isArtistPlaylist(raw)) return;
      final id = raw['ytid']?.toString();
      if (id == null || id.isEmpty || !seen.add(id)) return;
      result.add(Map<String, dynamic>.from(raw));
    }

    for (final p in userCustomPlaylists.value) {
      consider(p);
    }
    for (final folder in userPlaylistFolders.value) {
      final folderPlaylists = folder['playlists'] as List? ?? const [];
      for (final p in folderPlaylists) {
        consider(p);
      }
    }
    for (final p in userLikedPlaylists.value) {
      consider(p);
    }

    result.sort((a, b) {
      final at = a['title']?.toString().toLowerCase() ?? '';
      final bt = b['title']?.toString().toLowerCase() ?? '';
      return at.compareTo(bt);
    });
    return result;
  }

  /// Playlist cover, or the first song artwork when the playlist has no image.
  String? _playlistArtworkUrl(Map playlist) {
    final direct = playlist['image']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;

    final list = playlist['list'];
    if (list is! List || list.isEmpty) return null;
    final first = list.first;
    if (first is! Map) return null;

    for (final key in ['image', 'highResImage', 'lowResImage']) {
      final value = first[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String? _decodePathParam(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  String? _playlistIdFromPath(String path) {
    const marker = '/playlist/';
    final index = path.indexOf(marker);
    if (index < 0) return null;
    final idPart = path.substring(index + marker.length);
    if (idPart.isEmpty) return null;
    final end = idPart.indexOf(RegExp('[/?#]'));
    final raw = end < 0 ? idPart : idPart.substring(0, end);
    return _decodePathParam(raw);
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.expanded,
    required this.onToggle,
  });

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final toggleLabel = expanded ? 'Collapse sidebar' : 'Expand sidebar';

    Widget logo() {
      return ClipRRect(
        borderRadius: BorderRadius.circular(WiyaDesign.cornerRadiusSmall),
        child: Image.asset(
          'assets/icons/wiyamusic_icon.png',
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            Icons.music_note_rounded,
            color: colorScheme.primary,
            size: 26,
          ),
        ),
      );
    }

    Widget toggleButton() {
      return Tooltip(
        message: toggleLabel,
        waitDuration: const Duration(milliseconds: 400),
        child: IconButton(
          onPressed: onToggle,
          tooltip: toggleLabel,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            foregroundColor: colorScheme.onSurfaceVariant,
            backgroundColor: colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.45,
            ),
            minimumSize: const Size(36, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
          ),
          icon: AnimatedRotation(
            duration: _sidebarAnimDuration,
            curve: _sidebarAnimCurve,
            turns: expanded ? 0 : 0.5,
            child: Icon(
              expanded
                  ? FluentIcons.panel_left_contract_24_regular
                  : FluentIcons.panel_left_expand_24_regular,
              size: 18,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(expanded ? 12 : 8, 16, 8, 8),
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showLabels = expanded && constraints.maxWidth >= 160;

            if (!showLabels) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  logo(),
                  const SizedBox(height: 10),
                  toggleButton(),
                ],
              );
            }

            return Row(
              children: [
                logo(),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'WiyaMusic',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                toggleButton(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SidebarGroupHeader extends StatelessWidget {
  const _SidebarGroupHeader({
    required this.label,
    required this.selected,
    required this.expanded,
    required this.groupExpanded,
    required this.onHeaderTap,
    required this.onChevronTap,
    this.animatedIcon,
    this.fluentIcon,
    this.indent = 0,
  });

  final String label;
  final bool selected;
  final bool expanded;
  final bool groupExpanded;
  final VoidCallback onHeaderTap;
  final VoidCallback onChevronTap;
  final AnimateIcons? animatedIcon;
  final IconData? fluentIcon;
  final int indent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    final background = selected
        ? colorScheme.primary.withValues(alpha: 0.14)
        : Colors.transparent;
    final leftPad = expanded ? 8.0 + indent * 12.0 : 6.0;

    Widget leadingIcon() {
      if (fluentIcon != null) {
        return Icon(fluentIcon, size: 22, color: foreground);
      }
      return WiyaAnimatedIcon(
        icon: animatedIcon ?? AnimateIcons.list,
        size: 22,
        color: foreground,
        iconType: selected
            ? IconType.continueAnimation
            : IconType.onlyIcon,
      );
    }

    Widget chevron() {
      return IconButton(
        onPressed: onChevronTap,
        tooltip: groupExpanded ? 'Collapse' : 'Expand',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        icon: AnimatedRotation(
          turns: groupExpanded ? 0.25 : 0,
          duration: _sidebarAnimDuration,
          curve: _sidebarAnimCurve,
          child: Icon(
            FluentIcons.chevron_right_24_regular,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final row = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onHeaderTap,
        borderRadius: BorderRadius.circular(WiyaDesign.cornerRadiusSmall),
        child: AnimatedContainer(
          duration: _sidebarAnimDuration,
          curve: _sidebarAnimCurve,
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(leftPad, 10, expanded ? 4 : 6, 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(WiyaDesign.cornerRadiusSmall),
          ),
          child: ClipRect(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showLabel = expanded && constraints.maxWidth >= 96;

                if (!showLabel) {
                  return Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: FittedBox(child: leadingIcon()),
                    ),
                  );
                }

                return Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: leadingIcon(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: indent > 0 ? 14 : 15,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                          color: foreground,
                        ),
                      ),
                    ),
                    chevron(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    if (expanded) return row;
    return Tooltip(message: label, child: row);
  }
}

class _SidebarNavTile extends StatelessWidget {
  const _SidebarNavTile({
    required this.label,
    required this.selected,
    required this.expanded,
    required this.onTap,
    this.animatedIcon,
    this.fluentIcon,
    this.imageUrl,
    this.indent = 0,
  });

  final String label;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;
  final AnimateIcons? animatedIcon;
  final IconData? fluentIcon;
  final String? imageUrl;
  final int indent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    final background = selected
        ? colorScheme.primary.withValues(alpha: 0.14)
        : Colors.transparent;
    final leftPad = expanded ? 8.0 + indent * 12.0 : 6.0;
    final iconSize = selected && indent == 0 ? 26.0 : 22.0;
    final artworkSize = imageUrl != null && imageUrl!.isNotEmpty
        ? (expanded ? 28.0 : 26.0)
        : iconSize;

    final tile = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(WiyaDesign.cornerRadiusSmall),
        child: AnimatedContainer(
          duration: _sidebarAnimDuration,
          curve: _sidebarAnimCurve,
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(leftPad, 10, expanded ? 10 : 6, 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(WiyaDesign.cornerRadiusSmall),
            border: selected
                ? Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.28),
                  )
                : null,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showLabel = expanded && constraints.maxWidth >= 72;

              Widget leadingIcon() {
                final url = imageUrl?.trim();
                if (url != null && url.isNotEmpty) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image(
                      image: ArtworkProvider.get(url),
                      width: artworkSize,
                      height: artworkSize,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        if (fluentIcon != null) {
                          return Icon(
                            fluentIcon,
                            size: iconSize,
                            color: foreground,
                          );
                        }
                        return Icon(
                          FluentIcons.music_note_2_24_regular,
                          size: iconSize,
                          color: foreground,
                        );
                      },
                    ),
                  );
                }
                if (fluentIcon != null) {
                  return Icon(fluentIcon, size: iconSize, color: foreground);
                }
                return WiyaAnimatedIcon(
                  icon: animatedIcon ?? AnimateIcons.list,
                  size: iconSize,
                  color: foreground,
                  iconType: selected
                      ? IconType.continueAnimation
                      : IconType.onlyIcon,
                );
              }

              if (!showLabel) {
                return Center(
                  child: SizedBox(
                    width: artworkSize,
                    height: artworkSize,
                    child: FittedBox(child: leadingIcon()),
                  ),
                );
              }

              return Row(
                children: [
                  SizedBox(
                    width: artworkSize,
                    height: artworkSize,
                    child: leadingIcon(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: indent >= 2 ? 13.5 : 14.5,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: foreground,
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );

    if (expanded) return tile;
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 350),
      child: tile,
    );
  }
}
