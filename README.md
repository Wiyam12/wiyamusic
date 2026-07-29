# WiyaMusic Website

Static marketing site for WiyaMusic.

## Local preview

```bash
python3 -m http.server 8080
```

Open `http://127.0.0.1:8080`.

## App downloads

Place release builds in:

- `downloads/android/wiyamusic-<version>.apk` (example: `wiyamusic-1.1.0.apk`)
- `downloads/android/version.json` (must match the APK version/filename)
- `downloads/ios/wiyamusic.ipa`

The homepage download buttons are filled from `version.json` at runtime.

## Deploy

This branch is published to GitHub Pages via `.github/workflows/deploy-pages.yml`.

Live URL: https://wiyam12.github.io/wiyamusic/
