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
import 'package:wiyamusic/main.dart' show logger, audioHandler;
import 'package:wiyamusic/models/playback_context.dart';
import 'package:wiyamusic/services/common_services.dart';
import 'package:wiyamusic/services/data_manager.dart';
import 'package:wiyamusic/services/playlist_download_service.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/theme/design_tokens.dart';
import 'package:wiyamusic/utilities/app_utils.dart';
import 'package:wiyamusic/utilities/flutter_toast.dart';
import 'package:wiyamusic/utilities/playlist_utils.dart';
import 'package:wiyamusic/utilities/song_filtering.dart';
import 'package:wiyamusic/widgets/confirmation_dialog.dart';
import 'package:wiyamusic/widgets/mini_player_bottom_space.dart';
import 'package:wiyamusic/widgets/overflow_menu_button.dart';
import 'package:wiyamusic/widgets/playlist_page/empty_playlist_state.dart';
import 'package:wiyamusic/widgets/playlist_page/search_bar_section.dart';
import 'package:wiyamusic/widgets/popup_menu_item.dart';
import 'package:wiyamusic/widgets/song_bar.dart';
import 'package:wiyamusic/widgets/sort_chips.dart';

enum OfflineSortType { default_, title, artist, dateAdded }

const _likedSongsOfflineId = 'user_liked_songs';

class UserSongsPage extends StatefulWidget {
  const UserSongsPage({super.key, required this.page});

  final String page;

  @override
  State<UserSongsPage> createState() => _UserSongsPageState();
}

class _UserSongsPageState extends State<UserSongsPage> {
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier('');
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  ValueNotifier<List> get _songsNotifier => switch (widget.page) {
    'liked' => userLikedSongsList,
    'offline' => userOfflineSongs,
    _ => userRecentlyPlayed,
  };

