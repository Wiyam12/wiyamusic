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
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wiyamusic/constants/app_constants.dart';
import 'package:wiyamusic/controllers/search_discovery_controller.dart';
import 'package:wiyamusic/database/radio_stations.db.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/models/radio_model.dart';
import 'package:wiyamusic/models/search_discovery_models.dart';
import 'package:wiyamusic/services/common_services.dart';
import 'package:wiyamusic/services/data_manager.dart';
import 'package:wiyamusic/services/playlists_manager.dart';
import 'package:wiyamusic/services/router_service.dart';
import 'package:wiyamusic/utilities/app_utils.dart';
import 'package:wiyamusic/utilities/flutter_toast.dart';
import 'package:wiyamusic/utilities/search_navigation.dart';
import 'package:wiyamusic/widgets/artist_bar.dart';
import 'package:wiyamusic/widgets/custom_search_bar.dart';
import 'package:wiyamusic/widgets/home/home_section_header.dart';
import 'package:wiyamusic/widgets/mini_player_bottom_space.dart';
import 'package:wiyamusic/widgets/pinned_sliver_header.dart';
import 'package:wiyamusic/widgets/playlist_bar.dart';
import 'package:wiyamusic/widgets/radio_station_card.dart';
import 'package:wiyamusic/widgets/search/search_discovery.dart';
import 'package:wiyamusic/widgets/section_title.dart';
import 'package:wiyamusic/widgets/song_bar.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  _SearchPageState createState() => _SearchPageState();
}

// Global ValueNotifier for search history to make it reactive
final ValueNotifier<List> searchHistoryNotifier = ValueNotifier<List>(
  Hive.box('user').get('searchHistory', defaultValue: []),
);

// Backward compatibility - keep the global variable for existing code
List get searchHistory => searchHistoryNotifier.value;
set searchHistory(List value) {
  searchHistoryNotifier.value = value;
}

