import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/screens/playlist_page.dart';
import 'package:wiyamusic/services/playlists_manager.dart';
import 'package:wiyamusic/services/router_service.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/theme/design_tokens.dart';
import 'package:wiyamusic/utilities/app_utils.dart';
import 'package:wiyamusic/utilities/artwork_contrast.dart';
import 'package:wiyamusic/utilities/flutter_toast.dart';
import 'package:wiyamusic/utilities/playlist_dialogs.dart';
import 'package:wiyamusic/utilities/playlist_utils.dart';
import 'package:wiyamusic/widgets/bottom_sheet_bar.dart';
import 'package:wiyamusic/widgets/confirmation_dialog.dart';
import 'package:wiyamusic/widgets/dialog_item.dart';
import 'package:wiyamusic/widgets/mini_player_bottom_space.dart';
import 'package:wiyamusic/widgets/playlist_bar.dart';
import 'package:wiyamusic/widgets/playlist_page/empty_playlist_state.dart';

/// Opens a manually created (user-owned) playlist song list.
///
/// Routed from the library stack so custom playlists don't use the remote
/// [PlaylistPage] home path. Lives beside [PlaylistFolderPage] as the
/// manual-library surface.
class UserCreatedPlaylistPage extends StatelessWidget {
  const UserCreatedPlaylistPage({
    super.key,
    this.playlistId,
    this.playlistData,
  });

  final String? playlistId;
  final dynamic playlistData;

  @override
  Widget build(BuildContext context) {
    final resolvedId =
        playlistId ??
        (playlistData is Map ? playlistData['ytid']?.toString() : null);

    // Always prefer the live stored playlist so song removals survive reopen.
    Map? stored;
    if (resolvedId != null && resolvedId.isNotEmpty) {
      for (final playlist in getUserCustomPlaylists()) {
        if (playlist['ytid']?.toString() == resolvedId) {
          stored = playlist;
          break;
        }
      }
    }

    return PlaylistPage(
      key: ValueKey('playlist-page-$resolvedId'),
      playlistId: resolvedId,
      playlistData: stored ?? playlistData,
    );
  }
}

class PlaylistFolderPage extends StatefulWidget {
  const PlaylistFolderPage({
    super.key,
    required this.folderId,
    required this.folderName,
  });

  final String folderId;
  final String folderName;

  @override
  State<PlaylistFolderPage> createState() => _PlaylistFolderPageState();
}

class _PlaylistFolderPageState extends State<PlaylistFolderPage> {
  late String _folderName;
  double _headerExpandProgress = 1;

  /// Tall enough for a 2-line FlexibleSpaceBar title when the app bar is pinned.
  static const double _collapsedToolbarHeight = 76;

  @override
  void initState() {
    super.initState();
    _folderName = widget.folderName;
  }

