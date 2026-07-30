import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/widgets/now_playing/bottom_actions_row.dart';
import 'package:wiyamusic/widgets/now_playing/now_playing_artwork.dart';
import 'package:wiyamusic/widgets/now_playing/now_playing_controls.dart';
import 'package:wiyamusic/widgets/overflow_menu_button.dart';
import 'package:wiyamusic/widgets/queue_list_view.dart';

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  final _lyricsController = NowPlayingLyricsController();

  @override
  void dispose() {
    _lyricsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isLargeScreen = size.width > 800 && size.height > 600;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = size.width;
    final baseIconSize = isLargeScreen
        ? 52.0
        : screenWidth < 360
        ? 28.0
        : screenWidth < 400
        ? 32.0
        : 36.0;
    final miniIconSize = isLargeScreen
        ? 34.0
        : screenWidth < 360
        ? 22.0
        : 24.0;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: StreamBuilder<MediaItem?>(
          stream: audioHandler.mediaItem,
          builder: (context, snapshot) {
            if (snapshot.data == null || !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final metadata = snapshot.data!;
            return Column(
              children: [
                _buildAppBar(context, colorScheme, metadata),
                Expanded(
                  child: isLargeScreen
                      ? _DesktopLayout(
                          metadata: metadata,
                          size: size,
                          adjustedIconSize: baseIconSize,
                          adjustedMiniIconSize: miniIconSize,
                          lyricsController: _lyricsController,
                        )
                      : _MobileLayout(
                          metadata: metadata,
                          size: size,
                          adjustedIconSize: baseIconSize,
                          adjustedMiniIconSize: miniIconSize,
                          isLargeScreen: isLargeScreen,
                          lyricsController: _lyricsController,
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    ColorScheme colorScheme,
    MediaItem metadata,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              'Now Playing',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    FluentIcons.chevron_down_24_regular,
                    color: colorScheme.onSurface,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
                OverflowMenuButton<String>(
                  color: colorScheme.onSurface,
                  onSelected: (value) => handleNowPlayingMoreAction(
                    context: context,
                    value: value,
                    metadata: metadata,
                    lyricsController: _lyricsController,
                  ),
                  itemBuilder: (context) => buildNowPlayingMoreMenuItems(
                    context: context,
                    metadata: metadata,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.metadata,
    required this.size,
    required this.adjustedIconSize,
    required this.adjustedMiniIconSize,
    required this.lyricsController,
  });
  final MediaItem metadata;
  final Size size;
  final double adjustedIconSize;
  final double adjustedMiniIconSize;
  final NowPlayingLyricsController lyricsController;

  static const double _queueMinWidth = 280;
  static const double _queueMaxWidth = 420;
  static const Duration _queueSlideDuration = Duration(milliseconds: 320);

  @override
  Widget build(BuildContext context) {
    final queueWidth = (size.width * 0.38).clamp(
      _queueMinWidth,
      _queueMaxWidth,
    );

    return ValueListenableBuilder<bool>(
      valueListenable: nowPlayingQueueVisible,
      builder: (context, queueVisible, _) {
        return Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    flex: 2,
                    child: NowPlayingArtwork(
                      size: size,
                      metadata: metadata,
                      lyricsController: lyricsController,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Column(
                        children: [
                          if (!(metadata.extras?['isLive'] ?? false))
                            Expanded(
                              child: NowPlayingControls(
                                size: size,
                                audioId: metadata.extras?['ytid'],
                                adjustedIconSize: adjustedIconSize,
                                adjustedMiniIconSize: adjustedMiniIconSize,
                                metadata: metadata,
                              ),
                            ),
                          BottomActionsRow(
                            metadata: metadata,
                            iconSize: 26,
                            isLargeScreen: true,
                            lyricsController: lyricsController,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ClipRect(
              child: AnimatedAlign(
                duration: _queueSlideDuration,
                curve: Curves.easeInOutCubic,
                alignment: Alignment.centerLeft,
                widthFactor: queueVisible ? 1 : 0,
                heightFactor: 1,
                child: SizedBox(width: queueWidth, child: const QueueWidget()),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({
    required this.metadata,
    required this.size,
    required this.adjustedIconSize,
    required this.adjustedMiniIconSize,
    required this.isLargeScreen,
    required this.lyricsController,
  });
  final MediaItem metadata;
  final Size size;
  final double adjustedIconSize;
  final double adjustedMiniIconSize;
  final bool isLargeScreen;
  final NowPlayingLyricsController lyricsController;

  @override
  Widget build(BuildContext context) {
    final isLandscape = size.width > size.height;

    if (isLandscape) {
      return _buildLandscapeLayout(context);
    }
    return _buildPortraitLayout(context);
  }

  Widget _buildPortraitLayout(BuildContext context) {
    final isLive = metadata.extras?['isLive'] ?? false;

    return Column(
      children: [
        Expanded(
          flex: 11,
          child: NowPlayingArtwork(
            size: size,
            metadata: metadata,
            lyricsController: lyricsController,
          ),
        ),
        Expanded(
          flex: 9,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                if (!isLive)
                  Expanded(
                    child: NowPlayingControls(
                      size: size,
                      audioId: metadata.extras?['ytid'],
                      adjustedIconSize: adjustedIconSize,
                      adjustedMiniIconSize: adjustedMiniIconSize,
                      metadata: metadata,
                    ),
                  ),
                BottomActionsRow(
                  metadata: metadata,
                  iconSize: adjustedMiniIconSize,
                  isLargeScreen: isLargeScreen,
                  lyricsController: lyricsController,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(BuildContext context) {
    final isLive = metadata.extras?['isLive'] ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Center(
              child: NowPlayingArtwork(
                size: size,
                metadata: metadata,
                lyricsController: lyricsController,
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!isLive)
                  Expanded(
                    child: NowPlayingControls(
                      size: size,
                      audioId: metadata.extras?['ytid'],
                      adjustedIconSize: adjustedIconSize,
                      adjustedMiniIconSize: adjustedMiniIconSize,
                      metadata: metadata,
                    ),
                  ),
                BottomActionsRow(
                  metadata: metadata,
                  iconSize: adjustedMiniIconSize,
                  isLargeScreen: isLargeScreen,
                  lyricsController: lyricsController,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
