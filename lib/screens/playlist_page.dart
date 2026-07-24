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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/services/artist_service.dart';
import 'package:wiyamusic/services/common_services.dart';
import 'package:wiyamusic/services/data_manager.dart';
import 'package:wiyamusic/services/playlist_download_service.dart';
import 'package:wiyamusic/services/playlists_manager.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/theme/design_tokens.dart';
import 'package:wiyamusic/utilities/app_utils.dart';
import 'package:wiyamusic/utilities/artwork_provider.dart';
import 'package:wiyamusic/utilities/flutter_toast.dart';
import 'package:wiyamusic/utilities/offline_playlist_dialogs.dart';
import 'package:wiyamusic/utilities/playlist_utils.dart';
import 'package:wiyamusic/utilities/song_filtering.dart';
import 'package:wiyamusic/utilities/sort_utils.dart';
import 'package:wiyamusic/widgets/bottom_sheet_bar.dart';
import 'package:wiyamusic/widgets/confirmation_dialog.dart';
import 'package:wiyamusic/widgets/edit_playlist_dialog.dart';
import 'package:wiyamusic/widgets/mini_player_bottom_space.dart';
import 'package:wiyamusic/widgets/playlist_page/empty_playlist_state.dart';
import 'package:wiyamusic/widgets/playlist_page/search_bar_section.dart';
import 'package:wiyamusic/widgets/song_bar.dart';
import 'package:wiyamusic/widgets/sort_chips.dart';
import 'package:wiyamusic/widgets/spinner.dart';

