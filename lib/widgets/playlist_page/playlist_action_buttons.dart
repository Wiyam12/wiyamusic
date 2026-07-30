import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wiyamusic/extensions/l10n.dart';

class PlaylistActionButtons extends StatelessWidget {
  const PlaylistActionButtons({
    super.key,
    required this.songs,
    required this.onPlay,
    required this.onShuffle,
  });

  final List<dynamic> songs;

  final VoidCallback onPlay;

  final AsyncCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(FluentIcons.play_24_regular),
              label: Text(context.l10n!.play),
              onPressed: onPlay,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.secondaryContainer,
                foregroundColor: colorScheme.onSecondaryContainer,
              ),
              icon: const Icon(FluentIcons.arrow_shuffle_24_regular),
              label: Text(context.l10n!.shuffle),
              onPressed: songs.isEmpty ? null : onShuffle,
            ),
          ),
        ],
      ),
    );
  }
}
