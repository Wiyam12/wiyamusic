import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:audio_service/audio_service.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/localization/app_localizations.dart';
import 'package:wiyamusic/screens/splash_screen.dart';
import 'package:wiyamusic/services/audio_service.dart';
import 'package:wiyamusic/services/common_services.dart';
import 'package:wiyamusic/services/data_manager.dart';
import 'package:wiyamusic/services/download_notification_service.dart';
import 'package:wiyamusic/services/io_service.dart';
import 'package:wiyamusic/services/listening_stats_service.dart';
import 'package:wiyamusic/services/logger_service.dart';
import 'package:wiyamusic/services/offline_download_coordinator.dart';
import 'package:wiyamusic/services/playlist_sharing.dart';
import 'package:wiyamusic/services/playlists_manager.dart';
import 'package:wiyamusic/services/router_service.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/services/update_manager.dart';
import 'package:wiyamusic/theme/app_themes.dart';
import 'package:wiyamusic/theme/design_tokens.dart';
import 'package:wiyamusic/utilities/flutter_toast.dart';
import 'package:wiyamusic/utilities/language_utils.dart';
import 'package:wiyamusic/utilities/playlist_utils.dart';
import 'package:wiyamusic/utilities/sharing_intent.dart';
import 'package:wiyamusic/widgets/windows_title_bar.dart';

late WiyaMusicAudioHandler audioHandler;
StreamSubscription<String?>? sharingIntentSubscription;

final logger = Logger();
final appLinks = AppLinks();

bool isFdroidBuild = false;
bool isUpdateChecked = false;

class WiyaMusic extends StatefulWidget {
  const WiyaMusic({super.key});

  static Future<void> updateAppState(
    BuildContext context, {
    ThemeMode? newThemeMode,
    Locale? newLocale,
    Color? newAccentColor,
    bool? useSystemColor,
  }) async {
    context.findAncestorStateOfType<_WiyaMusicState>()!.changeSettings(
      newThemeMode: newThemeMode,
      newLocale: newLocale,
      newAccentColor: newAccentColor,
      systemColorStatus: useSystemColor,
    );
  }

  @override
  _WiyaMusicState createState() => _WiyaMusicState();
}

