import 'dart:convert';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wiyamusic/constants/version.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/services/data_manager.dart';
import 'package:wiyamusic/services/router_service.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/utilities/flutter_toast.dart';
import 'package:wiyamusic/utilities/url_launcher.dart';
import 'package:wiyamusic/widgets/auto_format_text.dart';

/// Live website version manifest (versioned APK + changelog).
const String checkUrl =
    'https://wiyam12.github.io/wiyamusic/downloads/android/version.json';
const String downloadUrlKey = 'url';
const String downloadUrlArm64Key = 'arm64url';

const String _skippedUpdateVersionKey = 'skippedUpdateVersion';

Future<void> checkAppUpdates({bool manual = false}) async {
  BuildContext? dialogContext;
  try {
    dialogContext = NavigationManager().context;
  } catch (_) {
    dialogContext = null;
  }

  try {
    final response = await http
        .get(Uri.parse(checkUrl))
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      logger.log(
        'Fetch update API (checkUrl) call returned status code ${response.statusCode}',
      );
      if (manual && dialogContext != null && dialogContext.mounted) {
        showToast(dialogContext, dialogContext.l10n!.error);
      }
      return;
    }

    final map = json.decode(response.body) as Map<String, dynamic>;
    final announcement = map['announcementurl']?.toString();
    if (announcement != null && announcement.isNotEmpty) {
      announcementURL.value = announcement;
    }

    final latestVersion = map['version']?.toString().trim() ?? '';
    if (latestVersion.isEmpty) {
      if (manual && dialogContext != null && dialogContext.mounted) {
        showToast(dialogContext, dialogContext.l10n!.error);
      }
      return;
    }

    if (!isLatestVersionHigher(appVersion, latestVersion)) {
      if (manual && dialogContext != null && dialogContext.mounted) {
        showToast(dialogContext, dialogContext.l10n!.noUpdateAvailable);
      }
      return;
    }

    // Auto prompts respect "don't display again" for this exact version.
    if (!manual) {
      final skipped = await getData('settings', _skippedUpdateVersionKey);
      if (skipped?.toString() == latestVersion) {
        return;
      }
    }

    if (dialogContext == null || !dialogContext.mounted) return;

    final changelog = (map['changelog']?.toString().trim().isNotEmpty ?? false)
        ? map['changelog'].toString().trim()
        : 'WiyaMusic $latestVersion is ready to install.';

    await showDialog<void>(
      context: dialogContext,
      builder: (BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;
        var dontShowAgain = false;

        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> persistSkipIfNeeded() async {
              if (!dontShowAgain) return;
              await addOrUpdateData<String>(
                'settings',
                _skippedUpdateVersionKey,
                latestVersion,
              );
            }

            return AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      FluentIcons.arrow_download_24_regular,
                      color: colorScheme.onPrimaryContainer,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n!.appUpdateIsAvailable,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'V$latestVersion',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height / 2.5,
                    ),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SingleChildScrollView(
                      child: AutoFormatText(text: changelog),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: dontShowAgain,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      context.l10n!.dontShowAgain,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() => dontShowAgain = value ?? false);
                    },
                  ),
                ],
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: <Widget>[
                OutlinedButton(
                  onPressed: () async {
                    await persistSkipIfNeeded();
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colorScheme.outline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(context.l10n!.cancel),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    await persistSkipIfNeeded();
                    final url = await getDownloadUrl(map);
                    await launchURL(Uri.parse(url));
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(FluentIcons.arrow_download_20_regular),
                  label: Text(context.l10n!.download),
                ),
              ],
            );
          },
        );
      },
    );
  } catch (e, stackTrace) {
    logger.log('Error in checkAppUpdates', error: e, stackTrace: stackTrace);
    if (manual && dialogContext != null && dialogContext.mounted) {
      showToast(dialogContext, dialogContext.l10n!.error);
    }
  }
}

void showUpdateCheckDialog(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        icon: Icon(
          FluentIcons.arrow_sync_circle_24_regular,
          color: colorScheme.primary,
          size: 40,
        ),
        title: Text(
          context.l10n!.checkForUpdates,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        content: Text(
          context.l10n!.enableUpdateChecksDescription,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            onPressed: () {
              shouldWeCheckUpdates.value = false;
              addOrUpdateData<bool>('settings', 'shouldWeCheckUpdates', false);
              Navigator.of(context).pop();
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colorScheme.outline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(context.l10n!.no),
          ),
          FilledButton(
            onPressed: () {
              shouldWeCheckUpdates.value = true;
              addOrUpdateData<bool>('settings', 'shouldWeCheckUpdates', true);
              if (!isFdroidBuild && !offlineMode.value) {
                checkAppUpdates();
                isUpdateChecked = true;
              }
              Navigator.of(context).pop();
            },
            child: Text(context.l10n!.yes),
          ),
        ],
      );
    },
  );
}

bool isLatestVersionHigher(String appVersion, String latestVersion) {
  final parsedAppVersion = appVersion.split('.');
  final parsedAppLatestVersion = latestVersion.split('.');
  final length = parsedAppVersion.length > parsedAppLatestVersion.length
      ? parsedAppVersion.length
      : parsedAppLatestVersion.length;
  for (var i = 0; i < length; i++) {
    final value1 = i < parsedAppVersion.length
        ? int.tryParse(parsedAppVersion[i]) ?? 0
        : 0;
    final value2 = i < parsedAppLatestVersion.length
        ? int.tryParse(parsedAppLatestVersion[i]) ?? 0
        : 0;
    if (value2 > value1) {
      return true;
    } else if (value2 < value1) {
      return false;
    }
  }

  return false;
}

Future<String> getCPUArchitecture() async {
  try {
    final info = await Process.run('uname', ['-m']);
    return info.stdout.toString().replaceAll('\n', '');
  } catch (_) {
    return '';
  }
}

Future<String> getDownloadUrl(Map<String, dynamic> map) async {
  final cpuArchitecture = await getCPUArchitecture();
  final arm64 = map[downloadUrlArm64Key]?.toString();
  final universal = map[downloadUrlKey]?.toString();
  final apkPath = map['apkPath']?.toString();

  if (cpuArchitecture == 'aarch64' &&
      arm64 != null &&
      arm64.isNotEmpty &&
      arm64 != 'null') {
    return arm64;
  }
  if (universal != null && universal.isNotEmpty && universal != 'null') {
    return universal;
  }
  if (apkPath != null && apkPath.isNotEmpty) {
    return 'https://wiyam12.github.io/wiyamusic/$apkPath';
  }
  return 'https://wiyam12.github.io/wiyamusic/downloads/android/wiyamusic.apk';
}

/// Fetch only the announcement URL from the version manifest and set the
/// global `announcementURL` ValueNotifier. This does not trigger update
/// dialogs/downloads and is safe to call for F‑Droid builds.
Future<void> fetchAnnouncementOnly() async {
  try {
    final response = await http
        .get(Uri.parse(checkUrl))
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      logger.log(
        'Fetch announcement (checkUrl) call returned status code ${response.statusCode}',
      );
      return;
    }

    final map = json.decode(response.body) as Map<String, dynamic>;
    final ann = map['announcementurl'];
    if (ann != null && ann.toString().isNotEmpty) {
      announcementURL.value = ann.toString();
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error in fetchAnnouncementOnly',
      error: e,
      stackTrace: stackTrace,
    );
  }
}
