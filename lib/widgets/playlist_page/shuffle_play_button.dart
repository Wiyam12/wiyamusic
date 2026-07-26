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
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/models/playback_context.dart';

class ShufflePlayButton extends StatelessWidget {
  const ShufflePlayButton({
    super.key,
    required this.songs,
    this.playbackContext,
  });

  final List songs;
  final PlaybackContext? playbackContext;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      icon: const Icon(FluentIcons.arrow_shuffle_24_regular),
      iconSize: 24,
      tooltip: 'Shuffle play',
      onPressed: () async {
        if (songs.isEmpty) return;
        final shuffledSongs = List<Map>.from(songs.whereType<Map>());
        if (shuffledSongs.isEmpty) return;

        await audioHandler.addPlaylistToQueue(
          shuffledSongs..shuffle(),
          replace: true,
          startIndex: 0,
          context:
              playbackContext ??
              const PlaybackContext(kind: PlaybackSourceKind.other),
          enableShuffle: true,
        );
      },
    );
  }
}