class _WiyaMusicState extends State<WiyaMusic> with WidgetsBindingObserver {
  void changeSettings({
    ThemeMode? newThemeMode,
    Locale? newLocale,
    Color? newAccentColor,
    bool? systemColorStatus,
  }) {
    setState(() {
      if (newThemeMode != null) {
        themeMode = newThemeMode;
        brightness = getBrightnessFromThemeMode(newThemeMode);
      }
      if (newLocale != null) {
        languageSetting = newLocale;
      }
      if (newAccentColor != null) {
        if (systemColorStatus != null &&
            useSystemColor.value != systemColorStatus) {
          useSystemColor.value = systemColorStatus;
          addOrUpdateData<bool>(
            'settings',
            'useSystemColor',
            systemColorStatus,
          );
        }
        primaryColorSetting = newAccentColor;
      }
    });
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    final platformDispatcher = PlatformDispatcher.instance;

    // This callback is called every time the brightness changes.
    platformDispatcher.onPlatformBrightnessChanged = () {
      if (themeMode == ThemeMode.system) {
        setState(() {
          brightness = platformDispatcher.platformBrightness;
        });
      }
    };

    offlineMode.addListener(_onOfflineModeChanged);

    // Mobile-only: receive_sharing_intent has no Windows/desktop implementation.
    if (Platform.isAndroid || Platform.isIOS) {
      sharingIntentSubscription = ReceiveSharingIntent.getTextStream().listen(
        (String? value) async {
          await consumeYoutubeSharedTextIntent(
            value,
            audioHandler: audioHandler,
            onError: (error, stackTrace) {
              logger.log(
                'Error while playing shared song:',
                error: error,
                stackTrace: stackTrace,
              );
            },
          );
        },
        onError: (err) {
          logger.log('getTextStream error:', error: err);
        },
      );
    }

    try {
      LicenseRegistry.addLicense(() async* {
        final license = await rootBundle.loadString(
          'assets/licenses/paytone.txt',
        );
        yield LicenseEntryWithLineBreaks(['paytoneOne'], license);
      });
    } catch (e, stackTrace) {
      logger.log(
        'License Registration Error',
        error: e,
        stackTrace: stackTrace,
      );
    }

    if (!isFdroidBuild && Platform.isAndroid) {
      // Auto-check when online (skipped versions respect "don't display again").
      if (!isUpdateChecked && shouldWeCheckUpdates.value != false) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!offlineMode.value) {
            unawaited(checkAppUpdates());
          }
          isUpdateChecked = true;
        });
      } else if (shouldWeCheckUpdates.value == false) {
        SchedulerBinding.instance.addPostFrameCallback((_) async {
          if (!offlineMode.value) {
            await fetchAnnouncementOnly();
          }
        });
      }
    } else if (!offlineMode.value) {
      SchedulerBinding.instance.addPostFrameCallback((_) async {
        await fetchAnnouncementOnly();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Persist listening stats when the app leaves the foreground. This is the
    // reliable moment to snapshot and flush: unlike widget dispose, these
    // callbacks are delivered before the OS suspends or terminates the process.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      listeningStatsService.recordListeningSessionProgress(
        wasPlaying: audioHandler.audioPlayer.playing,
      );
      unawaited(listeningStatsService.flush());
    }

    // On iOS, pause the download queue when truly backgrounded so we do not
    // thrash CPU while suspended. Resume safely when returning to foreground
    // without starting duplicate sessions (locks + slots already prevent that).
    if (Platform.isIOS) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.detached) {
        offlineDownloadCoordinator.pause();
      } else if (state == AppLifecycleState.resumed) {
        offlineDownloadCoordinator.resume();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    offlineMode.removeListener(_onOfflineModeChanged);

    Hive.close();
    unawaited(sharingIntentSubscription?.cancel());
    super.dispose();
  }

  void _onOfflineModeChanged() {
    // Force rebuild when offline mode changes
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightColorScheme, darkColorScheme) {
        final colorScheme = getAppColorScheme(
          lightColorScheme,
          darkColorScheme,
        );

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarContrastEnforced: true,
            // iOS: brightness of the *background* under the status bar.
            // Dark background → white time/battery icons.
            statusBarBrightness:
                brightness == Brightness.dark
                    ? Brightness.dark
                    : Brightness.light,
            // Android: brightness of the icons themselves.
            statusBarIconBrightness:
                brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
            systemNavigationBarIconBrightness:
                brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
          ),
          child: MaterialApp.router(
            themeMode: themeMode,
            darkTheme: getAppTheme(colorScheme),
            theme: getAppTheme(colorScheme),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            debugShowCheckedModeBanner: false,
            supportedLocales: appSupportedLocales,
            locale: languageSetting,
            routerConfig: NavigationManager.router,
            builder: (context, child) {
              return WindowsDesktopShell(
                child: child ?? const SizedBox.shrink(),
              );
            },
          ),
        );
      },
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(900, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'WiyaMusic',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const AppBootstrap());
}

/// Shows the branded splash while Hive / audio / router finish booting.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  static const _minimumSplash = Duration(milliseconds: 1600);

  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final started = DateTime.now();
    await initialisation();

    final elapsed = DateTime.now().difference(started);
    if (elapsed < _minimumSplash) {
      await Future<void>.delayed(_minimumSplash - elapsed);
    }

    if (mounted) {
      setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 480),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child:
          _ready
              ? const WiyaMusic(key: ValueKey('wiyamusic-app'))
              : MaterialApp(
                key: const ValueKey('wiyamusic-splash'),
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  brightness: Brightness.dark,
                  colorScheme: WiyaDesign.darkColorScheme,
                  scaffoldBackgroundColor: WiyaDesign.background,
                  useMaterial3: true,
                ),
                builder: (context, child) {
                  return WindowsDesktopShell(
                    child: child ?? const SizedBox.shrink(),
                  );
                },
                home: const SplashScreen(),
              ),
    );
  }
}

