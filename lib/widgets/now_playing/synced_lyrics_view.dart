import 'package:flutter/material.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/models/position_data.dart';
import 'package:wiyamusic/models/song_lyrics.dart';

/// Karaoke-style lyrics: highlights the active line (and words when timed).
class SyncedLyricsView extends StatefulWidget {
  const SyncedLyricsView({
    super.key,
    required this.lyrics,
    this.onToggleArtwork,
  });

  final SongLyrics lyrics;
  final VoidCallback? onToggleArtwork;

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> {
  final _scrollController = ScrollController();
  final _lineKeys = <int, GlobalKey>{};
  int _lastScrolledLine = -2;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int _lineIndexFor(Duration position, List<LyricLine> lines) {
    if (lines.isEmpty) return -1;
    if (position < lines.first.start) return -1;
    var index = 0;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].start <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  int _wordIndexFor(Duration position, LyricLine line) {
    if (!line.hasWordTimings) return -1;
    var index = 0;
    for (var i = 0; i < line.words.length; i++) {
      if (line.words[i].start <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  void _scrollToActive(int index) {
    final key = _lineKeys[index];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.4,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lines = widget.lyrics.syncedLines;

    if (!widget.lyrics.hasSynced) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggleArtwork,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          physics: const BouncingScrollPhysics(),
          child: Text(
            widget.lyrics.displayPlain,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return StreamBuilder<PositionData>(
      stream: audioHandler.positionDataStream,
      builder: (context, snapshot) {
        final position = snapshot.data?.position ?? Duration.zero;
        final activeLineIndex = _lineIndexFor(position, lines);
        final activeWordIndex = activeLineIndex >= 0
            ? _wordIndexFor(position, lines[activeLineIndex])
            : -1;

        if (activeLineIndex != _lastScrolledLine) {
          final lineToScroll = activeLineIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (lineToScroll == _lastScrolledLine) return;
            _lastScrolledLine = lineToScroll;
            if (lineToScroll >= 0) _scrollToActive(lineToScroll);
          });
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggleArtwork,
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
            physics: const BouncingScrollPhysics(),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final line = lines[index];
              final isActive = index == activeLineIndex;
              final isPast = index < activeLineIndex;
              _lineKeys.putIfAbsent(index, GlobalKey.new);

              return KeyedSubtree(
                key: _lineKeys[index],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    style: TextStyle(
                      fontSize: isActive ? 22 : 17,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      height: 1.45,
                      color: isActive
                          ? colorScheme.primary
                          : isPast
                          ? colorScheme.onSurface.withValues(alpha: 0.45)
                          : colorScheme.onSurface.withValues(alpha: 0.72),
                    ),
                    child: isActive && line.hasWordTimings
                        ? _WordTimedLine(
                            line: line,
                            activeWordIndex: activeWordIndex,
                            activeColor: colorScheme.primary,
                            inactiveColor: colorScheme.onSurface.withValues(
                              alpha: 0.35,
                            ),
                          )
                        : Text(line.text, textAlign: TextAlign.center),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _WordTimedLine extends StatelessWidget {
  const _WordTimedLine({
    required this.line,
    required this.activeWordIndex,
    required this.activeColor,
    required this.inactiveColor,
  });

  final LyricLine line;
  final int activeWordIndex;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < line.words.length; i++) ...[
            TextSpan(
              text: line.words[i].text,
              style: TextStyle(
                color: i <= activeWordIndex ? activeColor : inactiveColor,
                fontWeight: i == activeWordIndex
                    ? FontWeight.w800
                    : FontWeight.w600,
              ),
            ),
            if (i < line.words.length - 1) const TextSpan(text: ' '),
          ],
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
