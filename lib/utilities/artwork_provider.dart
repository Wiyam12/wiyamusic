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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class ArtworkProvider {
  ArtworkProvider._();

  static const AssetImage defaultArtwork = AssetImage(
    'assets/images/default_artwork.png',
  );

  // Cache by a short key so large base64 payloads aren't Map keys.
  static final Map<String, ImageProvider> _cache = {};

  /// Returns true when [path] is a local file path that currently exists.
  static bool localFileExists(String? path) {
    if (kIsWeb || path == null || path.isEmpty) return false;
    final normalized = path.replaceFirst('file://', '');
    if (!(normalized.startsWith('/') || path.startsWith('file://'))) {
      return false;
    }
    try {
      return File(normalized).existsSync();
    } catch (_) {
      return false;
    }
  }

  static ImageProvider get(String artwork) {
    if (artwork.isEmpty) throw ArgumentError('artwork must not be empty');

    final cacheKey = _cacheKey(artwork);
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    late ImageProvider provider;
    try {
      if (artwork.startsWith('http')) {
        provider = CachedNetworkImageProvider(artwork);
      } else if (artwork.startsWith('data:')) {
        provider = MemoryImage(_decodeDataUri(artwork));
      } else if (_looksLikeRawBase64(artwork)) {
        provider = MemoryImage(base64Decode(artwork));
      } else if (!kIsWeb &&
          (artwork.startsWith('file://') || artwork.startsWith('/'))) {
        final path = artwork.replaceFirst('file://', '');
        final file = File(path);
        // Skip FileImage when the offline artwork was deleted / never saved —
        // FileImage throws PathNotFoundException while resolving the codec.
        if (!file.existsSync()) {
          return defaultArtwork;
        }
        provider = FileImage(file);
      } else {
        provider = AssetImage(artwork);
      }
    } catch (_) {
      return defaultArtwork;
    }

    _cache[cacheKey] = provider;
    return provider;
  }

  static String _cacheKey(String artwork) {
    if (artwork.length <= 128) return artwork;
    return '${artwork.length}:${artwork.hashCode}:'
        '${artwork.substring(0, 32)}:${artwork.substring(artwork.length - 32)}';
  }

  static Uint8List _decodeDataUri(String artwork) {
    final commaIdx = artwork.indexOf(',');
    if (commaIdx == -1) {
      throw Exception('invalid data URI image');
    }
    return base64Decode(artwork.substring(commaIdx + 1));
  }

  static bool _looksLikeRawBase64(String value) {
    if (value.length < 64) return false;
    if (value.contains('/') || value.contains('.') || value.contains(':')) {
      return false;
    }
    return RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(value);
  }

  static void clearCache() => _cache.clear();
}