  List _getDisplayList(List songsList) {
    var list = filterSongsByQuery(songsList, _searchQueryNotifier.value);
    if (widget.page == 'offline') {
      list = _sortOfflineSongsLocal(list, _getCurrentOfflineSortType());
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchQueryNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = _titleForPage(context);
    final icon = _iconForPage();
    final expandedHeight = MediaQuery.sizeOf(context).height * 0.38;
    final isLiked = widget.page == 'liked';
    final isOffline = widget.page == 'offline';
    final isRecents = widget.page == 'recents';

    return ValueListenableBuilder<List>(
      valueListenable: _songsNotifier,
      builder: (context, songsList, _) {
        final songsLength = songsList.length;

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
                  onPressed: () => Navigator.pop(context),
                  tooltip: context.l10n!.back,
                ),
                actions: [
                  if (isLiked && songsLength > 0)
                    OverflowMenuButton<String>(
                      color: Colors.white,
                      onSelected: _handleLikedMenuAction,
                      itemBuilder: (context) {
                        final l10n = context.l10n!;
                        final colorScheme = Theme.of(context).colorScheme;
                        final fullyOffline = isPlaylistFullyOffline(
                          _songsNotifier.value,
                        );
                        final isDownloading = offlinePlaylistService
                            .isPlaylistDownloading(_likedSongsOfflineId);

                        return [
                          buildPopupMenuItem<String>(
                            value: isDownloading
                                ? 'cancel_download'
                                : fullyOffline
                                ? 'remove_offline'
                                : 'download',
                            icon: isDownloading
                                ? FluentIcons.dismiss_circle_24_regular
                                : fullyOffline
                                ? FluentIcons.arrow_download_off_24_regular
                                : FluentIcons.arrow_download_24_regular,
                            label: isDownloading
                                ? '${l10n.cancel} ${l10n.download.toLowerCase()}'
                                : fullyOffline
                                ? l10n.removeLikedSongsOffline
                                : l10n.downloadLikedSongs,
                            colorScheme: colorScheme,
                          ),
                          buildPopupMenuItem<String>(
                            value: 'clear',
                            icon: FluentIcons.delete_24_regular,
                            label: l10n.clearLikedSongs,
                            colorScheme: colorScheme,
                          ),
                        ];
                      },
                    ),
                  if (isRecents && songsLength > 0)
                    IconButton(
                      icon: const Icon(FluentIcons.delete_24_regular),
                      tooltip: context.l10n!.clear,
                      onPressed: _confirmClearRecents,
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.fromLTRB(48, 0, 48, 16),
                  centerTitle: true,
                  title: Text(
                    title,
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
                  background: _UserSongsHeaderBackground(icon: icon),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildControlsSection(
                  title: title,
                  songsLength: songsLength,
                  isLiked: isLiked,
                  isOffline: isOffline,
                  isRecents: isRecents,
                ),
              ),
              _buildSongList(title),
              const SliverMiniPlayerBottomSpace(),
            ],
          ),
        );
      },
    );
  }

  String _titleForPage(BuildContext context) {
    return switch (widget.page) {
      'liked' => context.l10n!.likedSongs,
      'offline' => context.l10n!.offlineSongs,
      'recents' => context.l10n!.recentlyPlayed,
      _ => context.l10n!.playlist,
    };
  }

  IconData _iconForPage() {
    return switch (widget.page) {
      'liked' => FluentIcons.heart_24_filled,
      'offline' => FluentIcons.cloud_off_24_filled,
      'recents' => FluentIcons.history_24_filled,
      _ => FluentIcons.heart_24_filled,
    };
  }

  String _typeLabel(BuildContext context) {
    return switch (widget.page) {
      'liked' => context.l10n!.likedSongs,
      'offline' => context.l10n!.offlineSongs,
      'recents' => context.l10n!.recentlyPlayed,
      _ => context.l10n!.playlist,
    };
  }

  IconData _typeChipIcon() {
    return switch (widget.page) {
      'liked' => FluentIcons.heart_16_regular,
      'offline' => FluentIcons.cloud_off_16_regular,
      'recents' => FluentIcons.history_16_regular,
      _ => FluentIcons.apps_list_24_regular,
    };
  }

  OfflineSortType _getCurrentOfflineSortType() {
    return OfflineSortType.values.firstWhere(
      (e) => e.name == offlineSortSetting,
      orElse: () => OfflineSortType.default_,
    );
  }

  Widget _buildControlsSection({
    required String title,
    required int songsLength,
    required bool isLiked,
    required bool isOffline,
    required bool isRecents,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(icon: _typeChipIcon(), label: _typeLabel(context)),
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
                    onPressed: () => _playAll(title),
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
                    onPressed: _shuffleAll,
                  ),
                ),
              ],
            ),
          ],
          if (isOffline && songsLength > 1) ...[
            const SizedBox(height: 12),
            SortChips<OfflineSortType>(
              currentSortType: _getCurrentOfflineSortType(),
              sortTypes: OfflineSortType.values,
              sortTypeToString: _getSortTypeDisplayText,
              onSelected: (type) {
                setState(() {
                  addOrUpdateData<String>(
                    'settings',
                    'offlineSortType',
                    type.name,
                  );
                  offlineSortSetting = type.name;
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

  void _playAll(String title) {
    final songsList = _songsNotifier.value;
    var sortedList = songsList;
    if (widget.page == 'offline') {
      sortedList = _sortOfflineSongsLocal(
        songsList,
        _getCurrentOfflineSortType(),
      );
    }
    audioHandler.playPlaylistSong(
      playlist: {
        'ytid': '',
        'title': title,
        'source': 'user-created',
        'playbackKind': _playbackKindForPage().name,
        'list': sortedList,
      },
      songIndex: 0,
      context: _playbackContextForPage(title),
    );
  }

  Future<void> _shuffleAll() async {
    final songs = _songsNotifier.value;
    if (songs.isEmpty) return;
    final title = _titleForPage(context);
    await audioHandler.playPlaylistSong(
      playlist: {
        'ytid': '',
        'title': title,
        'source': 'user-created',
        'playbackKind': _playbackKindForPage().name,
        'list': songs,
      },
      songIndex: 0,
      context: _playbackContextForPage(title),
      enableShuffle: true,
    );
  }

  PlaybackSourceKind _playbackKindForPage() {
    return switch (widget.page) {
      'liked' => PlaybackSourceKind.likedSongs,
      'offline' => PlaybackSourceKind.offlineSongs,
      'recents' => PlaybackSourceKind.recentlyPlayed,
      _ => PlaybackSourceKind.other,
    };
  }

  PlaybackContext _playbackContextForPage(String title) {
    return PlaybackContext(
      kind: _playbackKindForPage(),
      title: title,
    );
  }

  void _confirmClearRecents() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ConfirmationDialog(
          confirmationMessage: context.l10n!.clearRecentlyPlayedQuestion,
          submitMessage: context.l10n!.clear,
          isDangerous: true,
          onCancel: () => Navigator.pop(context),
          onSubmit: () {
            Navigator.pop(context);
            userRecentlyPlayed.value = [];
            addOrUpdateData<List>('user', 'recentlyPlayedSongs', []);
            showToast(context, context.l10n!.recentlyPlayedMsg);
          },
        );
      },
    );
  }

  void _handleLikedMenuAction(String value) {
    switch (value) {
      case 'download':
        unawaited(_downloadLikedSongs());
        break;
      case 'cancel_download':
        unawaited(
          offlinePlaylistService.cancelDownload(context, _likedSongsOfflineId),
        );
        break;
      case 'remove_offline':
        _confirmRemoveLikedSongsOffline();
        break;
      case 'clear':
        _confirmClearLikedSongs();
        break;
    }
  }

  Future<void> _downloadLikedSongs() async {
    final songs = List<dynamic>.from(userLikedSongsList.value);
    if (songs.isEmpty) {
      showToast(context, context.l10n!.playlistEmpty);
      return;
    }

    if (offlineMode.value) {
      showToast(context, context.l10n!.offlineMode);
      return;
    }

    if (offlinePlaylistService.isPlaylistDownloading(_likedSongsOfflineId)) {
      showToast(context, context.l10n!.alreadyDownloading);
      return;
    }

    final playlist = <String, dynamic>{
      'ytid': _likedSongsOfflineId,
      'title': context.l10n!.likedSongs,
      'source': 'user-created',
      'list': songs,
    };

    await offlinePlaylistService.downloadPlaylist(context, playlist);
  }

  void _confirmRemoveLikedSongsOffline() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return ConfirmationDialog(
          confirmationMessage: context.l10n!.removeLikedSongsOfflineConfirm,
          submitMessage: context.l10n!.removeLikedSongsOffline,
          isDangerous: true,
          onCancel: () => Navigator.pop(dialogContext),
          onSubmit: () {
            Navigator.pop(dialogContext);
            unawaited(_removeLikedSongsOffline());
          },
        );
      },
    );
  }

  Future<void> _removeLikedSongsOffline() async {
    try {
      final songs = List<dynamic>.from(userLikedSongsList.value);
      for (final song in songs) {
        final ytid = song is Map ? song['ytid']?.toString() : null;
        if (ytid == null || ytid.isEmpty) continue;
        if (isSongAlreadyOffline(ytid)) {
          await removeSongFromOffline(ytid);
        }
      }

      if (offlinePlaylistService.isPlaylistDownloaded(_likedSongsOfflineId)) {
        // Drop the liked-songs offline playlist marker without depending on
        // removeOfflinePlaylist song-retention rules for liked tracks.
        final updated = List<dynamic>.from(
          offlinePlaylistService.offlinePlaylists.value,
        )..removeWhere(
            (p) => p is Map && p['ytid']?.toString() == _likedSongsOfflineId,
          );
        offlinePlaylistService.offlinePlaylists.value = updated;
        unawaited(
          addOrUpdateData<List>(
            'userNoBackup',
            'offlinePlaylists',
            offlinePlaylistService.offlinePlaylists.value,
          ),
        );
      }

      if (mounted) {
        showToast(context, context.l10n!.songRemovedFromOffline);
      }
    } catch (e, stackTrace) {
      logger.log(
        'Error removing liked songs from offline',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) showToast(context, context.l10n!.error);
    }
  }

  void _confirmClearLikedSongs() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return ConfirmationDialog(
          confirmationMessage: context.l10n!.clearLikedSongsQuestion,
          submitMessage: context.l10n!.clearLikedSongs,
          isDangerous: true,
          onCancel: () => Navigator.pop(dialogContext),
          onSubmit: () {
            Navigator.pop(dialogContext);
            userLikedSongsList.value = [];
            unawaited(addOrUpdateData<List>('user', 'likedSongs', []));
            showToast(context, context.l10n!.removedFromLikedSongs);
          },
        );
      },
    );
  }

  Widget _buildSongList(String title) {
    final isLikedSongs = widget.page == 'liked';
    final isRecentlyPlayed = widget.page == 'recents';
    final isOfflineSongs = widget.page == 'offline';

    return ValueListenableBuilder<String>(
      valueListenable: _searchQueryNotifier,
      builder: (_, searchQuery, __) {
        final songsList = _songsNotifier.value;
        final listKeyScope = 'user_song_${widget.page}';
        final isSearching = searchQuery.isNotEmpty;
        final displayList = _getDisplayList(songsList);
        var sortedList = songsList;
        if (isOfflineSongs) {
          sortedList = _sortOfflineSongsLocal(
            songsList,
            _getCurrentOfflineSortType(),
          );
        }
        final playlist = {
          'ytid': '',
          'title': title,
          'source': 'user-created',
          'playbackKind': _playbackKindForPage().name,
          'list': sortedList,
        };

        if (displayList.isEmpty) {
          return EmptyPlaylistState(
            icon: isLikedSongs
                ? FluentIcons.heart_24_regular
                : isRecentlyPlayed
                ? FluentIcons.history_24_regular
                : FluentIcons.cloud_off_24_regular,
            message: context.l10n!.playlistEmpty,
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          sliver: SliverList(
            key: isOfflineSongs && !isSearching
                ? ValueKey(_getCurrentOfflineSortType())
                : null,
            delegate: SliverChildBuilderDelegate((context, index) {
              final song = displayList[index];
              final borderRadius = getItemBorderRadius(
                index,
                displayList.length,
              );
              return RepaintBoundary(
                key: listItemKey(listKeyScope, index, song),
                child: _buildSongBar(
                  song,
                  index,
                  borderRadius,
                  playlist,
                  isRecentSong: isRecentlyPlayed,
                ),
              );
            }, childCount: displayList.length),
          ),
        );
      },
    );
  }

  Widget _buildSongBar(
    Map song,
    int index,
    BorderRadius borderRadius,
    Map playlist, {
    bool isRecentSong = false,
  }) {
    final isLikedSongs = widget.page == 'liked';

    return SongBar(
      key: listItemKey('user_song', index, song),
      song,
      true,
      onPlay: () {
        final fullIndex = PlaylistUtils.findSongIndexByYtid(
          playlist,
          song['ytid'],
        );
        if (fullIndex == -1) {
          logger.log(
            'Warning: Song ${song['ytid']} not found in full song list',
          );
        }
        audioHandler.playPlaylistSong(
          playlist: playlist,
          songIndex: fullIndex != -1 ? fullIndex : index,
          context: _playbackContextForPage(
            playlist['title']?.toString() ?? _titleForPage(context),
          ),
        );
      },
      borderRadius: borderRadius,
      isRecentSong: isRecentSong,
      isFromLikedSongs: isLikedSongs,
      showPlayingIndicator: true,
    );
  }

  String _getSortTypeDisplayText(OfflineSortType type) {
    return switch (type) {
      OfflineSortType.default_ => context.l10n!.default_,
      OfflineSortType.title => context.l10n!.name,
      OfflineSortType.artist => context.l10n!.artist,
      OfflineSortType.dateAdded => context.l10n!.dateAdded,
    };
  }

  List _sortOfflineSongsLocal(List list, OfflineSortType type) {
    final sortedList = List<dynamic>.from(list);
    switch (type) {
      case OfflineSortType.default_:
        return sortedList;
      case OfflineSortType.title:
        sortedList.sort((a, b) {
          final titleA = (a['title'] ?? '').toString().toLowerCase();
          final titleB = (b['title'] ?? '').toString().toLowerCase();
          return titleA.compareTo(titleB);
        });
        break;
      case OfflineSortType.artist:
        sortedList.sort((a, b) {
          final artistA = (a['artist'] ?? '').toString().toLowerCase();
          final artistB = (b['artist'] ?? '').toString().toLowerCase();
          return artistA.compareTo(artistB);
        });
        break;
      case OfflineSortType.dateAdded:
        sortedList.sort((a, b) {
          final dateA = a['dateAdded'] as int? ?? 0;
          final dateB = b['dateAdded'] as int? ?? 0;
          return dateB.compareTo(dateA);
        });
        break;
    }
    return sortedList;
  }
}

class _UserSongsHeaderBackground extends StatelessWidget {
  const _UserSongsHeaderBackground({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: WiyaDesign.surfaceHigh,
          child: Center(
            child: Icon(
              icon,
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
