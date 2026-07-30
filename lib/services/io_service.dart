import 'dart:io';

late String applicationDirPath;

class FilePaths {
  // File extensions
  static const String audioExtension = '.m4a';
  static const String artworkExtension = '.jpg';
  static const String lyricsExtension = '.json';

  // Directory names
  static const String tracksDir = 'tracks';
  static const String artworksDir = 'artworks';
  static const String lyricsDir = 'lyrics';

  // Get full paths for various file types
  static String getAudioPath(String songId) {
    return '$applicationDirPath/$tracksDir/$songId$audioExtension';
  }

  static String getArtworkPath(String songId) {
    return '$applicationDirPath/$artworksDir/$songId$artworkExtension';
  }

  static String getLyricsPath(String songId) {
    return '$applicationDirPath/$lyricsDir/$songId$lyricsExtension';
  }

  /// Resolves a playable local audio path for [songId].
  ///
  /// Prefers the canonical current app-documents path. This matters on iOS
  /// where the container UUID (and therefore absolute Hive-stored paths) can
  /// change across installs/updates while the files themselves move with the
  /// container.
  static Future<String?> resolveExistingAudioPath(
    String songId, {
    String? storedPath,
  }) {
    return _resolveExistingPath(
      canonicalPath: getAudioPath(songId),
      storedPath: storedPath,
      relativeDir: tracksDir,
    );
  }

  /// Resolves a local artwork file path for [songId], with the same iOS
  /// container-path remapping as [resolveExistingAudioPath].
  static Future<String?> resolveExistingArtworkPath(
    String songId, {
    String? storedPath,
  }) {
    return _resolveExistingPath(
      canonicalPath: getArtworkPath(songId),
      storedPath: storedPath,
      relativeDir: artworksDir,
    );
  }

  static Future<String?> _resolveExistingPath({
    required String canonicalPath,
    required String? storedPath,
    required String relativeDir,
  }) async {
    final candidates = <String>{
      canonicalPath,
      if (storedPath != null && storedPath.isNotEmpty)
        storedPath.replaceFirst('file://', ''),
    };

    final remapped = remapPathToCurrentAppDir(
      storedPath,
      relativeDir: relativeDir,
    );
    if (remapped != null && remapped.isNotEmpty) {
      candidates.add(remapped);
    }

    for (final path in candidates) {
      try {
        if (await File(path).exists()) return path;
      } catch (_) {}
    }
    return null;
  }

  /// Rewrites an absolute path under a previous iOS/Android app container to
  /// the current [applicationDirPath], keeping the relative `dir/filename`.
  static String? remapPathToCurrentAppDir(
    String? storedPath, {
    required String relativeDir,
  }) {
    if (storedPath == null || storedPath.isEmpty) return null;

    final normalized = storedPath.replaceFirst('file://', '');
    final marker = '/$relativeDir/';
    final markerIndex = normalized.lastIndexOf(marker);
    if (markerIndex == -1) return null;

    final relative = normalized.substring(markerIndex + 1); // dir/file.ext
    return '$applicationDirPath/$relative';
  }

  // Ensure directories exist
  static Future<void> ensureDirectoriesExist() async {
    final tracksDirectory = Directory('$applicationDirPath/$tracksDir');
    final artworksDirectory = Directory('$applicationDirPath/$artworksDir');
    final lyricsDirectory = Directory('$applicationDirPath/$lyricsDir');

    if (!await tracksDirectory.exists()) {
      await tracksDirectory.create(recursive: true);
    }

    if (!await artworksDirectory.exists()) {
      await artworksDirectory.create(recursive: true);
    }

    if (!await lyricsDirectory.exists()) {
      await lyricsDirectory.create(recursive: true);
    }
  }
}
