# Velqi Developer Guide

## Quick Reference

### Build Commands

```powershell
# Environment variables (set before any build)
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot"
$env:ANDROID_HOME = "C:\Android\Sdk"
$env:SERIOUS_PYTHON_SITE_PACKAGES = "C:\Users\Admin\Desktop\Velqi-Music-App\build\python-site-packages"
$env:PATH = "C:\flutter\bin;C:\Users\Admin\AppData\Local\Programs\Python\Python312;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

# Step 1: Package Python backend (PIN yt-dlp version — see Bug #7 below)
dart run serious_python:main package python --platform Android --asset assets/python_app.zip -r "yt-dlp==2026.07.04" -r "ytmusicapi==1.12.1" --cleanup

# IMPORTANT: SERIOUS_PYTHON_SITE_PACKAGES must ALSO be set when running `flutter build apk`
# (the serious_python Gradle plugin reads it). Without it: "SERIOUS_PYTHON_SITE_PACKAGES
# environment variable is not set" and the build fails.

# Step 2: Optimize (optional, reduces ~11MB per arch)
python scripts/trim_ytdlp.py build/python-site-packages

# Step 3: Build APKs
flutter build apk --release --split-per-abi --android-skip-build-dependency-validation
```

### Version Update Checklist

**Places to update for each release:**

1. `pubspec.yaml` line 5: `version: X.Y.Z+1` (Flutter/Android build version — drives `versionName`/`versionCode` in the APK)
2. `lib/ui/screens/Settings/settings_screen_controller.dart` line 46: `currentVersion = "VX.Y.Z"` (shown in app UI + update check)
3. `windows/packaging/exe/inno_setup.iss` line 3: `AppVersion=X.Y.Z` (Windows installer metadata)
4. `README.md`: APK filenames + "Cambios recientes" sections

If only one is updated, the app will show the wrong version or trigger false update notifications.

---

## Critical Bugs & Fixes (Lessons Learned)

### 1. Android 11+ MANAGE_EXTERNAL_STORAGE Permission

**Problem:** `permission_handler` package's `.request()` silently returns `denied` on Android 11+ without showing any UI dialog.

**Fix:** Open `ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` via native MethodChannel.

**Files:**
- `lib/services/permission_service.dart` — Dart side, calls MethodChannel
- `android/app/src/main/kotlin/com/velqi/app/MainActivity.kt` — Native handler

**Key rule:** After opening settings, return `false` and let the user retry. Don't check permission immediately — the user hasn't had time to grant it yet.

### 2. Export vs Download (Different Features!)

- **Download** = saves to app's internal cache (`$_cacheDir/cachedSongs/`) for in-app offline playback
- **Export** = copies from internal cache to external storage (user-accessible via file manager)

When a user says "exportar" they mean Export, not Download. These have completely different code paths.

**Export code:** `lib/ui/widgets/export_file_dialog.dart`
**Download code:** `lib/services/downloader.dart`

### 3. Notification Channel ID

**Problem:** `androidNotificationChannelId` was set to placeholder `com.mycompany.myapp.audio`.

**Fix:** Changed to `com.velqi.app.audio` in `lib/services/audio_handler.dart:38`.

### 4. POST_NOTIFICATIONS Permission (Android 13+)

**Problem:** Missing from AndroidManifest.xml and no runtime request.

**Fix:** Added `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>` and runtime request via `PermissionService.getNotificationPermission()` in `main.dart`.

### 5. Dio.download Parameter Order

**Problem:** `options` was passed as second positional argument instead of named parameter.

**Fix:** `filePath` must be second argument, `options` as named parameter.

```dart
// WRONG
_dio.download(url, options: Options(...), filePath, ...)

// CORRECT
_dio.download(url, filePath, options: Options(...), ...)
```

### 6. Backend ensureReady() Before Requests

**Problem:** Download/export could hit the Python backend before it finished importing.

**Fix:** Always call `BackendService.instance.ensureReady()` before `StreamProvider.fetch()`.

### 7. YouTube killed tv_embedded client (v1.3.0 — URGENT fix)

**Problem:** Users got "formato no disponible" / `Requested format is not available` on playback and download. Root cause was NOT yt-dlp being obsolete: the backend forced `player_client: ["tv_embedded", "android"]` + `skip: ["hls", "dash"]`. YouTube killed the `tv_embedded` client in early 2026 (removed from yt-dlp 2026.01.31), and skipping DASH manifests removed the audio-only formats (itags 139/249/140/251) entirely. Result: yt-dlp returned ZERO audio-only formats and fell back to the muxed itag 18.

**Fix (`python/ytdlp_backend.py`):** use `player_client: ["default"]` and remove `skip: ["hls", "dash"]`. Verified with yt-dlp 2026.07.04 across 4 videos: returns 26-31 formats including itags 139/249/140/251 with direct URLs, no cookies and no JS runtime needed.

**Rules:**
- ALWAYS pin the yt-dlp version in `python/requirements.txt`, `build_android.ps1`, `build_android_full.ps1` and the DEV_GUIDE command above. Do NOT let it float (`-r "yt-dlp"`).
- After any yt-dlp upgrade, recreate `assets/python_app.zip` WITHOUT `site-packages.zip` inside (it would shadow the fresh per-ABI deps via main.py's ZipImport `sys.path.insert(0, ...)`), and rebuild the APK.
- Do not hardcode player clients. yt-dlp's `default` client list handles fallbacks across clients (android_vr, web, ...) automatically.
- QuickJS (`qjs` binary) remains optional: yt-dlp 2026.07.04 resolves current YouTube videos without any JS runtime.

---

## BlueStacks Testing

- Use `app-x86_64-release.apk` (not arm64)
- ADB address: `127.0.0.1:5555`
- ADB is unstable — use `adb kill-server` + `adb start-server` + `adb connect` to reconnect
- Always use `--timeout` on adb commands

---

## Project Architecture

```
lib/
  main.dart                    — App entry, Hive init, backend start
  services/
    audio_handler.dart         — Audio playback + notification
    downloader.dart            — Download/export songs
    music_service.dart         — HTTP client to Python backend
    stream_service.dart        — Stream URL resolution
    permission_service.dart    — Storage/notification permissions
    backend/
      backend_service.dart     — Python backend lifecycle
      backend_android.dart     — Android runner (serious_python)
      backend_desktop.dart     — Windows runner
  ui/
    player/                    — Player UI + controller
    screens/Settings/          — Settings + version display
    widgets/export_file_dialog.dart — Export dialog
  models/                      — Data models (Album, Artist, etc.)

python/
  main.py                      — HTTP server (localhost:8765)
  ytdlp_backend.py             — yt-dlp stream resolution
  ytmusic_backend.py           — ytmusicapi metadata
```

---

## Git Identity

- **Author:** LuPyther
- **Email:** roybrayanccamaquechuma@gmail.com
- **Always commit with:** `git config user.name "LuPyther"` + `git config user.email "roybrayanccamaquechuma@gmail.com"`
