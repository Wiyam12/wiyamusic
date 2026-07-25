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
import 'package:go_router/go_router.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/main.dart' show audioHandler, logger;
import 'package:wiyamusic/services/artist_service.dart';
import 'package:wiyamusic/services/common_services.dart';
import 'package:wiyamusic/services/playlist_download_service.dart';
import 'package:wiyamusic/services/playlists_manager.dart';
import 'package:wiyamusic/services/router_service.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/theme/design_tokens.dart';
import 'package:wiyamusic/utilities/app_utils.dart';
import 'package:wiyamusic/utilities/artwork_provider.dart';
import 'package:wiyamusic/utilities/async_loader.dart';
import 'package:wiyamusic/utilities/flutter_toast.dart';
import 'package:wiyamusic/utilities/offline_playlist_dialogs.dart';
import 'package:wiyamusic/utilities/playlist_dialogs.dart';
import 'package:wiyamusic/utilities/playlist_utils.dart';
import 'package:wiyamusic/widgets/confirmation_dialog.dart';
import 'package:wiyamusic/widgets/home/home_media_card.dart';
import 'package:wiyamusic/widgets/home/home_section_header.dart';
import 'package:wiyamusic/widgets/mini_player_bottom_space.dart';
import 'package:wiyamusic/widgets/pinned_sliver_header.dart';
import 'package:wiyamusic/widgets/playlist_bar.dart';

