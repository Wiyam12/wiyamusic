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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/main.dart' show logger;

// Cache durations for different types of data
const Duration songCacheDuration = Duration(hours: 1, minutes: 30);
const Duration playlistCacheDuration = Duration(hours: 5);
/// Saved playlists/albums/artists are local-first and remain available until
/// the user explicitly clears the cache.
const Duration likedPlaylistCacheDuration = Duration(days: 3650);
const Duration searchCacheDuration = Duration(days: 4);
const Duration defaultCacheDuration = Duration(days: 7);

// In-memory cache for frequently accessed items
final _memoryCache = <String, _CacheEntry>{};

class _CacheEntry {
  _CacheEntry(this.data, this.timestamp);
  final dynamic data;
  final DateTime timestamp;

  bool isValid(Duration cacheDuration) {
    return DateTime.now().difference(timestamp) < cacheDuration;
  }
}

// Maximum number of entries allowed in the memory cache
const int _maxMemoryCacheSize = 500;
const int _memoryCacheTrimSize = 100;

void _setMemoryCacheEntry(String key, _CacheEntry entry) {
  _memoryCache
    ..remove(key)
    ..[key] = entry;
  _trimMemoryCacheIfNeeded();
}

void _touchMemoryCacheEntry(String key) {
  final entry = _memoryCache.remove(key);
  if (entry != null) {
    _memoryCache[key] = entry;
  }
}

void _trimMemoryCacheIfNeeded() {
  if (_memoryCache.length > _maxMemoryCacheSize) {
    final keysToRemove = _memoryCache.keys.take(_memoryCacheTrimSize).toList();
    for (final key in keysToRemove) {
      _memoryCache.remove(key);
    }
  }
}

Future<void> addOrUpdateData<T>(String category, String key, T value) async {
  final _box = await _openBox(category);
  await _box.put(key, value);

  if (category == 'cache') {
    await _box.put('${key}_date', DateTime.now());

    // Update memory cache too
    final cacheKey = '${category}_$key';
    _setMemoryCacheEntry(cacheKey, _CacheEntry(value, DateTime.now()));
  }
}

Future<dynamic> getData(
  String category,
  String key, {
  dynamic defaultValue,
  Duration? cachingDuration,
}) async {
  // Set appropriate cache duration based on key
  cachingDuration ??= _getCacheDurationForKey(key);

  // Check memory cache first
  final cacheKey = '${category}_$key';
  final memCacheEntry = _memoryCache[cacheKey];
  if (memCacheEntry != null && memCacheEntry.isValid(cachingDuration)) {
    _touchMemoryCacheEntry(cacheKey);
    return memCacheEntry.data;
  }
  _trimMemoryCacheIfNeeded();

  final _box = await _openBox(category);
  if (category == 'cache') {
    final cacheIsValid = isCacheValid(_box, key, cachingDuration);
    if (!cacheIsValid) {
      await deleteData(category, key);
      await deleteData(category, '${key}_date');
      return defaultValue;
    }
  }

  final data = await _box.get(key, defaultValue: defaultValue);

  // Store in memory cache for faster access next time
  if (data != null && category == 'cache') {
    final timestamp = await _box.get('${key}_date') ?? DateTime.now();
    _setMemoryCacheEntry(cacheKey, _CacheEntry(data, timestamp));
  }

  return data;
}

Future<void> deleteData(String category, String key) async {
  _memoryCache
    ..remove('${category}_$key')
    ..remove('${category}_${key}_date');

  final _box = await _openBox(category);
  await _box.delete(key);
}

Future<bool> clearCache() async {
  try {
    // Clear memory cache
    _memoryCache.clear();

    final cacheBox = await _openBox('cache');
    await cacheBox.clear();
    return true;
  } catch (e, stackTrace) {
    logger.log('Failed to clear cache', error: e, stackTrace: stackTrace);
    return false;
  }
}

