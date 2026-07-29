Place the Android release APK here using the versioned filename:

  wiyamusic-<version>.apk

Example for version 1.1.0:

  wiyamusic-1.1.0.apk

Keep `version.json` in sync with the APK:

```json
{
  "version": "1.1.0",
  "filename": "wiyamusic-1.1.0.apk",
  "apkPath": "downloads/android/wiyamusic-1.1.0.apk",
  "url": "https://wiyam12.github.io/wiyamusic/downloads/android/wiyamusic-1.1.0.apk",
  "arm64url": "https://wiyam12.github.io/wiyamusic/downloads/android/wiyamusic-1.1.0.apk",
  "announcementurl": "",
  "changelog": "Release notes for this version."
}
```

The website and the Android app both read `version.json` for the current download URL and update checks.
