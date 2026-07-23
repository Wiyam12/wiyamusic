import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Clients used when resolving stream manifests.
///
/// On Android we only use [YoutubeApiClient.androidSdkless] so googlevideo CDN
/// URLs match [youtubeStreamHeaders]. Mixing clients (VR/iOS) often yields URLs
/// that 403 when played with a different User-Agent.
List<YoutubeApiClient> get customClients {
  if (Platform.isIOS || Platform.isMacOS) {
    return [
      YoutubeApiClient.ios,
      YoutubeApiClient.androidSdkless,
    ];
  }

  return const [YoutubeApiClient.androidSdkless];
}

/// ANDROID_VR client aligned with current yt-dlp definitions.
/// Kept for optional restricted-video experiments; not used in [customClients].
const customAndroidVr = YoutubeApiClient(
  {
    'context': {
      'client': {
        'clientName': 'ANDROID_VR',
        'clientVersion': '1.65.10',
        'deviceMake': 'Oculus',
        'deviceModel': 'Quest 3',
        'androidSdkVersion': 32,
        'userAgent':
            'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
        'osName': 'Android',
        'osVersion': '12L',
        'hl': 'en',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    },
  },
  'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
  headers: {
    'User-Agent':
        'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
  },
);

/// User-Agent that must match the client used to mint the stream URL.
String get youtubeStreamUserAgent {
  if (Platform.isIOS || Platform.isMacOS) {
    return 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)';
  }
  return 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
}

/// Headers required by googlevideo CDN when opening progressive streams.
Map<String, String> get youtubeStreamHeaders => {
  'User-Agent': youtubeStreamUserAgent,
  'Accept': '*/*',
  'Referer': 'https://www.youtube.com/',
  'Origin': 'https://www.youtube.com',
};