void reloadSearchHistoryFromStorage() {
  searchHistoryNotifier.value = Hive.box(
    'user',
  ).get('searchHistory', defaultValue: []);
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchBar = TextEditingController();
  final FocusNode _inputNode = FocusNode();
  final ValueNotifier<bool> _fetchingSongs = ValueNotifier(false);
  int maxSongsInList = 15;
  List<dynamic> _songsSearchResult = [];
  List<Map<String, dynamic>> _artistsSearchResult = [];
  List<dynamic> _albumsSearchResult = [];
  List<dynamic> _playlistsSearchResult = [];
  List<RadioStation> _radioStationsSearchResult = [];
  List<String> _suggestionsList = [];
  Timer? _debounce;
  int _latestSuggestionRequest = 0;
  int _lastHandledAutofocusToken = 0;
  bool _isSearchFocused = false;
  int _maxArtistsInList = 3;
  late final SearchDiscoveryController _discoveryController;

  bool get _hasSearchResults =>
      _songsSearchResult.isNotEmpty ||
      _artistsSearchResult.isNotEmpty ||
      _albumsSearchResult.isNotEmpty ||
      _playlistsSearchResult.isNotEmpty ||
      _radioStationsSearchResult.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _discoveryController = SearchDiscoveryController()
      ..addListener(_onDiscoveryChanged);
    _inputNode.addListener(_onFocusChange);
    SearchNavigation.autofocusToken.addListener(_onAutofocusToken);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeAutofocusRequest();
    });
    unawaited(_discoveryController.load());
  }

  void _onDiscoveryChanged() {
    if (mounted) setState(() {});
  }

  void _onFocusChange() {
    final focused = _inputNode.hasFocus;
    if (focused == _isSearchFocused) return;
    setState(() => _isSearchFocused = focused);
  }

  /// Clears query/results and returns to Browse/Trending discovery.
  void _resetToDiscovery({bool clearText = false}) {
    _debounce?.cancel();
    _latestSuggestionRequest++;
    if (clearText && _searchBar.text.isNotEmpty) {
      _searchBar.clear();
    }
    _songsSearchResult = [];
    _artistsSearchResult = [];
    _albumsSearchResult = [];
    _playlistsSearchResult = [];
    _radioStationsSearchResult = [];
    _suggestionsList = [];
    _fetchingSongs.value = false;
    _maxArtistsInList = 3;
    _isSearchFocused = false;
    if (_inputNode.hasFocus) {
      _inputNode.unfocus();
    }
    if (mounted) setState(() {});
  }

  void _onAutofocusToken() {
    _consumeAutofocusRequest();
  }

  void _consumeAutofocusRequest() {
    final token = SearchNavigation.autofocusToken.value;
    if (token == 0 || token == _lastHandledAutofocusToken) return;
    _lastHandledAutofocusToken = token;

    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _inputNode.requestFocus();
      final text = _searchBar.text;
      _searchBar.selection = TextSelection.collapsed(offset: text.length);
    });
  }

  Future<void> _submitSearch([String? query]) async {
    if (query != null) {
      _searchBar.text = query;
      _searchBar.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchBar.text.length),
      );
    }

    _latestSuggestionRequest++;
    _debounce?.cancel();
    _suggestionsList = [];
    _maxArtistsInList = 3;
    if (mounted) setState(() {});

    await search();
    _inputNode.unfocus();
  }

  void _openGenrePage(String genre) {
    final normalized = genre.trim();
    if (normalized.isEmpty) return;
    _inputNode.unfocus();
    context.push(
      '${NavigationManager.searchPath}/genre/${Uri.encodeComponent(normalized)}',
    );
  }

  void _removeHistoryQuery(String query) {
    if (!searchHistory.contains(query)) return;
    final updatedHistory = List.from(searchHistory)..remove(query);
    searchHistoryNotifier.value = updatedHistory;
    unawaited(addOrUpdateData<List>('user', 'searchHistory', updatedHistory));
  }

  @override
  void dispose() {
    _inputNode.removeListener(_onFocusChange);
    SearchNavigation.autofocusToken.removeListener(_onAutofocusToken);
    _discoveryController
      ..removeListener(_onDiscoveryChanged)
      ..dispose();
    _searchBar.dispose();
    _inputNode.dispose();
    _fetchingSongs.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> search() async {
    final query = _searchBar.text;

    if (query.isEmpty) {
      _resetToDiscovery();
      return;
    }
    _fetchingSongs.value = true;

    if (!searchHistory.contains(query)) {
      final updatedHistory = List.from(searchHistory)..insert(0, query);
      searchHistoryNotifier.value = updatedHistory;
      unawaited(addOrUpdateData<List>('user', 'searchHistory', updatedHistory));
    }

    try {
      final results = await Future.wait<List<dynamic>>([
        fetchSongsList(query),
        searchArtists(query),
        getPlaylists(query: query, type: 'album'),
        getPlaylists(query: query, type: 'playlist'),
      ]);

      _songsSearchResult = results[0];
      _artistsSearchResult = results[1]
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
      if (_songsSearchResult.isEmpty && _artistsSearchResult.isNotEmpty) {
        _songsSearchResult = await _fetchSongsForResolvedArtist(query);
      }
      _albumsSearchResult = results[2];
      _playlistsSearchResult = results[3];

      _radioStationsSearchResult = radioStationsDB
          .where(
            (station) =>
                station.name.toLowerCase().contains(query.toLowerCase()) ||
                (station.genre?.toLowerCase().contains(query.toLowerCase()) ??
                    false),
          )
          .toList();
    } catch (e, stackTrace) {
      logger.log(
        'Error while searching online songs',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _fetchingSongs.value = false;
      if (mounted) setState(() {});
    }
  }

  Future<List<dynamic>> _fetchSongsForResolvedArtist(String query) async {
    final artistName = _artistsSearchResult.first['title']?.toString().trim();
    if (artistName == null || artistName.isEmpty) return [];

    final fallbackQueries = <String>{
      if (artistName.toLowerCase() != query.trim().toLowerCase()) artistName,
      '$artistName songs',
      '$artistName music',
    };

    for (final fallbackQuery in fallbackQueries) {
      final songs = await fetchSongsList(fallbackQuery);
      if (songs.isNotEmpty) return songs;
    }

    return [];
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final topInset = MediaQuery.paddingOf(context).top;
    // CustomSearchBar: vertical padding 16*2 + SearchBar minHeight 45.
    const searchBarBodyHeight = 77.0;
    final stickyHeight = topInset + searchBarBodyHeight;

    return Scaffold(
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          PinnedSliverHeader(
            height: stickyHeight,
            child: Padding(
              padding: EdgeInsets.fromLTRB(10, topInset, 10, 0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 600;
                  final bar = ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isWide ? 600 : double.infinity,
                    ),
                    child: CustomSearchBar(
                      loadingProgressNotifier: _fetchingSongs,
                      controller: _searchBar,
                      focusNode: _inputNode,
                      labelText: 'Search songs, artists, albums...',
                      onChanged: (value) {
                        _debounce?.cancel();
                        final query = value;
                        final requestId = ++_latestSuggestionRequest;

                        if (query.isEmpty) {
                          _resetToDiscovery();
                          return;
                        }

                        // Typing a new query leaves previous results behind.
                        if (_hasSearchResults) {
                          _songsSearchResult = [];
                          _artistsSearchResult = [];
                          _albumsSearchResult = [];
                          _playlistsSearchResult = [];
                          _radioStationsSearchResult = [];
                          if (mounted) setState(() {});
                        }

                        _debounce = Timer(
                          const Duration(milliseconds: 300),
                          () async {
                            final searchSuggestions =
                                await getSearchSuggestions(query);

                            if (!mounted ||
                                requestId != _latestSuggestionRequest ||
                                _searchBar.text != query) {
                              return;
                            }

                            _suggestionsList = List<String>.from(
                              searchSuggestions,
                            );
                            if (mounted) setState(() {});
                          },
                        );
                      },
                      onSubmitted: (String value) {
                        _submitSearch();
                      },
                    ),
                  );
                  if (isWide) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [bar],
                    );
                  }
                  return bar;
                },
              ),
            ),
          ),
          SliverPadding(
            padding: commonSingleChildScrollViewPadding,
            sliver: SliverToBoxAdapter(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _buildBelowSearchBar(context, primaryColor),
              ),
            ),
          ),
          const SliverMiniPlayerBottomSpace(),
        ],
      ),
    );
  }

  Widget _buildBelowSearchBar(BuildContext context, Color primaryColor) {
    if (_hasSearchResults) {
      return KeyedSubtree(
        key: const ValueKey('search-results'),
        child: _buildSearchResults(context, primaryColor),
      );
    }

    if (_isSearchFocused) {
      return KeyedSubtree(
        key: const ValueKey('search-recents'),
        child: _buildFocusedContent(context),
      );
    }

    return KeyedSubtree(
      key: const ValueKey('search-discovery'),
      child: SearchDiscoveryContent(
        trendingSearches: _discoveryController.state.snapshot.trendingSearches,
        topArtists: _discoveryController.state.snapshot.topArtists,
        isLoading: _discoveryController.state.showSkeleton,
        showEmpty:
            _discoveryController.state.status == SearchDiscoveryStatus.error ||
            _discoveryController.state.status == SearchDiscoveryStatus.empty,
        onRetry: () => unawaited(_discoveryController.retry()),
        onTrendingTap: _submitSearch,
        onGenreTap: _openGenrePage,
        onSeeAllArtists: () => _submitSearch('Top artists'),
        onArtistTap: (artist) {
          final artistId =
              artist['ytid']?.toString() ?? artist['title']?.toString() ?? '';
          if (artistId.isEmpty) return;
          context.push(
            '${NavigationManager.searchPath}/artist/${Uri.encodeComponent(artistId)}',
            extra: artist,
          );
        },
      ),
    );
  }

  Widget _buildFocusedContent(BuildContext context) {
    if (_suggestionsList.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HomeSectionHeader(title: 'Suggestions'),
          for (final suggestion in _suggestionsList)
            SearchRecentTile(
              title: suggestion,
              subtitle: 'Search',
              onTap: () => _submitSearch(suggestion),
              onRemove: () {
                _suggestionsList = List<String>.from(_suggestionsList)
                  ..remove(suggestion);
                setState(() {});
              },
            ),
        ],
      );
    }

    return ValueListenableBuilder<List>(
      valueListenable: searchHistoryNotifier,
      builder: (context, history, _) {
        if (history.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(2, 24, 2, 0),
            child: Text(
              'No recent searches yet',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const HomeSectionHeader(title: 'Recent searches'),
            for (final raw in history)
              SearchRecentTile(
                title: raw.toString(),
                subtitle: 'Search',
                onTap: () => _submitSearch(raw.toString()),
                onRemove: () => _removeHistoryQuery(raw.toString()),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSearchResults(BuildContext context, Color primaryColor) {
    final widgets = <Widget>[];

    if (_artistsSearchResult.isNotEmpty) {
      widgets.add(
        SectionTitle(
          context.l10n!.artists,
          primaryColor,
          icon: FluentIcons.person_24_filled,
        ),
      );

      final artists = _artistsSearchResult.take(_maxArtistsInList).toList();
      for (var index = 0; index < artists.length; index++) {
        final artist = Map<String, dynamic>.from(artists[index]);
        final artistId =
            artist['ytid']?.toString() ?? artist['title']?.toString() ?? '';
        if (artistId.isEmpty) continue;

        final borderRadius = getItemBorderRadius(index, artists.length);
        widgets.add(
          ArtistBar(
            key: listItemKey('search_artist', index, artist),
            artist: artist,
            borderRadius: borderRadius,
            onTap: () {
              context.push(
                '${NavigationManager.searchPath}/artist/${Uri.encodeComponent(artistId)}',
                extra: artist,
              );
            },
          ),
        );
      }
    }

    if (_songsSearchResult.isNotEmpty) {
      widgets.add(
        SectionTitle(
          context.l10n!.songs,
          primaryColor,
          icon: FluentIcons.music_note_1_24_filled,
        ),
      );

      final songsCount = _songsSearchResult.length > maxSongsInList
          ? maxSongsInList
          : _songsSearchResult.length;

      for (var index = 0; index < songsCount; index++) {
        final song = _songsSearchResult[index];
        final borderRadius = getItemBorderRadius(index, songsCount);
        widgets.add(
          SongBar(
            song,
            true,
            key: listItemKey('search_song', index, song),
            showMusicDuration: true,
            borderRadius: borderRadius,
          ),
        );
      }
    }

    if (_albumsSearchResult.isNotEmpty) {
      widgets.add(
        SectionTitle(
          context.l10n!.albums,
          primaryColor,
          icon: FluentIcons.album_24_filled,
        ),
      );

      final albumsCount = _albumsSearchResult.length > maxSongsInList
          ? maxSongsInList
          : _albumsSearchResult.length;

      for (var index = 0; index < albumsCount; index++) {
        final playlist = _albumsSearchResult[index];
        final borderRadius = getItemBorderRadius(index, albumsCount);

        widgets.add(
          PlaylistBar(
            key: listItemKey('search_album', index, playlist),
            playlist['title'],
            playlistId: playlist['ytid'],
            playlistArtwork: playlist['image'],
            cubeIcon: FluentIcons.cd_16_filled,
            isAlbum: true,
            borderRadius: borderRadius,
          ),
        );
      }
    }

    if (_playlistsSearchResult.isNotEmpty) {
      widgets.add(
        SectionTitle(
          context.l10n!.playlists,
          primaryColor,
          icon: FluentIcons.text_bullet_list_24_filled,
        ),
      );

      final playlistsCount = _playlistsSearchResult.length > maxSongsInList
          ? maxSongsInList
          : _playlistsSearchResult.length;

      for (var index = 0; index < playlistsCount; index++) {
        final playlist = _playlistsSearchResult[index];
        final isLast = index == playlistsCount - 1;
        final borderRadius = getItemBorderRadius(index, playlistsCount);

        widgets.add(
          Padding(
            padding: isLast ? commonListViewBottomPadding : EdgeInsets.zero,
            child: PlaylistBar(
              key: listItemKey('search_playlist', index, playlist),
              playlist['title'],
              playlistId: playlist['ytid'],
              playlistArtwork: playlist['image'],
              cubeIcon: FluentIcons.apps_list_24_filled,
              borderRadius: borderRadius,
            ),
          ),
        );
      }
    }

    if (_radioStationsSearchResult.isNotEmpty) {
      widgets.add(
        SectionTitle(
          'Radio Stations',
          primaryColor,
          icon: FluentIcons.speaker_2_24_filled,
        ),
      );

      final stationsCount = _radioStationsSearchResult.length > maxSongsInList
          ? maxSongsInList
          : _radioStationsSearchResult.length;

      for (var index = 0; index < stationsCount; index++) {
        final station = _radioStationsSearchResult[index];
        final isLast = index == stationsCount - 1;

        widgets.add(
          Padding(
            padding: isLast ? commonListViewBottomPadding : EdgeInsets.zero,
            child: RadioStationCard(
              key: listItemKey('search_radio_station', index, station),
              station: station,
              onPressed: () async {
                final success = await audioHandler.playRadioStream(
                  id: station.id,
                  name: station.name,
                  streamUrl: station.streamUrl,
                  image: station.image,
                  genre: station.genre,
                );
                if (!success && context.mounted) {
                  showToast(context, 'Failed to play radio station');
                }
              },
            ),
          ),
        );
      }
    }

    return Column(
      key: ValueKey(
        'results-${_songsSearchResult.length}-${_artistsSearchResult.length}-${_albumsSearchResult.length}-${_playlistsSearchResult.length}',
      ),
      children: widgets,
    );
  }
}