enum _LibraryFilter { playlists, songs, albums, artists }

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  _LibraryPageState createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  /// `null` = no active filter (overview rails).
  _LibraryFilter? _filter;

  static const int _overviewCardLimit = 12;
  static const double _overviewCardWidth = 112;
  static const double _overviewRailHeight = 160;

  @override
  Widget build(BuildContext context) {
    // Show offline mode message if there is no content
    if (offlineMode.value) {
      final hasUserContent =
          userPlaylistFolders.value.isNotEmpty ||
          userPlaylists.value.isNotEmpty ||
          userCustomPlaylists.value.isNotEmpty;
      final hasOfflinePlaylists = offlinePlaylistService.offlinePlaylists.value
          .any((p) => p is Map && !PlaylistUtils.isArtistPlaylist(p));
      final hasOfflineArtists = getLikedArtistItems(
        offlineOnly: true,
      ).isNotEmpty;
      final hasOfflineSongs = userOfflineSongs.value.isNotEmpty;

      if (!hasUserContent &&
          !hasOfflinePlaylists &&
          !hasOfflineArtists &&
          !hasOfflineSongs) {
        final colorScheme = Theme.of(context).colorScheme;
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      FluentIcons.cloud_off_24_regular,
                      size: 40,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n!.offlineMode,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n!.noOfflineLibraryContent,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    final topInset = MediaQuery.paddingOf(context).top;
    // top padding (8) + title row (~48) + chips block (18 + ~36 + 8).
    const headerBodyHeight = 120.0;
    final stickyHeight = topInset + headerBodyHeight;

    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([
          pinnedPlaylistIds,
          offlineMode,
          userCustomPlaylists,
          userPlaylistFolders,
          offlinePlaylistService.offlinePlaylists,
          userLikedPlaylists,
          onlinePlaylists,
          userPlaylists,
          userLikedSongsList,
          userOfflineSongs,
          userRecentlyPlayed,
        ]),
        builder: (context, _) {
          return CustomScrollView(
            slivers: [
              PinnedSliverHeader(
                height: stickyHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, topInset + 8, 12, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                'Your ${context.l10n!.library}',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.8,
                                ),
                              ),
                            ),
                          ),
                          if (!offlineMode.value)
                            IconButton(
                              tooltip: context.l10n!.createFolder,
                              onPressed: _showCreateFolderDialog,
                              icon: Icon(
                                FluentIcons.folder_add_24_regular,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                      child: _LibraryFilterChips(
                        selected: _filter,
                        onSelected: (filter) {
                          setState(() {
                            _filter = _filter == filter ? null : filter;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              ..._buildFilterSlivers(),
              const SliverMiniPlayerBottomSpace(),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildFilterSlivers() {
    switch (_filter) {
      case null:
        return _buildOverviewSlivers();
      case _LibraryFilter.playlists:
        return _buildPlaylistsSlivers();
      case _LibraryFilter.songs:
        return _buildSongsSlivers();
      case _LibraryFilter.albums:
        return _buildAlbumsSlivers();
      case _LibraryFilter.artists:
        return _buildArtistsSlivers();
    }
  }

  List<Widget> _buildOverviewSlivers() {
    final recents = userRecentlyPlayed.value
        .whereType<Map>()
        .take(_overviewCardLimit)
        .map((s) => Map<String, dynamic>.from(s))
        .toList();
    final likedSongs = userLikedSongsList.value
        .whereType<Map>()
        .take(_overviewCardLimit)
        .map((s) => Map<String, dynamic>.from(s))
        .toList();
    final albums = _collectAlbums().take(_overviewCardLimit).toList();
    final artists = getLikedArtistItems(
      offlineOnly: offlineMode.value,
    ).take(_overviewCardLimit).toList();

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OverviewSongRail(
                title: context.l10n!.recentlyPlayed,
                songs: recents,
                railHeight: _overviewRailHeight,
                cardWidth: _overviewCardWidth,
                emptyMessage: 'No recently played songs',
                emptyIcon: FluentIcons.history_24_regular,
                emptyActionLabel: offlineMode.value ? null : 'Play Something',
                onEmptyAction: offlineMode.value
                    ? null
                    : () => NavigationManager.router.go('/home'),
                onSeeAll: offlineMode.value || recents.isEmpty
                    ? null
                    : () => NavigationManager.router.go(
                        '/library/userSongs/recents',
                      ),
              ),
              _OverviewSongRail(
                title: context.l10n!.likedSongs,
                songs: likedSongs,
                railHeight: _overviewRailHeight,
                cardWidth: _overviewCardWidth,
                emptyMessage: 'No liked songs yet',
                emptyIcon: FluentIcons.heart_24_regular,
                emptyActionLabel: offlineMode.value ? null : 'Explore Music',
                onEmptyAction: offlineMode.value
                    ? null
                    : () => NavigationManager.router.go('/home'),
                onSeeAll: likedSongs.isEmpty
                    ? null
                    : () => NavigationManager.router.go(
                        '/library/userSongs/liked',
                      ),
              ),
              _OverviewPlaylistRail(
                title: context.l10n!.likedPlaylists,
                items: getLikedPlaylistItems(
                  excludeAlbums: true,
                  offlineOnly: offlineMode.value,
                ).take(_overviewCardLimit).toList(),
                railHeight: _overviewRailHeight,
                cardWidth: _overviewCardWidth,
                emptyMessage: 'No liked playlists yet',
                emptyIcon: FluentIcons.heart_24_regular,
                emptyActionLabel: offlineMode.value
                    ? null
                    : 'Discover Playlists',
                onEmptyAction: offlineMode.value
                    ? null
                    : () => NavigationManager.router.go('/search'),
                subtitleBuilder: (_) => context.l10n!.playlist,
                onSeeAll:
                    getLikedPlaylistItems(
                      excludeAlbums: true,
                      offlineOnly: offlineMode.value,
                    ).isEmpty
                    ? null
                    : () => setState(() => _filter = _LibraryFilter.playlists),
                onOpen: _openPlaylistOrArtist,
              ),
              _OverviewPlaylistRail(
                title: context.l10n!.albums,
                items: albums,
                railHeight: _overviewRailHeight,
                cardWidth: _overviewCardWidth,
                emptyMessage: 'No albums yet',
                emptyIcon: FluentIcons.album_24_regular,
                emptyActionLabel: offlineMode.value ? null : 'Search Albums',
                onEmptyAction: offlineMode.value
                    ? null
                    : () => NavigationManager.router.go('/search'),
                subtitleBuilder: (_) => context.l10n!.album,
                onSeeAll: albums.isEmpty
                    ? null
                    : () => setState(() => _filter = _LibraryFilter.albums),
                onOpen: _openPlaylistOrArtist,
              ),
              _OverviewPlaylistRail(
                title: context.l10n!.artists,
                items: artists,
                railHeight: _overviewRailHeight,
                cardWidth: _overviewCardWidth,
                emptyMessage: 'No artists yet',
                emptyIcon: FluentIcons.person_24_regular,
                emptyActionLabel: offlineMode.value ? null : 'Find Artists',
                onEmptyAction: offlineMode.value
                    ? null
                    : () => NavigationManager.router.go('/search'),
                subtitleBuilder: (_) => context.l10n!.artist,
                titleBuilder: (item) => normalizeArtistDisplayTitle(
                  item['title']?.toString() ?? '',
                ),
                imageBuilder: (item) =>
                    normalizeArtistThumbnailUrl(item['image']?.toString()),
                onSeeAll: artists.isEmpty
                    ? null
                    : () => setState(() => _filter = _LibraryFilter.artists),
                onOpen: _openPlaylistOrArtist,
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Map> _collectAlbums() {
    final albums = <dynamic>[
      if (offlineMode.value) ...[
        ...getOfflineAlbumItems(),
        ...getLikedAlbumItems(offlineOnly: true),
      ] else ...[
        ...resolvePinnedPlaylists(pinnedPlaylistIds.value),
        ...getPlaylistsNotInFolders(),
        ...getLikedAlbumItems(),
      ],
    ].where((p) => p is Map && p['isAlbum'] == true);

    final seen = <String>{};
    final unique = <Map>[];
    for (final album in albums) {
      final map = Map<String, dynamic>.from(album as Map);
      final id = map['ytid']?.toString() ?? '';
      if (id.isNotEmpty && !seen.add(id)) continue;
      unique.add(map);
    }
    return unique;
  }

  Future<void> _openPlaylistOrArtist(Map item) async {
    final ytid = item['ytid']?.toString();
    if (ytid == null || ytid.isEmpty) return;

    final isArtist =
        item['source']?.toString() == 'youtube-artist' ||
        PlaylistUtils.isArtistPlaylist(item);

    // Prefer downloaded / liked local cache so opens work without internet.
    Map<String, dynamic>? offlineItem;
    for (final playlist in offlinePlaylistService.offlinePlaylists.value) {
      if (playlist is Map && playlist['ytid']?.toString() == ytid) {
        offlineItem = Map<String, dynamic>.from(playlist);
        break;
      }
    }

    Map<String, dynamic> resolved =
        offlineItem ?? Map<String, dynamic>.from(item);
    final existingList = resolved['list'];
    if (existingList is! List || existingList.isEmpty) {
      final local = await getPlaylistInfoForWidget(
        ytid,
        isArtist: isArtist,
        artistName: resolved['title']?.toString(),
        artistImage: resolved['image']?.toString(),
        localOnly: true,
      );
      if (local != null) {
        resolved = Map<String, dynamic>.from(local);
      }
    }

    if (!mounted) return;

    if (isArtist) {
      context.push(
        '/library/artist/${Uri.encodeComponent(ytid)}',
        extra: resolved,
      );
      return;
    }

    if (PlaylistUtils.isCustomPlaylist(resolved)) {
      context.push(
        '${NavigationManager.libraryPath}/playlist/$ytid',
        extra: resolved,
      );
      return;
    }

    context.push(
      '${NavigationManager.libraryPath}/playlist/$ytid',
      extra: resolved,
    );
  }

  Future<void> _onCreatePlaylistTap() async {
    final result = await showCreatePlaylistDialog(context);
    if (!mounted || result == null) return;

    if (result['type'] == 'custom') {
      final playlistId = result['id'];
      if (playlistId == null || playlistId.isEmpty) return;
      Map? playlist;
      for (final entry in userCustomPlaylists.value) {
        if (entry['ytid']?.toString() == playlistId) {
          playlist = entry;
          break;
        }
      }
      unawaited(
        context.push(
          '${NavigationManager.libraryPath}/playlist/$playlistId',
          extra: playlist,
        ),
      );
    }
  }

  List<Widget> _buildPlaylistsSlivers() {
    final isOffline = offlineMode.value;
    final colorScheme = Theme.of(context).colorScheme;

    final rawOfflinePlaylists = offlinePlaylistService.offlinePlaylists.value;
    final visibleOfflinePlaylists = rawOfflinePlaylists
        .where(
          (p) =>
              p is Map &&
              !PlaylistUtils.isArtistPlaylist(p) &&
              p['isAlbum'] != true,
        )
        .toList();
    final folders = isOffline
        ? userPlaylistFolders.value
              .where(PlaylistUtils.folderHasOfflinePlaylists)
              .toList()
        : userPlaylistFolders.value;

    final offlinePlaylistsNotInFolders =
        PlaylistUtils.filterOfflinePlaylistsNotInFolders(
          visibleOfflinePlaylists,
          folders,
        );
    final offlineIdsNotInFolders = PlaylistUtils.offlinePlaylistIdsNotInFolders(
      visibleOfflinePlaylists,
      folders,
    );
    final playlistsNotInFolders = PlaylistUtils.excludePlaylistsWithIds(
      getPlaylistsNotInFolders(),
      offlineIdsNotInFolders,
    ).where((p) => p['isAlbum'] != true).toList();

    final pinned = resolvePinnedPlaylists(pinnedPlaylistIds.value)
        .where((p) {
          return !isOffline ||
              offlinePlaylistService.isPlaylistDownloaded(
                p['ytid']?.toString() ?? '',
              );
        })
        .where((p) => p['isAlbum'] != true)
        .toList();

    final likedPlaylists = getLikedPlaylistItems(
      excludeAlbums: true,
      offlineOnly: isOffline,
    );
    // Avoid showing the same playlist twice when it's already listed above
    // (custom / folder / pinned / offline).
    final alreadyListedIds = <String>{
      for (final p in pinned) p['ytid']?.toString() ?? '',
      for (final f in folders)
        for (final p in (f['playlists'] as List? ?? const []))
          if (p is Map) p['ytid']?.toString() ?? '',
      for (final p in playlistsNotInFolders) p['ytid']?.toString() ?? '',
      for (final p in offlinePlaylistsNotInFolders)
        (p is Map ? p['ytid']?.toString() : null) ?? '',
    }..removeWhere((id) => id.isEmpty);

    final likedOnly = likedPlaylists.where((p) {
      final id = p['ytid']?.toString() ?? '';
      return id.isNotEmpty && !alreadyListedIds.contains(id);
    }).toList();

    final slivers = <Widget>[
      if (!isOffline)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Column(
              children: [
                _LibraryActionTile(
                  title: 'Create playlist',
                  leading: _SquareIconLead(
                    icon: FluentIcons.add_24_regular,
                    background: colorScheme.surfaceContainerHigh,
                  ),
                  onTap: _onCreatePlaylistTap,
                ),
                const SizedBox(height: 6),
                _LibraryActionTile(
                  title: context.l10n!.likedSongs,
                  subtitle: _songsCountLabel(userLikedSongsList.value.length),
                  leading: const _LikedSongsLead(),
                  onTap: () =>
                      NavigationManager.router.go('/library/userSongs/liked'),
                ),
              ],
            ),
          ),
        ),
    ];

    if (pinned.isNotEmpty) {
      slivers.add(_buildPlaylistListSliver(pinned));
    }
    if (folders.isNotEmpty) {
      slivers.add(_buildFolderListSliver(folders));
    }
    if (playlistsNotInFolders.isNotEmpty) {
      slivers.add(_buildPlaylistListSliver(playlistsNotInFolders));
    }
    if (offlinePlaylistsNotInFolders.isNotEmpty) {
      slivers.add(
        _buildPlaylistListSliver(
          offlinePlaylistsNotInFolders,
          isOfflinePlaylists: true,
        ),
      );
    }

    if (!isOffline && userPlaylists.value.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AsyncLoader<List<dynamic>>(
              future: getUserPlaylistsNotInFolders(),
              builder: (context, playlists) {
                final nonAlbums = playlists
                    .where((p) => p is Map && p['isAlbum'] != true)
                    .toList();
                if (nonAlbums.isEmpty) return const SizedBox.shrink();
                return Column(
                  children: [
                    for (var i = 0; i < nonAlbums.length; i++) ...[
                      if (i > 0) const SizedBox(height: 6),
                      _playlistBarFor(nonAlbums[i]),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      );
    }

    if (likedOnly.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              context.l10n!.likedPlaylists,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      );
      slivers.add(_buildPlaylistListSliver(likedOnly));
    }

    if (slivers.length == 1 && isOffline) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              context.l10n!.noPlaylistsAdded,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return slivers;
  }

  List<Widget> _buildSongsSlivers() {
    if (offlineMode.value) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: _LibraryActionTile(
              title: context.l10n!.offlineSongs,
              subtitle: _songsCountLabel(userOfflineSongs.value.length),
              leading: _SquareIconLead(
                icon: FluentIcons.cloud_off_24_regular,
                background: Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
              onTap: () =>
                  NavigationManager.router.go('/library/userSongs/offline'),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        sliver: SliverList.list(
          children: [
            _LibraryActionTile(
              title: context.l10n!.recentlyPlayed,
              subtitle: _songsCountLabel(userRecentlyPlayed.value.length),
              leading: _SquareIconLead(
                icon: FluentIcons.history_24_regular,
                background: Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
              onTap: () =>
                  NavigationManager.router.go('/library/userSongs/recents'),
            ),
            const SizedBox(height: 6),
            _LibraryActionTile(
              title: context.l10n!.likedSongs,
              subtitle: _songsCountLabel(userLikedSongsList.value.length),
              leading: const _LikedSongsLead(),
              onTap: () =>
                  NavigationManager.router.go('/library/userSongs/liked'),
            ),
            const SizedBox(height: 6),
            _LibraryActionTile(
              title: context.l10n!.offlineSongs,
              subtitle: _songsCountLabel(userOfflineSongs.value.length),
              leading: _SquareIconLead(
                icon: FluentIcons.cloud_off_24_regular,
                background: Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
              onTap: () =>
                  NavigationManager.router.go('/library/userSongs/offline'),
            ),
            const SizedBox(height: 6),
            _LibraryActionTile(
              title: context.l10n!.radioStations,
              leading: _SquareIconLead(
                icon: FluentIcons.sound_source_24_regular,
                background: Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
              onTap: () =>
                  NavigationManager.router.go('/library/radioStations'),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildAlbumsSlivers() {
    final albums = _collectAlbums();

    if (albums.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              context.l10n!.noPlaylistsAdded,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ];
    }

    return [
      _buildPlaylistListSliver(albums, isOfflinePlaylists: offlineMode.value),
    ];
  }

  List<Widget> _buildArtistsSlivers() {
    final artists = getLikedArtistItems(offlineOnly: offlineMode.value);
    if (artists.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              context.l10n!.noPlaylistsAdded,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ];
    }
    return [
      _buildPlaylistListSliver(artists, isOfflinePlaylists: offlineMode.value),
    ];
  }

  Widget _buildPlaylistListSliver(
    List playlists, {
    bool isOfflinePlaylists = false,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      sliver: SliverList.separated(
        itemCount: playlists.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          return _playlistBarFor(
            playlists[index],
            isOfflinePlaylists: isOfflinePlaylists,
          );
        },
      ),
    );
  }

  Widget _buildFolderListSliver(List folders) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      sliver: SliverList.separated(
        itemCount: folders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final folder = folders[index];
          return PlaylistBar(
            folder['name'],
            playlistData: folder,
            borderRadius: WiyaDesign.borderRadiusMedium,
            onDelete: () => _showDeleteFolderDialog(folder),
          );
        },
      ),
    );
  }

  Widget _playlistBarFor(dynamic playlist, {bool isOfflinePlaylists = false}) {
    final isArtist = playlist['source']?.toString() == 'youtube-artist';
    final title = playlist['title']?.toString() ?? context.l10n!.playlist;
    final playlistMap = playlist is Map
        ? Map<String, dynamic>.from(
            playlist.map((key, value) => MapEntry(key.toString(), value)),
          )
        : null;
    return PlaylistBar(
      key: listItemKey('library_playlist', playlist.hashCode, playlist),
      title,
      playlistId: playlist['ytid']?.toString(),
      playlistArtwork: playlist['image']?.toString(),
      subtitle: isArtist ? null : _playlistSongCountLabel(playlist),
      cubeIcon: isArtist
          ? FluentIcons.person_24_filled
          : FluentIcons.text_bullet_list_24_filled,
      isAlbum: isArtist ? false : playlist['isAlbum'],
      // Always pass data for library rows so opens hydrate from local cache
      // instead of going straight to the network.
      playlistData: playlistMap,
      onDelete:
          playlist['source'] == 'user-created' ||
              playlist['source'] == 'user-youtube' ||
              isOfflinePlaylists
          ? () => isOfflinePlaylists
                ? _showRemoveOfflinePlaylistDialog(playlist)
                : _showRemovePlaylistDialog(playlist)
          : null,
      borderRadius: WiyaDesign.borderRadiusMedium,
    );
  }

  String? _playlistSongCountLabel(dynamic playlist) {
    final list = playlist is Map ? playlist['list'] : null;
    if (list is! List) return null;
    return _songsCountLabel(list.length);
  }

  String _songsCountLabel(int count) {
    if (count <= 0) return context.l10n!.songs;
    return '$count ${context.l10n!.songs.toLowerCase()}';
  }

  void _showRemoveOfflinePlaylistDialog(Map playlist) {
    final playlistId = playlist['ytid']?.toString() ?? '';
    if (playlistId.isEmpty) return;
    showRemoveOfflinePlaylistDialog(context, playlistId);
  }

  void _showRemovePlaylistDialog(Map playlist) => showDialog(
    context: context,
    builder: (BuildContext context) {
      return ConfirmationDialog(
        confirmationMessage: context.l10n!.removePlaylistQuestion,
        submitMessage: context.l10n!.remove,
        onCancel: () {
          Navigator.of(context).pop();
        },
        onSubmit: () {
          Navigator.of(context).pop();

          final playlistId = playlist['ytid']?.toString() ?? '';

          if (playlistId.isEmpty) {
            logger.log('Playlist ID is missing, cannot remove playlist.');
            showToast(context, context.l10n!.error);
            return;
          }

          removeUserPlaylistEntry(playlist);
          if (offlinePlaylistService.isPlaylistDownloaded(playlistId)) {
            unawaited(offlinePlaylistService.removeOfflinePlaylist(playlistId));
          }
        },
      );
    },
  );

  void _showCreateFolderDialog() {
    var folderName = '';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        final bottomSafe = MediaQuery.paddingOf(sheetContext).bottom;

        void submit() {
          final trimmed = folderName.trim();
          if (trimmed.isEmpty) {
            showToast(sheetContext, sheetContext.l10n!.enterFolderName);
            return;
          }

          final (result, folderId) = createPlaylistFolder(
            trimmed,
            sheetContext,
          );
          showToast(sheetContext, result);
          Navigator.pop(sheetContext);

          if (folderId == null || !mounted) return;

          context.push(
            '/library/folder/$folderId/${Uri.encodeComponent(trimmed)}',
          );
        }

        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, bottomSafe + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        FluentIcons.folder_add_24_regular,
                        color: colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.l10n!.createFolder,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    labelText: context.l10n!.folderName,
                    hintText: context.l10n!.newFolder,
                    prefixIcon: Icon(
                      FluentIcons.folder_20_regular,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: colorScheme.surface,
                  ),
                  onChanged: (value) => folderName = value,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colorScheme.outline),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(context.l10n!.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: submit,
                        icon: const Icon(FluentIcons.add_20_regular),
                        label: Text(context.l10n!.create),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDeleteFolderDialog(Map folder) => showDialog(
    context: context,
    builder: (BuildContext context) {
      return ConfirmationDialog(
        confirmationMessage: context.l10n!.deleteFolderQuestion,
        submitMessage: context.l10n!.delete,
        onCancel: () {
          Navigator.of(context).pop();
        },
        onSubmit: () {
          final result = deletePlaylistFolder(folder['id'], context);
          Navigator.of(context).pop();
          showToast(context, result);
        },
      );
    },
  );
}

class _LibraryFilterChips extends StatelessWidget {
  const _LibraryFilterChips({required this.selected, required this.onSelected});

  final _LibraryFilter? selected;
  final ValueChanged<_LibraryFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final filters = <(_LibraryFilter, String)>[
      (_LibraryFilter.playlists, l10n.playlists),
      (_LibraryFilter.songs, l10n.songs),
      (_LibraryFilter.albums, l10n.albums),
      (_LibraryFilter.artists, l10n.artists),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < filters.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _FilterChip(
              label: filters[i].$2,
              selected: selected == filters[i].$1,
              onTap: () => onSelected(filters[i].$1),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected
          ? colorScheme.primary
          : colorScheme.surfaceContainerHigh.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryActionTile extends StatelessWidget {
  const _LibraryActionTile({
    required this.title,
    required this.leading,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: WiyaDesign.borderRadiusMedium,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: WiyaDesign.borderRadiusMedium,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SquareIconLead extends StatelessWidget {
  const _SquareIconLead({required this.icon, required this.background});

  final IconData icon;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: PlaylistBar.artworkSize,
      height: PlaylistBar.artworkSize,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Theme.of(context).colorScheme.onSurface),
    );
  }
}

class _LikedSongsLead extends StatelessWidget {
  const _LikedSongsLead();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: PlaylistBar.artworkSize,
      height: PlaylistBar.artworkSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [WiyaDesign.primaryBright, WiyaDesign.primaryDeep],
        ),
        boxShadow: WiyaDesign.softGlow(blur: 12, opacity: 0.25),
      ),
      child: const Icon(
        FluentIcons.heart_24_filled,
        color: Colors.white,
        size: 26,
      ),
    );
  }
}

class _OverviewSongRail extends StatelessWidget {
  const _OverviewSongRail({
    required this.title,
    required this.songs,
    required this.railHeight,
    required this.cardWidth,
    required this.emptyMessage,
    required this.emptyIcon,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.onSeeAll,
  });

  final String title;
  final List<Map<String, dynamic>> songs;
  final double railHeight;
  final double cardWidth;
  final String emptyMessage;
  final IconData emptyIcon;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          title: title,
          onAction: onSeeAll,
          padding: const EdgeInsets.fromLTRB(2, 16, 2, 10),
        ),
        if (songs.isEmpty)
          _OverviewEmptyState(
            height: railHeight,
            message: emptyMessage,
            icon: emptyIcon,
            actionLabel: emptyActionLabel,
            onAction: onEmptyAction,
          )
        else
          SizedBox(
            height: railHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: songs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final song = songs[index];
                return HomeMediaCard(
                  width: cardWidth,
                  title: song['title']?.toString() ?? '',
                  subtitle: song['artist']?.toString(),
                  imageUrl: _librarySongImage(song),
                  onTap: () => audioHandler.playSong(song),
                  onPlay: () => audioHandler.playSong(song),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _OverviewPlaylistRail extends StatelessWidget {
  const _OverviewPlaylistRail({
    required this.title,
    required this.items,
    required this.railHeight,
    required this.cardWidth,
    required this.emptyMessage,
    required this.emptyIcon,
    required this.subtitleBuilder,
    required this.onOpen,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.titleBuilder,
    this.imageBuilder,
    this.onSeeAll,
  });

  final String title;
  final List items;
  final double railHeight;
  final double cardWidth;
  final String emptyMessage;
  final IconData emptyIcon;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final String Function(Map item) subtitleBuilder;
  final String Function(Map item)? titleBuilder;
  final String? Function(Map item)? imageBuilder;
  final void Function(Map item) onOpen;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          title: title,
          onAction: onSeeAll,
          padding: const EdgeInsets.fromLTRB(2, 16, 2, 10),
        ),
        if (items.isEmpty)
          _OverviewEmptyState(
            height: railHeight,
            message: emptyMessage,
            icon: emptyIcon,
            actionLabel: emptyActionLabel,
            onAction: onEmptyAction,
          )
        else
          SizedBox(
            height: railHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final item = Map<String, dynamic>.from(items[index] as Map);
                return HomeMediaCard(
                  width: cardWidth,
                  title:
                      titleBuilder?.call(item) ??
                      item['title']?.toString() ??
                      '',
                  subtitle: subtitleBuilder(item),
                  imageUrl:
                      imageBuilder?.call(item) ?? item['image']?.toString(),
                  onTap: () => onOpen(item),
                  onPlay: () => onOpen(item),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _OverviewEmptyState extends StatelessWidget {
  const _OverviewEmptyState({
    required this.height,
    required this.message,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  final double height;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasAction = actionLabel != null && onAction != null;

    return SizedBox(
      height: hasAction ? height + 28 : height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: WiyaDesign.borderRadiusMedium,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 28,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (hasAction) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String? _librarySongImage(Map song) {
  final highRes = song['highResImage']?.toString();
  if (highRes != null && highRes.isNotEmpty) return highRes;
  final lowRes = song['lowResImage']?.toString();
  if (lowRes != null && lowRes.isNotEmpty) return lowRes;
  final artworkPath = song['artworkPath']?.toString();
  if (ArtworkProvider.localFileExists(artworkPath)) return artworkPath;
  return null;
}
