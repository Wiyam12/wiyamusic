import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Clients tried one-at-a-time when resolving stream manifests.
///
/// ANDROID_VR is prioritized everywhere: it reliably returns audio streams and
/// avoids the 403 that the IOS client throws on some video itags (e.g. 137)
/// while building the manifest, which otherwise aborts the whole fetch. The
/// IOS client is kept only as a last-resort fallback on Apple platforms.
List<YoutubeApiClient> get customClients {
  if (Platform.isIOS || Platform.isMacOS) {
    return [
      customAndroidVr,
      YoutubeApiClient.androidSdkless,
      YoutubeApiClient.ios,
    ];
  }

  return [customAndroidVr, YoutubeApiClient.androidSdkless];
}

/// ANDROID_VR client with an explicit User-Agent (required by googlevideo CDN).
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

String clientStreamUserAgent(YoutubeApiClient client) {
  final fromPayload =
      client.payload['context']?['client']?['userAgent'] as String?;
  if (fromPayload != null && fromPayload.isNotEmpty) return fromPayload;

  final fromHeaders = client.headers['User-Agent'] as String?;
  if (fromHeaders != null && fromHeaders.isNotEmpty) return fromHeaders;

  if (client.payload['context']?['client']?['clientName'] == 'IOS') {
    return 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)';
  }

  return 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
}

Map<String, String> streamHeadersForClient(YoutubeApiClient client) => {
  'User-Agent': clientStreamUserAgent(client),
  'Accept': '*/*',
  'Referer': 'https://www.youtube.com/',
  'Origin': 'https://www.youtube.com',
};

/// Default headers for the platform's preferred client.
Map<String, String> get youtubeStreamHeaders =>
    streamHeadersForClient(customClients.first);