// Clean up old cache entries to prevent excessive storage usage
Future<void> cleanupOldCacheEntries() async {
  try {
    final cacheBox = await _openBox('cache');
    final now = DateTime.now();

    // Get all keys except the ones with _date suffix
    final keys = cacheBox.keys
        .where((k) => !k.toString().endsWith('_date'))
        .toList();

    for (final key in keys) {
      final dateKey = '${key}_date';
      final date = cacheBox.get(dateKey);

      if (date == null) {
        await cacheBox.delete(key);
        continue;
      }

      final age = now.difference(date);
      // Very old cache entries (older than 30 days) should be removed
      if (age > const Duration(days: 30)) {
        await cacheBox.delete(key);
        await cacheBox.delete(dateKey);
      }
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error cleaning up old cache entries',
      error: e,
      stackTrace: stackTrace,
    );
  }
}

// Check if the cache is still valid based on the caching duration
bool isCacheValid(Box box, String key, Duration cachingDuration) {
  final date = box.get('${key}_date');
  if (date == null) {
    return false;
  }
  final age = DateTime.now().difference(date);
  return age < cachingDuration;
}

Duration _getCacheDurationForKey(String key) {
  if (key.startsWith('song_') || key.contains('manifest_')) {
    return songCacheDuration;
  } else if (key.startsWith('playlistInfo') ||
      key.startsWith('playlistSongs') ||
      key.contains('playlistSongs')) {
    // Liked/saved playlist payloads should survive longer than generic cache.
    return likedPlaylistCacheDuration;
  } else if (key.startsWith('playlist_')) {
    return playlistCacheDuration;
  } else if (key.startsWith('search_')) {
    return searchCacheDuration;
  }
  return defaultCacheDuration;
}

Future<Box> _openBox(String category) async {
  if (Hive.isBoxOpen(category)) {
    return Hive.box(category);
  } else {
    return Hive.openBox(category);
  }
}

const _backupFormatVersion = 1;
const _backupBoxNames = ['user', 'settings'];

/// Converts Hive values into JSON-encodable structures.
dynamic _toJsonSafe(dynamic value) {
  if (value == null || value is num || value is String || value is bool) {
    return value;
  }
  if (value is DateTime) return value.toIso8601String();
  if (value is List) return value.map(_toJsonSafe).toList();
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _toJsonSafe(entry.value),
    };
  }
  return value.toString();
}

Map<String, dynamic> _boxToJsonMap(Box box) {
  final data = <String, dynamic>{};
  for (final key in box.keys) {
    data[key.toString()] = _toJsonSafe(box.get(key));
  }
  return data;
}

Future<Map<String, dynamic>> _buildBackupPayload() async {
  final boxes = <String, dynamic>{};
  for (final boxName in _backupBoxNames) {
    final box = await _openBox(boxName);
    try {
      await box.compact();
    } catch (e, stackTrace) {
      logger.log(
        'Failed to compact box $boxName before backup',
        error: e,
        stackTrace: stackTrace,
      );
    }
    boxes[boxName] = _boxToJsonMap(box);
  }

  return {
    'formatVersion': _backupFormatVersion,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'boxes': boxes,
  };
}

Future<void> _restoreBoxesFromJson(Map<String, dynamic> boxesJson) async {
  for (final boxName in _backupBoxNames) {
    final raw = boxesJson[boxName];
    if (raw is! Map) continue;

    final box = await _openBox(boxName);
    await box.clear();
    for (final entry in raw.entries) {
      await box.put(entry.key.toString(), entry.value);
    }
  }
}

