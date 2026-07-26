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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/services/playlists_manager.dart';
import 'package:wiyamusic/utilities/artwork_provider.dart';
import 'package:wiyamusic/utilities/flutter_toast.dart';
import 'package:wiyamusic/utilities/playlist_image_picker.dart';

/// Shows the create-playlist sheet.
///
/// [customOnly] hides the YouTube import mode, for flows that can only produce
/// a user-created playlist.
Future<Map<String, String>?> showCreatePlaylistDialog(
  BuildContext context, {
  dynamic songToAdd,
  List<dynamic>? songsToAdd,
  bool customOnly = false,
}) {
  final canImportFromYouTube =
      !customOnly && songToAdd == null && songsToAdd == null;
  var id = '';
  var customPlaylistName = '';
  var isYouTubeMode = canImportFromYouTube;
  String? imageUrl;
  String? imageBase64;

  return showModalBottomSheet<Map<String, String>?>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, dialogSetState) {
          final colorScheme = Theme.of(context).colorScheme;
          final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
          final bottomSafe = MediaQuery.paddingOf(context).bottom;

          Future<void> _pickImage() async {
            final result = await pickImage();
            if (result != null) {
              dialogSetState(() {
                imageBase64 = result;
                imageUrl = null;
              });
            }
          }

          Widget _imagePreview() {
            return buildImagePreview(
              imageBase64: imageBase64,
              imageUrl: imageUrl,
            );
          }

          Future<void> _submit() async {
            if (isYouTubeMode && id.isNotEmpty) {
              final result = await addUserPlaylist(id, context);
              if (context.mounted) showToast(context, result);
              if (!context.mounted) return;
              Navigator.pop(context, {'type': 'youtube', 'id': id});
            } else if (!isYouTubeMode && customPlaylistName.isNotEmpty) {
              final (result, newPlaylistId) = createCustomPlaylist(
                customPlaylistName.trim(),
                imageBase64 ?? imageUrl,
                context,
              );
              if (songToAdd != null) {
                if (context.mounted) {
                  final addResult = addSongInCustomPlaylist(
                    context,
                    newPlaylistId,
                    songToAdd,
                  );
                  showToast(context, addResult);
                }
              } else if (songsToAdd != null && songsToAdd.isNotEmpty) {
                if (context.mounted) {
                  final addResult = addSongsInCustomPlaylist(
                    context,
                    newPlaylistId,
                    songsToAdd,
                  );
                  showToast(context, addResult);
                }
              } else {
                if (context.mounted) showToast(context, result);
              }
              if (!context.mounted) return;
              Navigator.pop(context, {'type': 'custom', 'id': newPlaylistId});
            } else {
              showToast(context, '${context.l10n!.provideIdOrNameError}.');
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 0, 20, bottomSafe + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
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
                          FluentIcons.add_24_filled,
                          color: colorScheme.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          customOnly
                              ? context.l10n!.createNewPlaylist
                              : context.l10n!.addPlaylist,
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
                  if (canImportFromYouTube)
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.55,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                dialogSetState(() {
                                  isYouTubeMode = true;
                                  id = '';
                                  customPlaylistName = '';
                                  imageUrl = null;
                                  imageBase64 = null;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isYouTubeMode
                                      ? colorScheme.primaryContainer
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      FluentIcons.globe_20_filled,
                                      size: 20,
                                      color: isYouTubeMode
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'YouTube',
                                      style: TextStyle(
                                        color: isYouTubeMode
                                            ? colorScheme.onPrimaryContainer
                                            : colorScheme.onSurfaceVariant,
                                        fontWeight: isYouTubeMode
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                dialogSetState(() {
                                  isYouTubeMode = false;
                                  id = '';
                                  customPlaylistName = '';
                                  imageUrl = null;
                                  imageBase64 = null;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: !isYouTubeMode
                                      ? colorScheme.primaryContainer
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      FluentIcons.person_20_filled,
                                      size: 20,
                                      color: !isYouTubeMode
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      context.l10n!.custom,
                                      style: TextStyle(
                                        color: !isYouTubeMode
                                            ? colorScheme.onPrimaryContainer
                                            : colorScheme.onSurfaceVariant,
                                        fontWeight: !isYouTubeMode
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (canImportFromYouTube) const SizedBox(height: 20),
                  if (isYouTubeMode)
                    TextField(
                      decoration: InputDecoration(
                        labelText: context.l10n!.youtubePlaylistLinkOrId,
                        prefixIcon: Icon(
                          FluentIcons.link_20_regular,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: colorScheme.surface,
                      ),
                      onChanged: (value) {
                        id = value;
                      },
                    )
                  else ...[
                    TextField(
                      decoration: InputDecoration(
                        labelText: context.l10n!.customPlaylistName,
                        prefixIcon: Icon(
                          FluentIcons.text_field_20_regular,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: colorScheme.surface,
                      ),
                      autofocus: true,
                      onChanged: (value) {
                        customPlaylistName = value;
                      },
                    ),
                    if (imageBase64 == null) ...[
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          labelText: context.l10n!.customPlaylistImgUrl,
                          prefixIcon: Icon(
                            FluentIcons.image_20_regular,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: colorScheme.surface,
                        ),
                        onChanged: (value) {
                          imageUrl = value;
                          imageBase64 = null;
                          dialogSetState(() {});
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (imageUrl == null) ...[
                      buildImagePickerRow(
                        context,
                        _pickImage,
                        imageBase64 != null,
                      ),
                      _imagePreview(),
                    ],
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
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
                          onPressed: _submit,
                          icon: const Icon(FluentIcons.add_20_filled),
                          label: Text(context.l10n!.add),
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
    },
  );
}

/// Opens the playlist picker so the user can add [song] (or [songs]) to one of
/// their own playlists, creating a new one along the way if needed.
void showAddToPlaylistDialog(
  BuildContext context, {
  dynamic song,
  List<dynamic>? songs,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _AddToPlaylistSheet(song: song, songs: songs),
  );
}

/// A user-created playlist, plus the folder holding it when it is nested.
class _PlaylistTarget {
  const _PlaylistTarget(this.playlist, {this.folderName});

  final Map playlist;
  final String? folderName;

  String get id => playlist['ytid']?.toString() ?? '';
  String get title => playlist['title']?.toString() ?? '';
  String? get image => playlist['image']?.toString();
  List<dynamic> get songs => playlist['list'] as List<dynamic>? ?? const [];

  bool matches(String query) {
    if (query.isEmpty) return true;
    final lowered = query.toLowerCase();
    return title.toLowerCase().contains(lowered) ||
        (folderName?.toLowerCase().contains(lowered) ?? false);
  }
}

List<_PlaylistTarget> _collectUserPlaylistTargets() {
  return [
    for (final playlist in userCustomPlaylists.value)
      if (playlist['source'] == 'user-created') _PlaylistTarget(playlist),
    for (final folder in userPlaylistFolders.value)
      for (final playlist in (folder['playlists'] as List? ?? const []))
        if (playlist is Map && playlist['source'] == 'user-created')
          _PlaylistTarget(playlist, folderName: folder['name']?.toString()),
  ];
}

class _AddToPlaylistSheet extends StatefulWidget {
  const _AddToPlaylistSheet({this.song, this.songs});

  final dynamic song;
  final List<dynamic>? songs;

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  /// Shorter lists are easy to scan, so the search field stays hidden.
  static const _searchThreshold = 6;

  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<dynamic> get _selection {
    if (widget.song != null) return [widget.song];
    return widget.songs ?? const [];
  }

  bool _alreadyHasSelection(_PlaylistTarget target) {
    final selection = _selection.whereType<Map>().toList();
    if (selection.isEmpty) return false;

    final existingIds = target.songs
        .whereType<Map>()
        .map((song) => song['ytid']?.toString())
        .toSet();
    return selection.every(
      (song) => existingIds.contains(song['ytid']?.toString()),
    );
  }

  void _addToPlaylist(_PlaylistTarget target) {
    final String message;
    if (widget.song != null) {
      message = addSongInCustomPlaylist(context, target.id, widget.song as Map);
    } else if (widget.songs != null && widget.songs!.isNotEmpty) {
      message = addSongsInCustomPlaylist(context, target.id, widget.songs!);
    } else {
      message = context.l10n!.error;
    }

    // Toast before popping: it lives in the root overlay and outlives the sheet.
    showToast(context, message);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.8),
        child: ListenableBuilder(
          listenable: Listenable.merge([
            userCustomPlaylists,
            userPlaylistFolders,
          ]),
          builder: (context, _) {
            final targets = _collectUserPlaylistTargets();
            final visible = targets
                .where((target) => target.matches(_query))
                .toList();

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(colorScheme),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _CreatePlaylistTile(
                    onTap: () =>
                        showCreatePlaylistDialog(context, customOnly: true),
                  ),
                ),
                if (targets.length >= _searchThreshold)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) =>
                          setState(() => _query = value.trim()),
                      decoration: InputDecoration(
                        labelText: context.l10n!.searchPlaylists,
                        prefixIcon: Icon(
                          FluentIcons.search_20_regular,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: colorScheme.surface,
                        isDense: true,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Flexible(
                  child: visible.isEmpty
                      ? _buildEmptyState(colorScheme, targets.isEmpty)
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            0,
                            20,
                            media.padding.bottom + 20,
                          ),
                          shrinkWrap: true,
                          itemCount: visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final target = visible[index];
                            return _PlaylistTargetTile(
                              target: target,
                              isAlreadyAdded: _alreadyHasSelection(target),
                              onTap: () => _addToPlaylist(target),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              FluentIcons.album_add_24_filled,
              color: colorScheme.onSecondaryContainer,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10n!.addToPlaylist,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme, bool hasNoPlaylists) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Text(
        hasNoPlaylists
            ? context.l10n!.noCustomPlaylists
            : context.l10n!.noPlaylistsFound,
        textAlign: TextAlign.center,
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _CreatePlaylistTile extends StatelessWidget {
  const _CreatePlaylistTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.onPrimaryContainer.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  FluentIcons.add_24_filled,
                  color: colorScheme.onPrimaryContainer,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  context.l10n!.createNewPlaylist,
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistTargetTile extends StatelessWidget {
  const _PlaylistTargetTile({
    required this.target,
    required this.isAlreadyAdded,
    required this.onTap,
  });

  final _PlaylistTarget target;
  final bool isAlreadyAdded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final folderName = target.folderName;
    final subtitle = [
      '${target.songs.length} ${context.l10n!.songs.toLowerCase()}',
      if (folderName != null && folderName.isNotEmpty) folderName,
    ].join(' · ');

    return Material(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _PlaylistThumbnail(image: target.image),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      target.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isAlreadyAdded
                    ? FluentIcons.checkmark_circle_24_filled
                    : FluentIcons.add_circle_24_regular,
                color: isAlreadyAdded
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistThumbnail extends StatelessWidget {
  const _PlaylistThumbnail({required this.image});

  final String? image;

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final artwork = image;

    if (artwork == null || artwork.isEmpty) return _fallback(colorScheme);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image(
        image: ArtworkProvider.get(artwork),
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(colorScheme),
      ),
    );
  }

  Widget _fallback(ColorScheme colorScheme) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        FluentIcons.text_bullet_list_24_filled,
        size: 22,
        color: colorScheme.onSecondaryContainer,
      ),
    );
  }
}
