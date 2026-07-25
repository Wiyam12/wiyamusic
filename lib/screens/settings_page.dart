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

import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wiyamusic/constants/app_constants.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/screens/search_page.dart';
import 'package:wiyamusic/services/common_services.dart';
import 'package:wiyamusic/services/data_manager.dart';
import 'package:wiyamusic/services/listening_stats_service.dart';
import 'package:wiyamusic/services/playlist_download_service.dart';
import 'package:wiyamusic/services/playlists_manager.dart';
import 'package:wiyamusic/services/router_service.dart';
import 'package:wiyamusic/services/settings_manager.dart';
// Unused while manual/auto app-update settings are hidden from end users.
// import 'package:wiyamusic/services/update_manager.dart';
// Unused while the accent color picker is hidden from end users.
// import 'package:wiyamusic/theme/app_colors.dart';
import 'package:wiyamusic/theme/app_themes.dart';
import 'package:wiyamusic/utilities/flutter_bottom_sheet.dart';
import 'package:wiyamusic/utilities/flutter_toast.dart';
import 'package:wiyamusic/utilities/language_utils.dart';
// Unused while the "Translate" (Crowdin) link is hidden from end users.
// import 'package:wiyamusic/utilities/url_launcher.dart';
import 'package:wiyamusic/widgets/bottom_sheet_bar.dart';
import 'package:wiyamusic/widgets/confirmation_dialog.dart';
import 'package:wiyamusic/widgets/custom_bar.dart';
import 'package:wiyamusic/widgets/mini_player_bottom_space.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(title: Text(context.l10n!.settings)),
      body: SingleChildScrollView(
        padding: commonSingleChildScrollViewPadding,
        child: Column(
          children: <Widget>[
            _buildPreferencesSection(context),
            if (!offlineMode.value) _buildOnlineFeaturesSection(context),
            _buildToolsSection(context),
            _buildOthersSection(context),
            const SizedBox(height: 20),
            const MiniPlayerBottomSpace(),
          ],
        ),
      ),
    );
  }

  Widget _settingsSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildPreferencesSection(BuildContext context) {
    final showPureBlack = themeMode == ThemeMode.dark;

    return Column(
      children: [
        _settingsSectionTitle(context, context.l10n!.preferences),
        CustomBar(
          context.l10n!.themeMode,
          FluentIcons.weather_sunny_28_regular,
          borderRadius: commonCustomBarRadiusFirst,
          onTap: () => _showThemeModePicker(context),
        ),
        CustomBar(
          context.l10n!.language,
          FluentIcons.translate_24_regular,
          showDivider: true,
          onTap: () => _showLanguagePicker(context),
        ),
        CustomBar(
          context.l10n!.audioQuality,
          FluentIcons.music_note_1_24_regular,
          showDivider: true,
          onTap: () => _showAudioQualityPicker(context),
        ),
        if (audioHandler.isEqualizerSupported)
          CustomBar(
            context.l10n!.equalizer,
            FluentIcons.data_histogram_24_regular,
            showDivider: true,
            onTap: () => context.push('/settings/equalizer'),
          ),
        // CustomBar(
        //   context.l10n!.dynamicColor,
        //   FluentIcons.toggle_left_24_regular,
        //   showDivider: true,
        //   trailing: _SettingsSwitch(
        //     value: useSystemColor.value,
        //     onChanged: (value) => _toggleSystemColor(context, value),
        //   ),
        // ),
        if (showPureBlack)
          CustomBar(
            context.l10n!.pureBlackTheme,
            FluentIcons.color_background_24_regular,
            showDivider: true,
            trailing: _SettingsSwitch(
              value: usePureBlackColor.value,
              onChanged: (value) => _togglePureBlack(context, value),
            ),
          ),
        // Hidden from most end users (power-user / niche settings):
        // - Predictive back (Android gesture polish)
        // - Use proxy (network troubleshooting)
        /*
        if (Platform.isAndroid)
          ValueListenableBuilder<bool>(
            valueListenable: predictiveBack,
            builder: (_, value, __) {
              return CustomBar(
                context.l10n!.predictiveBack,
                FluentIcons.position_backward_24_regular,
                trailing: Switch(
                  value: value,
                  onChanged: (value) => _togglePredictiveBack(context, value),
                ),
              );
            },
          ),
        ValueListenableBuilder<bool>(
          valueListenable: useProxy,
          builder: (_, value, __) {
            return CustomBar(
              context.l10n!.useProxy,
              FluentIcons.shield_24_regular,
              description: context.l10n!.useProxyDescription,
              trailing: Switch(
                value: value,
                onChanged: (value) {
                  useProxy.value = value;
                  addOrUpdateData<bool>('settings', 'useProxy', value);
                  showToast(context, context.l10n!.settingChangedMsg);
                },
              ),
            );
          },
        ),
        */
        // ValueListenableBuilder<bool>(
        //   valueListenable: wrappedEnabled,
        //   builder: (_, value, __) {
        //     return CustomBar(
        //       context.l10n!.listeningStats,
        //       FluentIcons.clock_24_regular,
        //       description: context.l10n!.listeningStatsDescription,
        //       trailing: Switch(
        //         value: value,
        //         onChanged: (value) => _toggleWrapped(context, value),
        //       ),
        //     );
        //   },
        // ),
        // ValueListenableBuilder<bool>(
        //   valueListenable: offlineMode,
        //   builder: (_, value, __) {
        //     return CustomBar(
        //       context.l10n!.offlineMode,
        //       FluentIcons.cloud_off_24_regular,
        //       showDivider: true,
        //       borderRadius: commonCustomBarRadiusLast,
        //       trailing: _SettingsSwitch(
        //         value: value,
        //         onChanged: (value) => _toggleOfflineMode(context, value),
        //       ),
        //     );
        //   },
        // ),
        // Automatic update checks hidden from most end users (niche, Android
        // non-F-Droid only).
        /*
        if (!isFdroidBuild && Platform.isAndroid)
          ValueListenableBuilder<bool?>(
            valueListenable: shouldWeCheckUpdates,
            builder: (_, value, __) {
              return CustomBar(
                context.l10n!.automaticUpdateChecks,
                FluentIcons.arrow_sync_24_regular,
                description: context.l10n!.automaticUpdateChecksDescription,
                borderRadius: offlineMode.value
                    ? commonCustomBarRadiusLast
                    : BorderRadius.zero,
                trailing: Switch(
                  value: value ?? false,
                  onChanged: (value) =>
                      _toggleAutomaticUpdateChecks(context, value),
                ),
              );
            },
          ),
        */
      ],
    );
  }

  Widget _buildOnlineFeaturesSection(BuildContext context) {
    return Column(
      children: [
        // Hidden from most end users (niche / privacy-adjacent):
        // - SponsorBlock (skips sponsor segments; advanced)
        // - External recommendations (sends data to external services)
        /*
        ValueListenableBuilder<bool>(
          valueListenable: sponsorBlockSupport,
          builder: (_, value, __) {
            return CustomBar(
              'SponsorBlock',
              FluentIcons.cut_24_regular,
              description: context.l10n!.sponsorBlockDescription,
              trailing: Switch(
                value: value,
                onChanged: (value) => _toggleSponsorBlock(context, value),
              ),
            );
          },
        ),
        */
        const SizedBox(height: 12),
        ValueListenableBuilder<bool>(
          valueListenable: playNextSongAutomatically,
          builder: (_, value, __) {
            return CustomBar(
              context.l10n!.automaticSongPicker,
              FluentIcons.music_note_2_play_20_regular,
              borderRadius: commonCustomBarRadius,
              trailing: _SettingsSwitch(
                value: value,
                onChanged: (value) {
                  _toggleAutoPlayNext(context, value);
                  showToast(context, context.l10n!.settingChangedMsg);
                },
              ),
            );
          },
        ),

        /*
        ValueListenableBuilder<bool>(
          valueListenable: externalRecommendations,
          builder: (_, value, __) {
            return CustomBar(
              context.l10n!.externalRecommendations,
              FluentIcons.channel_share_24_regular,
              description: context.l10n!.externalRecommendationsDescription,
              borderRadius: commonCustomBarRadiusLast,
              trailing: Switch(
                value: value,
                onChanged: (value) =>
                    _toggleExternalRecommendations(context, value),
              ),
            );
          },
        ),
        */
      ],
    );
  }

  Widget _buildToolsSection(BuildContext context) {
    return Column(
      children: [
        _settingsSectionTitle(context, context.l10n!.tools),
        CustomBar(
          context.l10n!.clearCache,
          FluentIcons.broom_24_regular,
          borderRadius: commonCustomBarRadiusFirst,
          onTap: () async {
            final cleared = await clearCache();
            showToast(
              context,
              cleared ? '${context.l10n!.cacheMsg}!' : context.l10n!.error,
            );
          },
        ),
        CustomBar(
          context.l10n!.clearSearchHistory,
          FluentIcons.history_24_regular,
          showDivider: true,
          onTap: () => _showConfirmationDialog(
            context: context,
            confirmationMessage: context.l10n!.clearSearchHistoryQuestion,
            onSubmit: () {
              searchHistoryNotifier.value = [];
              deleteData('user', 'searchHistory');
              showToast(context, '${context.l10n!.searchHistoryMsg}!');
            },
          ),
        ),
        CustomBar(
          context.l10n!.clearRecentlyPlayed,
          FluentIcons.receipt_play_24_regular,
          showDivider: true,
          onTap: () => _showConfirmationDialog(
            context: context,
            confirmationMessage: context.l10n!.clearRecentlyPlayedQuestion,
            onSubmit: () {
              userRecentlyPlayed.value = [];
              deleteData('user', 'recentlyPlayedSongs');
              showToast(context, '${context.l10n!.recentlyPlayedMsg}!');
            },
          ),
        ),
        // CustomBar(
        //   context.l10n!.clearListeningStats,
        //   FluentIcons.clock_24_regular,
        //   onTap: () => _showConfirmationDialog(
        //     context: context,
        //     confirmationMessage: context.l10n!.clearListeningStatsQuestion,
        //     submitMessage: context.l10n!.delete,
        //     isDangerous: true,
        //     onSubmit: () async {
        //       audioHandler.resetListeningStatsSession(flushStats: false);
        //       await listeningStatsService.clearStats();
        //       audioHandler.startListeningStatsSessionIfNeeded();
        //       if (context.mounted) {
        //         showToast(context, '${context.l10n!.listeningStatsCleared}!');
        //       }
        //     },
        //   ),
        // ),
        CustomBar(
          context.l10n!.deleteDownloads,
          FluentIcons.delete_24_regular,
          showDivider: true,
          onTap: () => _showConfirmationDialog(
            context: context,
            confirmationMessage: context.l10n!.deleteDownloadsQuestion,
            submitMessage: context.l10n!.delete,
            isDangerous: true,
            onSubmit: () async {
              try {
                await offlinePlaylistService.deleteAllDownloads();
                if (context.mounted) {
                  showToast(context, context.l10n!.downloadsDeleted);
                }
              } catch (e) {
                if (context.mounted) {
                  showToast(context, context.l10n!.error);
                }
              }
            },
          ),
        ),
        CustomBar(
          context.l10n!.backupUserData,
          FluentIcons.cloud_sync_24_regular,
          showDivider: true,
          onTap: () => _backupUserData(context),
        ),
        CustomBar(
          context.l10n!.restoreUserData,
          FluentIcons.cloud_add_24_regular,
          showDivider: true,
          borderRadius: commonCustomBarRadiusLast,
          onTap: () async {
            try {
              final result = await restoreData(context);
              if (result.success) {
                reloadSongLibraryStateFromStorage();
                reloadPlaylistLibraryStateFromStorage();
                reloadSearchHistoryFromStorage();
                // The restored settings box may carry a different
                // wrappedEnabled value than the one already loaded into this
                // ValueNotifier; without resyncing it here, recording silently
                // keeps following the pre-restore value until the next cold
                // start, when it would suddenly flip without explanation.
                wrappedEnabled.value =
                    await getData(
                          'settings',
                          'wrappedEnabled',
                          defaultValue: true,
                        )
                        as bool;
                listeningStatsService.reload();
              }
              if (context.mounted) {
                showToast(
                  context,
                  result.message,
                  icon: result.success
                      ? null
                      : FluentIcons.error_circle_24_regular,
                );
              }
            } catch (e, str) {
              logger.log('Error restoring data', error: e, stackTrace: str);
              if (context.mounted) {
                showToast(
                  context,
                  context.l10n!.error,
                  icon: FluentIcons.error_circle_24_regular,
                );
              }
            }
          },
        ),
        // Manual "Download app update" hidden from most end users.
        /*
        if (!isFdroidBuild && Platform.isAndroid)
          CustomBar(
            context.l10n!.downloadAppUpdate,
            FluentIcons.arrow_download_24_regular,
            borderRadius: commonCustomBarRadiusLast,
            onTap: checkAppUpdates,
          ),
        */
      ],
    );
  }

  Widget _buildOthersSection(BuildContext context) {
    return Column(
      children: [
        _settingsSectionTitle(context, context.l10n!.others),
        // CustomBar(
        //   context.l10n!.licenses,
        //   FluentIcons.document_24_regular,
        //   borderRadius: commonCustomBarRadiusFirst,
        //   onTap: () => NavigationManager.router.go('/settings/license'),
        // ),
        // Hidden from most end users (contributor / debugging tools):
        // - Translate (Crowdin contributor link)
        // - Copy logs (debugging)
        /*
        CustomBar(
          context.l10n!.translate,
          FluentIcons.translate_24_regular,
          description: context.l10n!.translateDescription,
          onTap: () =>
              launchURL(Uri.parse('https://crowdin.com/project/wiyamusic')),
        ),
        CustomBar(
          '${context.l10n!.copyLogs} (${logger.getLogCount()})',
          FluentIcons.error_circle_24_regular,
          onTap: () async => showToast(context, await logger.copyLogs(context)),
        ),
        */
        CustomBar(
          context.l10n!.about,
          FluentIcons.book_information_24_regular,
          borderRadius: commonCustomBarRadius,
          onTap: () => NavigationManager.router.go('/settings/about'),
        ),
      ],
    );
  }

  /*
  void _showAccentColorPicker(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    showCustomBottomSheet(
      context,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          itemCount: availableColors.length,
          itemBuilder: (context, index) {
            final color = availableColors[index];
            final isSelected = color == primaryColorSetting;

            return GestureDetector(
              onTap: () {
                addOrUpdateData<int>(
                  'settings',
                  'accentColor',
                  color.toARGB32(),
                );
                WiyaMusic.updateAppState(
                  context,
                  newAccentColor: color,
                  useSystemColor: false,
                );
                showToast(context, context.l10n!.accentChangeMsg);
                Navigator.pop(context);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: colorScheme.onSurface, width: 3)
                      : null,
                ),
                child: isSelected
                    ? Icon(
                        FluentIcons.checkmark_20_filled,
                        color: color.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white,
                        size: 24,
                      )
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }
  */

  void _showThemeModePicker(BuildContext context) {
    final availableModes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    const modeIcons = [
      FluentIcons.phone_24_regular,
      FluentIcons.weather_sunny_24_regular,
      FluentIcons.weather_moon_24_regular,
    ];

    showCustomBottomSheet(
      context,
      ListView.builder(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        padding: commonListViewBottomPadding,
        itemCount: availableModes.length,
        itemBuilder: (context, index) {
          final mode = availableModes[index];
          final modeNames = [
            context.l10n!.themeModeSystem,
            context.l10n!.themeModeLight,
            context.l10n!.themeModeDark,
          ];

          return BottomSheetBar(
            modeNames[mode.index],
            () {
              addOrUpdateData<int>('settings', 'themeIndex', mode.index);
              WiyaMusic.updateAppState(context, newThemeMode: mode);
              Navigator.pop(context);
            },
            themeMode == mode,
            icon: modeIcons[mode.index],
          );
        },
      ),
    );
  }

  void _showLanguagePicker(BuildContext context) {
    final availableLanguages = appLanguages.toList();
    final activeLanguageCode = Localizations.localeOf(context).languageCode;
    final activeScriptCode = Localizations.localeOf(context).scriptCode;
    final activeLanguageFullCode = activeScriptCode != null
        ? '$activeLanguageCode-$activeScriptCode'
        : activeLanguageCode;

    showCustomBottomSheet(
      context,
      ListView.builder(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        padding: commonListViewBottomPadding,
        itemCount: availableLanguages.length,
        itemBuilder: (context, index) {
          final language = availableLanguages[index];
          final newLocale = getLocaleFromLanguageCode(language);
          final newLocaleFullCode = newLocale.scriptCode != null
              ? '${newLocale.languageCode}-${newLocale.scriptCode}'
              : newLocale.languageCode;

          return BottomSheetBar(
            getLanguageDisplayName(context, language),
            () {
              addOrUpdateData<String>(
                'settings',
                'languageCode',
                newLocaleFullCode,
              );
              WiyaMusic.updateAppState(context, newLocale: newLocale);
              showToast(context, context.l10n!.languageMsg);
              Navigator.pop(context);
            },
            activeLanguageFullCode == newLocaleFullCode,
          );
        },
      ),
    );
  }

  void _showAudioQualityPicker(BuildContext context) {
    final availableQualities = ['low', 'medium', 'high'];
    final qualityNames = [
      context.l10n!.audioQualityLow,
      context.l10n!.audioQualityMedium,
      context.l10n!.audioQualityHigh,
    ];
    const qualityIcons = [
      FluentIcons.speaker_1_24_regular,
      FluentIcons.speaker_2_24_regular,
      FluentIcons.speaker_2_24_filled,
    ];

    showCustomBottomSheet(
      context,
      ListView.builder(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        padding: commonListViewBottomPadding,
        itemCount: availableQualities.length,
        itemBuilder: (context, index) {
          final quality = availableQualities[index];

          return BottomSheetBar(
            qualityNames[index],
            () {
              addOrUpdateData<String>('settings', 'audioQuality', quality);
              audioQualitySetting.value = quality;
              showToast(context, context.l10n!.audioQualityMsg);
              Navigator.pop(context);
            },
            audioQualitySetting.value == quality,
            icon: qualityIcons[index],
          );
        },
      ),
    );
  }

  void _toggleSystemColor(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'useSystemColor', value);
    useSystemColor.value = value;
    WiyaMusic.updateAppState(
      context,
      newAccentColor: primaryColorSetting,
      useSystemColor: value,
    );
    showToast(context, context.l10n!.settingChangedMsg);
  }

  void _togglePureBlack(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'usePureBlackColor', value);
    usePureBlackColor.value = value;
    WiyaMusic.updateAppState(context);
    showToast(context, context.l10n!.settingChangedMsg);
  }

  // Unused while these settings are hidden from most end users. Restore
  // alongside their CustomBar rows in the sections above to re-enable.
  /*
  void _togglePredictiveBack(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'predictiveBack', value);
    predictiveBack.value = value;
    transitionsBuilder = value
        ? const PredictiveBackPageTransitionsBuilder()
        : const CupertinoPageTransitionsBuilder();
    WiyaMusic.updateAppState(context);
    showToast(context, context.l10n!.settingChangedMsg);
  }
  */

  /*
  Future<void> _toggleWrapped(BuildContext context, bool value) async {
    if (!value) {
      audioHandler.resetListeningStatsSession(
        countCurrentTick: true,
        flushStats: false,
      );
      await listeningStatsService.flush();
    }

    await addOrUpdateData<bool>('settings', 'wrappedEnabled', value);
    wrappedEnabled.value = value;
    listeningStatsService.reload();
    if (value) {
      audioHandler.startListeningStatsSessionIfNeeded();
    }
    if (context.mounted) {
      showToast(context, context.l10n!.settingChangedMsg);
    }
  }
  */

  void _toggleOfflineMode(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'offlineMode', value);
    offlineMode.value = value;

    // Trigger router refresh and notify about the change
    NavigationManager.refreshRouter();

    showToast(context, context.l10n!.settingChangedMsg);
  }

  /*
  void _toggleSponsorBlock(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'sponsorBlockSupport', value);
    sponsorBlockSupport.value = value;
    showToast(context, context.l10n!.settingChangedMsg);
  }
  */

  void _toggleAutoPlayNext(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'playNextSongAutomatically', value);
    playNextSongAutomatically.value = value;
    showToast(context, context.l10n!.settingChangedMsg);
  }

  /*
  void _toggleAutomaticUpdateChecks(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'shouldWeCheckUpdates', value);
    shouldWeCheckUpdates.value = value;
    showToast(context, context.l10n!.settingChangedMsg);
  }

  void _toggleExternalRecommendations(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'externalRecommendations', value);
    externalRecommendations.value = value;
    showToast(context, context.l10n!.settingChangedMsg);
  }
  */

  void _showConfirmationDialog({
    required BuildContext context,
    required String confirmationMessage,
    required VoidCallback onSubmit,
    String? submitMessage,
    bool isDangerous = false,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ConfirmationDialog(
          submitMessage: submitMessage ?? context.l10n!.clear,
          confirmationMessage: confirmationMessage,
          isDangerous: isDangerous,
          onCancel: () => Navigator.of(context).pop(),
          onSubmit: () {
            Navigator.of(context).pop();
            onSubmit();
          },
        );
      },
    );
  }

  Future<void> _backupUserData(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;

    try {
      // Android-only heads-up about scoped-storage folder limits.
      if (Platform.isAndroid && context.mounted) {
        await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              icon: Icon(
                FluentIcons.info_24_regular,
                color: colorScheme.primary,
                size: 32,
              ),
              content: Text(
                context.l10n!.folderRestrictions,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: <Widget>[
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n!.understand),
                ),
              ],
            );
          },
        );
      }

      if (!context.mounted) return;
      final result = await backupData(context);
      if (context.mounted) {
        showToast(
          context,
          result.message,
          icon: result.success ? null : FluentIcons.error_circle_24_regular,
        );
      }
    } catch (e, stackTrace) {
      logger.log('Error backing up data', error: e, stackTrace: stackTrace);
      if (context.mounted) {
        showToast(
          context,
          context.l10n!.error,
          icon: FluentIcons.error_circle_24_regular,
        );
      }
    }
  }
}

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.78,
      alignment: Alignment.centerRight,
      child: Switch(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