Future<({String message, bool success})> backupData(
  BuildContext context,
) async {
  try {
    final payload = await _buildBackupPayload();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final fileName = 'wiyamusic_backup_$stamp.json';
    final jsonBytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );

    // On iOS, getDirectoryPath() returns a File Provider location that dart:io
    // cannot write to (PathAccessException / EPERM). saveFile with bytes uses
    // the system document picker and writes with the proper entitlements.
    // Android also requires bytes for saveFile in file_picker 11+.
    if (Platform.isIOS || Platform.isAndroid) {
      final savedPath = await FilePicker.saveFile(
        dialogTitle: context.l10n!.chooseBackupDir,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: jsonBytes,
      );

      if (savedPath == null) {
        return (message: '${context.l10n!.chooseBackupDir}!', success: false);
      }

      return (message: '${context.l10n!.backedupSuccess}!', success: true);
    }

    // Desktop: pick a destination path, then write the bytes ourselves.
    final savedPath = await FilePicker.saveFile(
      dialogTitle: context.l10n!.chooseBackupDir,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: jsonBytes,
    );

    if (savedPath == null) {
      return (message: '${context.l10n!.chooseBackupDir}!', success: false);
    }

    final targetFile = File(savedPath);
    await targetFile.parent.create(recursive: true);
    await targetFile.writeAsBytes(jsonBytes, flush: true);

    return (message: '${context.l10n!.backedupSuccess}!', success: true);
  } catch (e, stackTrace) {
    logger.log('Backup error', error: e, stackTrace: stackTrace);
    return (message: '${context.l10n!.backupError}: $e', success: false);
  }
}

Future<({String message, bool success})> restoreData(
  BuildContext context,
) async {
  final result = await FilePicker.pickFiles(
    allowMultiple: true,
    type: FileType.custom,
    allowedExtensions: const ['json', 'hive'],
  );

  if (result == null || result.files.isEmpty) {
    return (message: '${context.l10n!.chooseBackupFiles}!', success: false);
  }

  try {
    final jsonBackup = result.files.where((file) {
      final name = file.name.toLowerCase();
      return name.endsWith('.json') && file.path != null;
    }).firstOrNull;

    if (jsonBackup?.path != null) {
      final content = await File(jsonBackup!.path!).readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        return (message: '${context.l10n!.restoreError}', success: false);
      }

      final boxes = decoded['boxes'];
      if (boxes is! Map) {
        return (message: '${context.l10n!.restoreError}', success: false);
      }

      await _restoreBoxesFromJson(
        Map<String, dynamic>.from(
          boxes.map((key, value) => MapEntry(key.toString(), value)),
        ),
      );
      return (message: '${context.l10n!.restoredSuccess}!', success: true);
    }

    // Legacy restore: separate user.hive / settings.hive copies.
    return _restoreLegacyHiveFiles(context, result.files);
  } catch (e, stackTrace) {
    logger.log('Restore error', error: e, stackTrace: stackTrace);
    return (message: '${context.l10n!.restoreError}: $e', success: false);
  }
}

Future<({String message, bool success})> _restoreLegacyHiveFiles(
  BuildContext context,
  List<PlatformFile> files,
) async {
  for (final boxName in _backupBoxNames) {
    if (Hive.isBoxOpen(boxName)) {
      try {
        await Hive.box(boxName).close();
      } catch (e, stackTrace) {
        logger.log(
          'Failed to close box $boxName',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
  }

  await Future.delayed(const Duration(milliseconds: 100));

  for (final boxName in _backupBoxNames) {
    final backupFile = files
        .where(
          (file) =>
              file.name == '$boxName.hive' ||
              file.name.startsWith('${boxName}_'),
        )
        .firstOrNull;

    if (backupFile?.path == null) {
      logger.log('Backup file for $boxName not found in selection');
      continue;
    }

    final sourceFile = File(backupFile!.path!);
    if (!await sourceFile.exists()) {
      logger.log('Backup file does not exist: ${sourceFile.path}');
      continue;
    }

    try {
      final tempBox = await Hive.openBox(boxName);
      final boxPath = tempBox.path;
      await tempBox.close();

      if (boxPath == null) continue;

      final targetFile = File(boxPath);
      await targetFile.parent.create(recursive: true);
      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (e, stackTrace) {
          logger.log(
            'Failed to delete existing file',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }

      await sourceFile.copy(targetFile.path);
      logger.log(
        'Restored $boxName from ${sourceFile.path} to ${targetFile.path}',
      );
    } catch (e, stackTrace) {
      logger.log(
        'Failed to restore $boxName',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  await Future.delayed(const Duration(milliseconds: 100));

  for (final boxName in _backupBoxNames) {
    try {
      await _openBox(boxName);
    } catch (e, stackTrace) {
      logger.log(
        'Failed to reopen box $boxName',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  return (message: '${context.l10n!.restoredSuccess}!', success: true);
}