enum PlaylistSortType { default_, title, artist, dateAdded }

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({
    super.key,
    this.playlistId,
    this.playlistData,
    this.cubeIcon = FluentIcons.text_bullet_list_24_filled,
    this.isArtist = false,
  });

  final String? playlistId;
  final dynamic playlistData;
  final IconData cubeIcon;
  final bool isArtist;

  @override
  _PlaylistPageState createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  dynamic _playlist;
  late List<dynamic> _originalPlaylistList; // Keep original order separately

  late final playlistLikeStatus = ValueNotifier<bool>(
    isPlaylistAlreadyLiked(_resolvedPlaylistId),
  );
  bool _isInitializingPlaylist = true;

  String? get _resolvedPlaylistId =>
      _playlist?['ytid']?.toString() ??
      widget.playlistData?['ytid']?.toString() ??
      widget.playlistId;

  // Sorting
  late PlaylistSortType _sortType = PlaylistSortType.values.firstWhere(
    (e) => e.name == playlistSortSetting,
    orElse: () => PlaylistSortType.default_,
  );

  // Search
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier('');
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  List<dynamic> _getSourceList(String searchQuery) {
    final list = _playlist?['list'] as List<dynamic>? ?? [];
    return filterSongsByQuery(list, searchQuery);
  }

  bool get _isArtistCatalogLoading =>
      widget.isArtist && _playlist?['catalogStatus'] == 'loading';

  bool get _isArtistCatalogFailed =>
      widget.isArtist && _playlist?['catalogStatus'] == 'failed';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    userLikedPlaylists.addListener(_syncPlaylistLikeStatus);
    _initializePlaylist();
  }

  @override
  void dispose() {
    userLikedPlaylists.removeListener(_syncPlaylistLikeStatus);
    playlistLikeStatus.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchQueryNotifier.dispose();
    super.dispose();
  }

  void _syncPlaylistLikeStatus() {
    final newStatus = isPlaylistAlreadyLiked(_resolvedPlaylistId);
    if (playlistLikeStatus.value != newStatus) {
      playlistLikeStatus.value = newStatus;
    }
  }

  Future<void> _initializePlaylist() async {
    try {
      final initialPlaylist = widget.playlistData;
      final resolvedId =
          initialPlaylist?['ytid']?.toString() ?? widget.playlistId;

      if (initialPlaylist != null) {
        _playlist = initialPlaylist;
        final playlistList = _playlist?['list'] as List?;
        final shouldFetchInitialPlaylist =
            playlistList == null || (!widget.isArtist && playlistList.isEmpty);
        if (shouldFetchInitialPlaylist && resolvedId != null) {
          _playlist =
              await getPlaylistInfoForWidget(
                resolvedId,
                isArtist: widget.isArtist,
                artistName: initialPlaylist?['title']?.toString(),
                artistImage: initialPlaylist?['image']?.toString(),
                sourceSongId: initialPlaylist?['sourceSongId']?.toString(),
                sourceVideoAuthor: initialPlaylist?['videoAuthor']?.toString(),
                preferredVerified: initialPlaylist?['isVerifiedArtist'] == true,
              ) ??
              initialPlaylist;
        }
      } else {
        _playlist = await getPlaylistInfoForWidget(
          resolvedId,
          isArtist: widget.isArtist,
          artistName: initialPlaylist?['title']?.toString(),
          artistImage: initialPlaylist?['image']?.toString(),
          sourceSongId: initialPlaylist?['sourceSongId']?.toString(),
          sourceVideoAuthor: initialPlaylist?['videoAuthor']?.toString(),
          preferredVerified: initialPlaylist?['isVerifiedArtist'] == true,
        );
      }

      if (_playlist != null && _playlist['list'] != null) {
        _originalPlaylistList = List<dynamic>.from(_playlist['list'] as List);
        _sortPlaylist(_sortType);
        _syncPlaylistLikeStatus();
      }
    } catch (e, stackTrace) {
      logger.log(
        'Error initializing playlist:',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        showToast(context, context.l10n!.error);
      }
    } finally {
      _isInitializingPlaylist = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isInitializingPlaylist) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: const Center(child: Spinner()),
      );
    }

    if (_playlist == null) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(FluentIcons.arrow_left_24_regular),
            onPressed: () => Navigator.pop(context),
            tooltip: context.l10n!.back,
          ),
        ),
        body: Center(
          child: Text(
            context.l10n!.error,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final expandedHeight = MediaQuery.sizeOf(context).height * 0.38;
    final playlistTitle = widget.isArtist
        ? normalizeArtistDisplayTitle(_playlist['title']?.toString() ?? '')
        : _playlist['title']?.toString() ?? '';
    final imageUrl = widget.isArtist
        ? normalizeArtistThumbnailUrl(_playlist['image']?.toString())
        : _playlist['image']?.toString();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: expandedHeight,
            pinned: true,
            stretch: true,
            backgroundColor: colorScheme.surface,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(FluentIcons.arrow_left_24_regular),
              onPressed: () =>
                  Navigator.pop(context, widget.playlistData == _playlist),
              tooltip: context.l10n!.back,
            ),
            actions: _buildAppBarActions(),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(48, 0, 48, 16),
              centerTitle: true,
              title: Text(
                playlistTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1.05,
                ),
              ),
              background: _PlaylistHeaderBackground(
                imageUrl: imageUrl,
                cubeIcon: widget.cubeIcon,
              ),
            ),
          ),
          SliverToBoxAdapter(child: _buildControlsSection()),
          if ((_playlist['list'] as List? ?? const []).isNotEmpty)
            ValueListenableBuilder<String>(
              valueListenable: _searchQueryNotifier,
              builder: (context, searchQuery, _) {
                final sourceList = _getSourceList(searchQuery);
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  sliver: SliverList.builder(
                    itemCount: sourceList.length,
                    itemBuilder: (context, index) {
                      final isRemovable = _playlist['source'] == 'user-created';
                      return _buildSongListItem(
                        sourceList[index],
                        index,
                        isRemovable,
                      );
                    },
                  ),
                );
              },
            )
          else if (_isArtistCatalogLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.3,
                  child: const Spinner(),
                ),
              ),
            )
          else if (_isArtistCatalogFailed)
            EmptyPlaylistState(message: context.l10n!.error)
          else
            EmptyPlaylistState(message: context.l10n!.noSongsInPlaylist),
          const SliverMiniPlayerBottomSpace(),
        ],
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    return [
      IconButton(
        icon: const Icon(FluentIcons.more_vertical_24_regular),
        onPressed: _showPlaylistOptionsSheet,
      ),
    ];
  }

  void _showPlaylistOptionsSheet() {
    final colorScheme = Theme.of(context).colorScheme;
    final isUserCreated = _playlist['source'] == 'user-created';
    final songs = _playlist['list'] as List? ?? [];
    final playlistId = _playlist?['ytid']?.toString() ?? widget.playlistId;
    final isOffline =
        playlistId != null &&
        playlistId.isNotEmpty &&
        isPlaylistFullyOffline(songs);

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
                  context.l10n!.editPlaylist,
                  () {
                    Navigator.pop(sheetContext);
                    if (!isUserCreated) {
                      showToast(context, context.l10n!.error);
                      return;
                    }
                    unawaited(_editPlaylist());
                  },
                  false,
                  icon: FluentIcons.edit_24_regular,
                ),
                BottomSheetBar(
                  context.l10n!.deletePlaylist,
                  () {
                    Navigator.pop(sheetContext);
                    _confirmDeletePlaylist();
                  },
                  false,
                  icon: FluentIcons.delete_24_regular,
                ),
                BottomSheetBar(
                  isOffline
                      ? context.l10n!.removeOffline
                      : context.l10n!.downloadPlaylist,
                  () {
                    Navigator.pop(sheetContext);
                    _handleDownloadAction();
                  },
                  false,
                  icon: isOffline
                      ? FluentIcons.arrow_download_off_24_regular
                      : FluentIcons.arrow_download_24_regular,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlsSection() {
    final songsLength = (_playlist['list'] as List? ?? const []).length;
    final colorScheme = Theme.of(context).colorScheme;
    final isAlbum = _playlist['isAlbum'] == true;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.isArtist)
                _MetaChip(
                  icon: FluentIcons.person_16_regular,
                  label: context.l10n!.artist,
                )
              else
                _MetaChip(
                  icon: isAlbum
                      ? FluentIcons.cd_16_regular
                      : FluentIcons.apps_list_24_regular,
                  label: isAlbum ? context.l10n!.album : context.l10n!.playlist,
                ),
              _MetaChip(
                icon: FluentIcons.text_bullet_list_24_filled,
                label: '$songsLength ${context.l10n!.songs}',
              ),
            ],
          ),
          if (songsLength > 0) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(FluentIcons.play_24_filled),
                    label: Text(context.l10n!.play),
                    onPressed: () => audioHandler.playPlaylistSong(
                      playlist: _playlist,
                      songIndex: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.secondaryContainer,
                      foregroundColor: colorScheme.onSecondaryContainer,
                    ),
                    icon: const Icon(FluentIcons.arrow_shuffle_24_filled),
                    label: Text(context.l10n!.shuffle),
                    onPressed: () async {
                      final songs = _playlist['list'] as List? ?? [];
                      if (songs.isEmpty) return;
                      final shuffled = List<Map>.from(songs.whereType<Map>())
                        ..shuffle();
                      await audioHandler.addPlaylistToQueue(
                        shuffled,
                        replace: true,
                        startIndex: 0,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
          if (songsLength > 1) ...[
            const SizedBox(height: 12),
            SortChips<PlaylistSortType>(
              currentSortType: _sortType,
              sortTypes: PlaylistSortType.values,
              sortTypeToString: _getSortTypeDisplayText,
              onSelected: (type) {
                setState(() {
                  _sortType = type;
                  addOrUpdateData<String>(
                    'settings',
                    'playlistSortType',
                    type.name,
                  );
                  playlistSortSetting = type.name;
                  _sortPlaylist(type);
                });
              },
            ),
          ],
          if (songsLength > 0) ...[
            const SizedBox(height: 12),
            SearchBarSection(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onSearchChanged: (value) => _searchQueryNotifier.value = value,
              labelText: context.l10n!.search,
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _editPlaylist() async {
    final result = await showDialog<Map?>(
      context: context,
      builder: (context) => EditPlaylistDialog(playlistData: _playlist),
    );

    if (result == null) return;

    final resolvedPlaylistYtid =
        _playlist['ytid']?.toString() ?? widget.playlistId;
    if (resolvedPlaylistYtid == null ||
        resolvedPlaylistYtid.isEmpty ||
        resolvedPlaylistYtid == 'null') {
      showToast(context, context.l10n!.error);
      return;
    }

    final updatedPlaylist = {
      ..._playlist,
      ...result,
      'ytid': resolvedPlaylistYtid,
      'source': _playlist['source'] ?? result['source'],
      'list': result['list'] ?? _playlist['list'],
    };

    final rootIndex = userCustomPlaylists.value.indexWhere(
      (p) => p['ytid'] == resolvedPlaylistYtid,
    );

    if (rootIndex != -1) {
      final updatedPlaylists = List<Map>.from(userCustomPlaylists.value);
      updatedPlaylists[rootIndex] = updatedPlaylist;
      userCustomPlaylists.value = updatedPlaylists;
      unawaited(
        addOrUpdateData<List>(
          'user',
          'customPlaylists',
          userCustomPlaylists.value,
        ),
      );
    } else {
      final updatedFolders = List<Map>.from(userPlaylistFolders.value);
      for (final folder in updatedFolders) {
        final folderPlaylists = List<Map>.from(
          folder['playlists'] as List? ?? [],
        );
        final fi = folderPlaylists.indexWhere(
          (p) => p['ytid'] == resolvedPlaylistYtid,
        );
        if (fi != -1) {
          folderPlaylists[fi] = updatedPlaylist;
          folder['playlists'] = folderPlaylists;
          break;
        }
      }
      userPlaylistFolders.value = updatedFolders;
      unawaited(
        addOrUpdateData<List>(
          'user',
          'playlistFolders',
          userPlaylistFolders.value,
        ),
      );
    }

    unawaited(syncOfflinePlaylistMetadata(updatedPlaylist));
    setState(() => _playlist = updatedPlaylist);
    showToast(context, context.l10n!.playlistUpdated);
  }

  void _confirmDeletePlaylist() {
    final isUserCreated = _playlist['source'] == 'user-created';
    final isUserYoutube = _playlist['source'] == 'user-youtube';

    if (!isUserCreated && !isUserYoutube) {
      showToast(context, context.l10n!.error);
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return ConfirmationDialog(
          confirmationMessage: context.l10n!.removePlaylistQuestion,
          submitMessage: context.l10n!.delete,
          onCancel: () => Navigator.of(dialogContext).pop(),
          onSubmit: () {
            Navigator.of(dialogContext).pop();
            final playlistId = _playlist['ytid']?.toString() ?? '';
            if (playlistId.isEmpty) {
              showToast(context, context.l10n!.error);
              return;
            }

            removeUserPlaylistEntry(
              Map<String, dynamic>.from(_playlist as Map),
            );
            if (offlinePlaylistService.isPlaylistDownloaded(playlistId)) {
              unawaited(
                offlinePlaylistService.removeOfflinePlaylist(playlistId),
              );
            }
            if (mounted) {
              Navigator.of(context).pop(true);
            }
          },
        );
      },
    );
  }

  void _handleDownloadAction() {
    final playlistId = _playlist?['ytid']?.toString() ?? widget.playlistId;
    if (playlistId == null || playlistId.isEmpty) {
      showToast(context, context.l10n!.error);
      return;
    }

    final songs = _playlist?['list'] as List? ?? [];
    if (songs.isEmpty) {
      showToast(context, context.l10n!.noSongsInPlaylist);
      return;
    }

    if (isPlaylistFullyOffline(songs)) {
      _showRemoveOfflineDialog(playlistId);
      return;
    }

    if (offlineMode.value) {
      showToast(context, context.l10n!.offlineMode);
      return;
    }

    if (offlinePlaylistService.isPlaylistDownloading(playlistId)) {
      offlinePlaylistService.cancelDownload(context, playlistId);
      return;
    }

    unawaited(offlinePlaylistService.downloadPlaylist(context, _playlist));
  }

  void _showRemoveOfflineDialog(String playlistId) =>
      showRemoveOfflinePlaylistDialog(context, playlistId);

  void _updateSongsListOnRemove(int indexOfRemovedSong, dynamic songToRemove) {
    _originalPlaylistList.removeWhere((s) => s['ytid'] == songToRemove['ytid']);
    final playlistId = _playlist['ytid'];
    if (mounted) {
      setState(() {});
      showToastWithButton(
        context,
        context.l10n!.songRemoved,
        context.l10n!.undo.toUpperCase(),
        () {
          addSongInCustomPlaylist(
            context,
            playlistId,
            songToRemove,
            indexToInsert: indexOfRemovedSong,
          );
          if (mounted) setState(() {});
        },
      );
    } else {
      logger.log(
        '(_updateSongsListOnRemove): Widget not mounted, cannot show undo toast.',
      );
    }
  }

  String _getSortTypeDisplayText(PlaylistSortType type) {
    switch (type) {
      case PlaylistSortType.default_:
        return context.l10n!.default_;
      case PlaylistSortType.title:
        return context.l10n!.name;
      case PlaylistSortType.artist:
        return context.l10n!.artist;
      case PlaylistSortType.dateAdded:
        return context.l10n!.dateAdded;
    }
  }

  void _sortPlaylist(PlaylistSortType type) {
    if (_playlist == null || _playlist['list'] == null) return;

    switch (type) {
      case PlaylistSortType.default_:
        // Restore original order from backup
        _playlist['list'] = List<dynamic>.from(_originalPlaylistList);
        break;
      case PlaylistSortType.title:
        final playlist = List<dynamic>.from(_playlist['list']);
        sortSongsByKey(playlist, 'title');
        _playlist['list'] = playlist;
        break;
      case PlaylistSortType.artist:
        final playlist = List<dynamic>.from(_playlist['list']);
        sortSongsByKey(playlist, 'artist');
        _playlist['list'] = playlist;
        break;
      case PlaylistSortType.dateAdded:
        _playlist['list'] = List<dynamic>.from(_originalPlaylistList.reversed);
        break;
    }
  }

  Widget _buildSongListItem(dynamic song, int index, bool isRemovable) {
    final sourceList = _getSourceList(_searchQueryNotifier.value);
    final totalItems = sourceList.length;
    final borderRadius = getItemBorderRadius(index, totalItems);
    final isUserCreatedPlaylist = _playlist?['source'] == 'user-created';
    final playlistId = isUserCreatedPlaylist ? _playlist!['ytid'] : null;
    final isSearching = _searchQueryNotifier.value.isNotEmpty;
    final fullIndex = isSearching
        ? PlaylistUtils.findSongIndexByYtid(_playlist, song['ytid'])
        : index;

    if (isSearching && fullIndex == -1) {
      logger.log('Warning: Song ${song['ytid']} not found in full playlist');
    }

    return SongBar(
      song,
      true,
      key: listItemKey('playlist_song', index, song),
      onRemove: (isRemovable && !isSearching)
          ? () {
              if (removeSongFromPlaylist(
                _playlist,
                song,
                removeOneAtIndex: index,
              )) {
                _updateSongsListOnRemove(index, song);
              }
            }
          : null,
      onPlay: () {
        audioHandler.playPlaylistSong(
          playlist: _playlist,
          songIndex: fullIndex != -1 ? fullIndex : index,
        );
      },
      borderRadius: borderRadius,
      playlistId: playlistId,
      onRenamed: () => setState(() {}),
    );
  }
}

class _PlaylistHeaderBackground extends StatelessWidget {
  const _PlaylistHeaderBackground({
    required this.imageUrl,
    required this.cubeIcon,
  });

  final String? imageUrl;
  final IconData cubeIcon;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasImage)
          Image(
            image: ArtworkProvider.get(imageUrl!),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _FallbackArtwork(icon: cubeIcon),
          )
        else
          _FallbackArtwork(icon: cubeIcon),
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

class _FallbackArtwork extends StatelessWidget {
  const _FallbackArtwork({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WiyaDesign.surfaceHigh,
      child: Center(
        child: Icon(
          icon,
          size: 56,
          color: WiyaDesign.primaryBright.withValues(alpha: 0.75),
        ),
      ),
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
