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