Future<void> initialisation() async {
  try {
    // just_audio has no built-in Windows/Linux implementation; register media_kit.
    if (Platform.isWindows || Platform.isLinux) {
      JustAudioMediaKit.title = 'WiyaMusic';
      JustAudioMediaKit.ensureInitialized(
        windows: Platform.isWindows,
        linux: Platform.isLinux,
      );
    }

    await Hive.initFlutter();

    await Future.wait([
      Hive.openBox('settings'),
      Hive.openBox('user'),
      Hive.openBox('userNoBackup'),
      Hive.openBox('cache'),
    ]);

    audioHandler = await AudioService.init(
      builder: WiyaMusicAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.wiyamusic.app',
        androidNotificationChannelName: 'WiyaMusic',
        androidNotificationIcon: 'drawable/ic_notification',
        androidShowNotificationBadge: true,
        // Leave foreground on pause so the notification can be swiped away,
        // and so stop()/X can actually cancel it on modern Android.
      ),
    );

    // Download progress notifications (playlist / song offline downloads).
    await downloadNotificationService.init();

    // Init router
    NavigationManager.instance;

    try {
      // Listen to incoming links while app is running
      appLinks.uriLinkStream.listen(
        handleIncomingLink,
        onError: (err) {
          logger.log('URI link error:', error: err);
        },
      );
    } on PlatformException {
      logger.log('Failed to get initial uri');
    }

    if (isFdroidBuild && !offlineMode.value) {
      await fetchAnnouncementOnly();
    }
  } catch (e, stackTrace) {
    logger.log('Initialization Error', error: e, stackTrace: stackTrace);
  }

  applicationDirPath = (await getApplicationDocumentsDirectory()).path;
  await FilePaths.ensureDirectoriesExist();
  // Fix stale absolute offline paths after iOS container UUID changes.
  await repairOfflineSongPaths();

  // TODO: Remove after a few versions, this is just for legacy support
  unawaited(listeningStatsService.purgeLegacyRadioStreamStats());
}

void handleIncomingLink(Uri? uri) async {
  if (uri == null || uri.scheme != 'wiyamusic' || uri.host != 'playlist')
    return;

  if (uri.pathSegments.length < 2 || uri.pathSegments[0] != 'custom') return;

  try {
    final encodedPlaylist = uri.pathSegments[1];
    final playlist = await PlaylistSharingService.decodeAndExpandPlaylist(
      encodedPlaylist,
    );

    if (playlist == null) {
      _showPlaylistError();
      return;
    }

    // Ensure the incoming playlist has a unique id so it can be removed later
    if (playlist['ytid'] == null || playlist['ytid'].toString().isEmpty) {
      playlist['ytid'] = PlaylistUtils.generateCustomPlaylistId();
    }

    // Check for duplicate by title and song ytids
    final incomingYtids =
        (playlist['list'] as List<dynamic>)
            .map((s) => s['ytid'].toString())
            .toList();

    final isDuplicate = PlaylistUtils.playlistExists(
      playlist,
      incomingYtids,
      userCustomPlaylists.value,
    );

    if (isDuplicate) {
      showToast(
        NavigationManager().context,
        NavigationManager().context.l10n!.playlistAlreadyExists,
      );
    } else {
      userCustomPlaylists.value = [...userCustomPlaylists.value, playlist];
      unawaited(
        addOrUpdateData<List>(
          'user',
          'customPlaylists',
          userCustomPlaylists.value,
        ),
      );
      showToast(
        NavigationManager().context,
        '${NavigationManager().context.l10n!.addedSuccess}!',
      );
    }
  } catch (e) {
    _showPlaylistError();
  }
}

void _showPlaylistError() {
  showToast(
    NavigationManager().context,
    NavigationManager().context.l10n!.failedToLoadPlaylist,
  );
}
