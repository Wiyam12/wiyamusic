import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wiyamusic/constants/app_constants.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/services/common_services.dart';
// import 'package:wiyamusic/services/listening_stats_service.dart';
import 'package:wiyamusic/services/playlists_manager.dart';
import 'package:wiyamusic/services/router_service.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/theme/design_tokens.dart';
import 'package:wiyamusic/utilities/app_utils.dart';
import 'package:wiyamusic/utilities/artwork_provider.dart';
import 'package:wiyamusic/utilities/async_loader.dart';
// import 'package:wiyamusic/utilities/listening_stats_utils.dart';
import 'package:wiyamusic/widgets/announcement_box.dart';
import 'package:wiyamusic/widgets/home/home_featured_hero.dart';
import 'package:wiyamusic/widgets/home/home_media_card.dart';
import 'package:wiyamusic/widgets/home/home_section_header.dart';
// import 'package:wiyamusic/widgets/listening_recap_card.dart';
import 'package:wiyamusic/widgets/mini_player_bottom_space.dart';
import 'package:wiyamusic/widgets/pinned_sliver_header.dart';
import 'package:wiyamusic/widgets/search_entry_bar.dart';
// import 'package:wiyamusic/widgets/section_header.dart';
import 'package:wiyamusic/widgets/song_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Future<List> _suggestedPlaylistsFuture;
  late Future<List> _recommendedSongsFuture;

  static const int _horizontalCardLimit = 8;

  @override
  void initState() {
    super.initState();
    _suggestedPlaylistsFuture = getPlaylists(
      playlistsNum: recommendedCubesNumber,
    );
    _recommendedSongsFuture = getRecommendedSongs();
    externalRecommendations.addListener(_refreshRecommendedSongs);
  }

  @override
  void dispose() {
    externalRecommendations.removeListener(_refreshRecommendedSongs);
    super.dispose();
  }

  void _refreshRecommendedSongs() {
    if (!mounted) return;
    setState(() {
      _recommendedSongsFuture = getRecommendedSongs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    // CustomSearchBar: vertical padding 16*2 + SearchBar minHeight 45.
    const searchBarBodyHeight = 77.0;
    final stickyHeight = topInset + searchBarBodyHeight;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          PinnedSliverHeader(
            height: stickyHeight,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                10,
                topInset,
                10,
                0,
              ),
              child: const SearchEntryBar(
                hintText: 'Search songs, artists, albums...',
              ),
            ),
          ),
          SliverPadding(
            padding: commonSingleChildScrollViewPadding,
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                ValueListenableBuilder<String?>(
                  valueListenable: announcementURL,
                  builder: (_, url, __) {
                    if (url == null) return const SizedBox.shrink();
                    final isSponsorshipAnnouncement =
                        isSponsorshipAnnouncementUrl(url);
                    final message = isSponsorshipAnnouncement
                        ? context.l10n!.sponsorProject
                        : context.l10n!.newAnnouncement;
                    final icon = isSponsorshipAnnouncement
                        ? FluentIcons.heart_24_filled
                        : FluentIcons.megaphone_24_filled;

                    return AnnouncementBox(
                      message: message,
                      url: url,
                      icon: icon,
                      onDismiss: () async {
                        announcementURL.value = null;
                      },
                    );
                  },
                ),
                _buildFeaturedHero(),
                _buildRecentlyPlayedSection(),
                _buildMadeForYouSection(),
                _buildRecommendedSongsSection(),
              ]),
            ),
          ),
          const SliverMiniPlayerBottomSpace(),
        ],
      ),
    );
  }

  Widget _buildFeaturedHero() {
    return AsyncLoader<List<dynamic>>(
      future: _suggestedPlaylistsFuture,
      builder: (context, playlists) {
        if (playlists.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: HomeFeaturedHero(
            playlists: playlists,
            onOpen: _openPlaylist,
            onPlay: _openPlaylist,
          ),
        );
      },
    );
  }

  Widget _buildRecentlyPlayedSection() {
    return ValueListenableBuilder<List>(
      valueListenable: userRecentlyPlayed,
      builder: (context, songs, _) {
        if (songs.isEmpty) return const SizedBox.shrink();
        final queue = songs
            .whereType<Map>()
            .map((song) => Map<String, dynamic>.from(song))
            .toList(growable: false);
        final items = queue.take(_horizontalCardLimit).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeSectionHeader(
              title: context.l10n!.recentlyPlayed,
              onAction: () =>
                  NavigationManager.router.go('/library/userSongs/recents'),
            ),
            SizedBox(
              height: 204,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final song = items[index];
                  return HomeMediaCard(
                    title: song['title']?.toString() ?? '',
                    subtitle: song['artist']?.toString(),
                    imageUrl: _songImage(song),
                    onTap: () => _playRecentlyPlayedAt(queue, index),
                    onPlay: () => _playRecentlyPlayedAt(queue, index),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _playRecentlyPlayedAt(
    List<Map<String, dynamic>> queue,
    int songIndex,
  ) async {
    if (queue.isEmpty) return;
    final safeIndex = songIndex.clamp(0, queue.length - 1);
    await audioHandler.playPlaylistSong(
      playlist: {
        'ytid': '',
        'title': context.l10n!.recentlyPlayed,
        'source': 'user-created',
        'list': queue,
      },
      songIndex: safeIndex,
    );
  }

  Widget _buildMadeForYouSection() {
    return ValueListenableBuilder<List<Map>>(
      valueListenable: userLikedPlaylists,
      builder: (context, likedPlaylists, _) {
        final playlists = likedPlaylists
            .where((playlist) => !isArtistPlaylist(playlist))
            .take(_horizontalCardLimit)
            .toList();

        if (playlists.isEmpty) {
          return AsyncLoader<List<dynamic>>(
            future: _suggestedPlaylistsFuture,
            builder: (context, suggested) {
              if (suggested.isEmpty) return const SizedBox.shrink();
              return _buildHorizontalPlaylistRail(
                title: context.l10n!.recommendedForYou,
                playlists: suggested.take(_horizontalCardLimit).toList(),
                showForYouBadge: true,
              );
            },
          );
        }

        return _buildHorizontalPlaylistRail(
          title: context.l10n!.recommendedForYou,
          playlists: playlists,
          showForYouBadge: true,
          onSeeAll: () => NavigationManager.router.go('/library'),
        );
      },
    );
  }

  Widget _buildHorizontalPlaylistRail({
    required String title,
    required List playlists,
    required bool showForYouBadge,
    VoidCallback? onSeeAll,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(title: title, onAction: onSeeAll),
        SizedBox(
          height: 204,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: playlists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final playlist = Map<String, dynamic>.from(
                playlists[index] as Map,
              );
              return HomeMediaCard(
                title: playlist['title']?.toString() ?? '',
                subtitle: playlist['isAlbum'] == true
                    ? context.l10n!.album
                    : context.l10n!.playlist,
                imageUrl: playlist['image']?.toString(),
                showForYouBadge: showForYouBadge,
                onTap: () => _openPlaylist(playlist),
                onPlay: () => _openPlaylist(playlist),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendedSongsSection() {
    return AsyncLoader<List<dynamic>>(
      future: _recommendedSongsFuture,
      builder: (context, data) {
        if (data.isEmpty) return const SizedBox.shrink();
        return _buildRecommendedForYouSection(context, data);
      },
    );
  }

  // Widget _buildCurrentMonthRecapSection() {
  //   return ValueListenableBuilder<bool>(
  //     valueListenable: wrappedEnabled,
  //     builder: (_, isEnabled, __) {
  //       if (!isEnabled) return const SizedBox.shrink();
  //
  //       final currentMonthKey = listeningStatsMonthKey(DateTime.now());
  //       final monthStats = listeningStatsService.monthStats(currentMonthKey);
  //       final songs = listeningStatsService.monthTopSongs(currentMonthKey);
  //       final displayMinutes = monthDisplayMinutes(monthStats);
  //       if (displayMinutes <= 0 && songs.isEmpty) {
  //         return const SizedBox.shrink();
  //       }
  //
  //       final previewSongs = songs.take(wrappedShareSongsLimit).toList();
  //       final periodLabel = formatMonthPeriodLabel(
  //         Localizations.localeOf(context),
  //         currentMonthKey,
  //       );
  //
  //       return Column(
  //         children: [
  //           SectionHeader(
  //             title: context.l10n!.timeMachine,
  //             icon: FluentIcons.data_trending_24_filled,
  //           ),
  //           ListeningRecapCard(
  //             periodLabel: periodLabel,
  //             minutes: displayMinutes,
  //             songs: previewSongs,
  //             onSongTap: (index) => _playRecapSongs(previewSongs, index),
  //           ),
  //           Padding(
  //             padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
  //             child: SizedBox(
  //               width: double.infinity,
  //               child: FilledButton.tonalIcon(
  //                 onPressed: () => context.push('/home/timeMachine'),
  //                 icon: const Icon(FluentIcons.arrow_right_24_regular),
  //                 label: Text(context.l10n!.listeningStats),
  //               ),
  //             ),
  //           ),
  //         ],
  //       );
  //     },
  //   );
  // }
  //
  // Future<void> _playRecapSongs(
  //   List<Map<String, dynamic>> songs,
  //   int index,
  // ) async {
  //   if (songs.isEmpty) return;
  //   await audioHandler.playPlaylistSong(
  //     playlist: {'title': context.l10n!.timeMachine, 'list': songs},
  //     songIndex: index,
  //   );
  // }

  Widget _buildRecommendedForYouSection(
    BuildContext context,
    List<dynamic> data,
  ) {
    final recommendedTitle = context.l10n!.suggestedPlaylists;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        HomeSectionHeader(
          title: recommendedTitle,
          actionLabel: context.l10n!.play,
          onAction: () async {
            await audioHandler.playPlaylistSong(
              playlist: {'title': recommendedTitle, 'list': data},
              songIndex: 0,
            );
          },
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(WiyaDesign.cornerRadius),
            border: Border.all(color: colorScheme.primary, width: 1.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(WiyaDesign.cornerRadius - 1.5),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: data.length,
              padding: commonListViewBottomPadding,
              itemBuilder: (context, index) {
                final borderRadius = getItemBorderRadius(index, data.length);
                return RepaintBoundary(
                  key: listItemKey('home_recommended', index, data[index]),
                  child: SongBar(
                    data[index],
                    true,
                    backgroundColor: Colors.transparent,
                    borderRadius: borderRadius,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _openPlaylist(Map playlist) {
    final ytid = playlist['ytid']?.toString();
    if (ytid == null || ytid.isEmpty) return;
    context.push('/home/playlist/$ytid');
  }

  String? _songImage(Map song) {
    final highRes = song['highResImage']?.toString();
    if (highRes != null && highRes.isNotEmpty) return highRes;
    final lowRes = song['lowResImage']?.toString();
    if (lowRes != null && lowRes.isNotEmpty) return lowRes;
    final artworkPath = song['artworkPath']?.toString();
    if (ArtworkProvider.localFileExists(artworkPath)) return artworkPath;
    return null;
  }
}