  bool _handleHeaderScroll(ScrollNotification notification) {
    final expandedHeight = MediaQuery.sizeOf(context).height * 0.38;
    final collapseRange = (expandedHeight - _collapsedToolbarHeight).clamp(
      1.0,
      double.infinity,
    );
    final progress = (1 - (notification.metrics.pixels / collapseRange)).clamp(
      0.0,
      1.0,
    );
    if ((progress - _headerExpandProgress).abs() > 0.02) {
      setState(() => _headerExpandProgress = progress);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final expandedHeight = MediaQuery.sizeOf(context).height * 0.38;
    // Folder headers use a dark fallback artwork, so expanded icons stay light
    // and lerp to onSurface as the app bar collapses.
    final headerForeground = playlistHeaderForegroundColor(
      isTopRegionLight: false,
      collapsedColor: colorScheme.onSurface,
      expandProgress: _headerExpandProgress,
    );

    return ValueListenableBuilder<List>(
      valueListenable: userPlaylistFolders,
      builder: (context, _, __) {
        final isOffline = offlineMode.value;
        final playlists = isOffline
            ? getPlaylistsInFolder(
                widget.folderId,
              ).where(PlaylistUtils.isPlaylistOffline).toList()
            : getPlaylistsInFolder(widget.folderId);

        return Scaffold(
          backgroundColor: colorScheme.surface,
          body: NotificationListener<ScrollNotification>(
            onNotification: _handleHeaderScroll,
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: expandedHeight,
                  pinned: true,
                  stretch: true,
                  toolbarHeight: _collapsedToolbarHeight,
                  collapsedHeight: _collapsedToolbarHeight,
                  backgroundColor: colorScheme.surface,
                  foregroundColor: headerForeground,
                  iconTheme: IconThemeData(color: headerForeground),
                  actionsIconTheme: IconThemeData(color: headerForeground),
                  leading: IconButton(
                    icon: Icon(
                      FluentIcons.arrow_left_24_regular,
                      color: headerForeground,
                    ),
                    onPressed: () => Navigator.pop(context),
                    tooltip: context.l10n!.back,
                  ),
                  actions: [
                    IconButton(
                      icon: Icon(
                        FluentIcons.more_vertical_24_regular,
                        color: headerForeground,
                      ),
                      onPressed: _showFolderOptionsSheet,
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    expandedTitleScale: 1.45,
                    titlePadding: const EdgeInsets.fromLTRB(52, 0, 52, 12),
                    centerTitle: true,
                    title: Text(
                      _folderName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        // Always white: the title sits on the dark header fade.
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        height: 1.15,
                      ),
                    ),
                    background: const _FolderHeaderBackground(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildControlsSection(playlists.length),
                ),
                if (playlists.isEmpty)
                  EmptyPlaylistState(
                    icon: FluentIcons.folder_24_regular,
                    message: context.l10n!.emptyFolderMsg,
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    sliver: SliverList.builder(
                      itemCount: playlists.length,
                      itemBuilder: (context, index) {
                        final playlist = playlists[index];
                        final borderRadius = getItemBorderRadius(
                          index,
                          playlists.length,
                        );
                        return PlaylistBar(
                          key: listItemKey('folder_playlist', index, playlist),
                          playlist['title'],
                          playlistId: playlist['ytid'],
                          playlistArtwork: playlist['image'],
                          playlistData: playlist,
                          onDelete: () => _showRemovePlaylistDialog(playlist),
                          borderRadius: borderRadius,
                        );
                      },
                    ),
                  ),
                const SliverMiniPlayerBottomSpace(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlsSection(int playlistCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              const _MetaChip(
                icon: FluentIcons.folder_16_regular,
                label: 'Folder',
              ),
              _MetaChip(
                icon: FluentIcons.text_bullet_list_24_filled,
                label: playlistCount == 1
                    ? '1 ${context.l10n!.playlist}'
                    : '$playlistCount ${context.l10n!.playlists}',
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showFolderOptionsSheet() {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final bottomSafe = MediaQuery.paddingOf(sheetContext).bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, bottomSafe + 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BottomSheetBar(
                  'Create playlist',
                  () {
                    Navigator.pop(sheetContext);
                    _showCreatePlaylistInFolder();
                  },
                  false,
                  icon: FluentIcons.add_24_regular,
                ),
                BottomSheetBar(
                  context.l10n!.addPlaylist,
                  () {
                    Navigator.pop(sheetContext);
                    _showAddPlaylistDialog();
                  },
                  false,
                  icon: FluentIcons.collections_add_24_regular,
                ),
                BottomSheetBar(
                  context.l10n!.editFolder,
                  () {
                    Navigator.pop(sheetContext);
                    _showRenameFolderDialog();
                  },
                  false,
                  icon: FluentIcons.edit_24_regular,
                ),
                BottomSheetBar(
                  context.l10n!.deleteFolder,
                  () {
                    Navigator.pop(sheetContext);
                    _showDeleteFolderDialog();
                  },
                  false,
                  icon: FluentIcons.delete_24_regular,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCreatePlaylistInFolder() async {
    final result = await showCreatePlaylistDialog(context);
    if (!mounted || result == null) return;

    if (result['type'] != 'custom') {
      // YouTube playlists stay as remote playlists; move into this folder if added.
      final youtubeId = result['id'];
      if (youtubeId == null || youtubeId.isEmpty) return;
      final playlists = await getUserPlaylistsNotInFolders();
      if (!mounted) return;
      Map? match;
      for (final entry in playlists) {
        if (entry is Map && entry['ytid']?.toString() == youtubeId) {
          match = entry;
          break;
        }
      }
      if (match != null) {
        movePlaylistToFolder(match, widget.folderId, context);
      }
      return;
    }

    final playlistId = result['id'];
    if (playlistId == null || playlistId.isEmpty) return;

    Map? playlist;
    for (final entry in userCustomPlaylists.value) {
      if (entry['ytid']?.toString() == playlistId) {
        playlist = entry;
        break;
      }
    }
    if (playlist == null) return;

    movePlaylistToFolder(playlist, widget.folderId, context);
  }

  Future<void> _showAddPlaylistDialog() async {
    final customCandidates = getPlaylistsNotInFolders();
    final youtubeCandidates = await getUserPlaylistsNotInFolders();
    final candidates = [...customCandidates, ...youtubeCandidates];

    if (!mounted) return;

    if (candidates.isEmpty) {
      showToast(context, context.l10n!.noPlaylistsAdded);
      return;
    }

    await showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          icon: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              FluentIcons.text_bullet_list_add_24_filled,
              color: colorScheme.secondary,
              size: 28,
            ),
          ),
          title: Text(
            context.l10n!.addPlaylist,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: candidates.length,
              itemBuilder: (context, index) {
                final playlist = candidates[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: DialogItem(
                    icon: FluentIcons.text_bullet_list_24_filled,
                    iconColor: colorScheme.tertiary,
                    iconBgColor: colorScheme.tertiaryContainer,
                    label: playlist['title'] ?? '',
                    onTap: () {
                      Navigator.pop(context);
                      movePlaylistToFolder(playlist, widget.folderId, context);
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n!.cancel),
            ),
          ],
        );
      },
    );
  }

  void _showRemovePlaylistDialog(Map playlist) {
    showDialog(
      context: context,
      builder: (context) => ConfirmationDialog(
        submitMessage: context.l10n!.remove,
        confirmationMessage: context.l10n!.removeFromFolder,
        onCancel: () => Navigator.of(context).pop(),
        onSubmit: () {
          Navigator.of(context).pop();
          movePlaylistToFolder(playlist, null, context);
        },
      ),
    );
  }

  void _showRenameFolderDialog() {
    var newName = _folderName;
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          FluentIcons.folder_24_regular,
          color: colorScheme.primary,
          size: 32,
        ),
        title: Text(
          context.l10n!.editFolder,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: TextFormField(
          decoration: InputDecoration(
            labelText: context.l10n!.folderName,
            prefixIcon: Icon(
              FluentIcons.text_field_20_regular,
              color: colorScheme.onSurfaceVariant,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
          ),
          initialValue: newName,
          autofocus: true,
          onChanged: (value) => newName = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              context.l10n!.cancel,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              final result = renamePlaylistFolder(
                widget.folderId,
                newName,
                context,
              );
              showToast(context, result);
              if (newName.trim().isNotEmpty) {
                setState(() => _folderName = newName.trim());
              }
            },
            icon: const Icon(FluentIcons.save_20_filled),
            label: Text(context.l10n!.update),
          ),
        ],
      ),
    );
  }

  void _showDeleteFolderDialog() {
    final pageContext = context;
    showDialog<void>(
      context: pageContext,
      builder: (dialogContext) => ConfirmationDialog(
        submitMessage: pageContext.l10n!.delete,
        confirmationMessage: pageContext.l10n!.deleteFolderQuestion,
        onCancel: () => Navigator.of(dialogContext).pop(),
        onSubmit: () {
          Navigator.of(dialogContext).pop();
          deletePlaylistFolder(widget.folderId, pageContext);
          if (!pageContext.mounted) return;

          // Prefer popping back to the previous library page; fall back to
          // replacing the stack so we never pop the last shell route.
          if (pageContext.canPop()) {
            pageContext.pop();
          } else {
            pageContext.go(NavigationManager.libraryPath);
          }
        },
      ),
    );
  }
}

class _FolderHeaderBackground extends StatelessWidget {
  const _FolderHeaderBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: WiyaDesign.surfaceHigh,
          child: Center(
            child: Icon(
              FluentIcons.folder_24_filled,
              size: 56,
              color: WiyaDesign.primaryBright.withValues(alpha: 0.75),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.15),
                WiyaDesign.primaryDeep.withValues(alpha: 0.45),
                WiyaDesign.background.withValues(alpha: 0.92),
                WiyaDesign.background,
              ],
              stops: const [0, 0.4, 0.78, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                WiyaDesign.primaryBright.withValues(alpha: 0.28),
                Colors.transparent,
                WiyaDesign.primary.withValues(alpha: 0.2),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
