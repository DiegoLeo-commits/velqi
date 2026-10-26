# Velqi Desktop — Developer Deep-Dive Guide

> **Last updated:** 2026-08-22 — This document is intended for an AI or developer
> picking up work on the Velqi Windows desktop build. It covers architecture,
> every known bug and its root cause, build system quirks, and remaining issues.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Key Files Map](#2-key-files-map)
3. [Build System](#3-build-system)
4. [Critical Bug: Audio Playback on Desktop](#4-critical-bug-audio-playback-on-desktop)
5. [Critical Bug: Player UI Broken on Desktop](#5-critical-bug-player-ui-broken-on-desktop)
6. [Critical Bug: vcruntime140.dll](#6-critical-bug-vcruntime140dll)
7. [Critical Bug: Backend Zip Extraction](#7-critical-bug-backend-zip-extraction)
8. [Other Known Issues](#8-other-known-issues)
9. [Scripts Reference](#9-scripts-reference)
10. [How to Test](#10-how-to-test)

---

## 1. Architecture Overview

### Desktop Audio Pipeline

```
User taps song
  → HomeScreenController → AudioHandler.playByIndex(index)
    → StreamService.getStreamInfo(songId)
      → HTTP GET http://127.0.0.1:8765/stream?videoId=XXXX
        → Python backend (main.py) uses yt-dlp to extract YouTube URL
        → Returns JSON: { playable: true, audioFormats: [...] }
    → StreamProvider selects best audio format (mp4a > opus, high bitrate)
    → Sets URL on MediaItem extras
    → Creates AudioSource.uri(url) with headers
    → Player.setAudioSource → Player.play()
    → just_audio_windows (Windows Media Foundation) plays the URL
```

### Key difference: Android vs Desktop

| Component | Android | Desktop (Windows) |
|-----------|---------|-------------------|
| Audio player | ExoPlayer (via just_audio) | Windows Media Foundation (via just_audio_windows) |
| yt-dlp | Embedded in app via serious_python + python_app.zip | System Python (3.11+) must be installed separately |
| Python backend | Runs inside the app, auto-extracted | Runs as separate process, auto-extracted to `%APPDATA%\Lupyther\velqi_backend\` |
| Backend port | localhost:8765 | localhost:8765 |
| Permission handling | Android 13+ notification permission | N/A |

### Why just_audio_windows?

Originally Velqi used `just_audio_media_kit` (libmpv) for desktop. This **does not work** because libmpv cannot properly stream YouTube URLs — it either:
- Creates a local HTTP proxy (127.0.0.1:5426) that it can't connect to
- Sends incorrect HTTP headers (missing Range) causing 403 errors
- Reports `playing=true` but never actually decodes audio

The fix (inspired by the author's other project [OpenSudo](https://github.com/lupyther/OpenSudo)):
```yaml
# pubspec.yaml — BEFORE (broken):
just_audio_media_kit:
  git:
    url: https://github.com/anandnet/just_audio_media_kit.git
    ref: 6672eb82...

# pubspec.yaml — AFTER (working):
just_audio_windows: ^0.2.3
```

`just_audio_windows` uses Windows Media Foundation (WMF) which is the native
Windows media framework. It handles YouTube URLs, HTTP headers, Range requests,
and DASH/HLS streaming natively.

**DO NOT re-add `just_audio_media_kit`.** It conflicts with `just_audio_windows`
and causes crashes. Both try to register as the audio handler for Windows.

---

## 2. Key Files Map

### Audio Playback Pipeline

| File | Purpose |
|------|---------|
| `lib/services/audio_handler.dart` | Core audio handler. Creates AudioPlayer, manages queue, handles play/pause/seek/next. **This is where the playback bug lives.** |
| `lib/services/stream_service.dart` | Talks to the Python backend to get stream URLs. Parses `audioFormats` from JSON. |
| `lib/services/backend/backend_config.dart` | Defines `kBackendBaseUrl` = `http://127.0.0.1:8765` |
| `lib/services/backend/backend_desktop.dart` | Desktop backend launcher. Extracts python_app.zip, starts Python process, waits for port 8765. |
| `python/main.py` | Python HTTP server. Endpoints: `/init`, `/stream?videoId=X`, `/search`, etc. Uses yt-dlp. |
| `python/ytdlp_backend.py` | Core yt-dlp logic. Extracts audio formats from YouTube. |
| `python/ytmusic_backend.py` | YouTube Music API wrapper. |

### Player UI

| File | Purpose |
|------|---------|
| `lib/ui/player/player.dart` | SlidingUpPanel wrapper. Contains `Player()` as the full panel, `MiniPlayer()` as collapsed. |
| `lib/ui/player/player_controller.dart` | State management for player. progressBarStatus, play/pause/seek logic, sleep timer, lyrics. |
| `lib/ui/player/components/standard_player.dart` | Full-screen "Now Playing" view. Album art, glassmorphism controls. |
| `lib/ui/player/components/mini_player.dart` | Compact mini player above nav bar. |
| `lib/ui/player/components/player_control.dart` | Seekbar, play/pause button, shuffle/fav/loop/volume controls. |
| `lib/ui/home.dart` | Main Home widget. Assembles SlidingUpPanel + BottomNavBar + ScreenNavigation. |
| `lib/ui/widgets/bottom_nav_bar.dart` | Bottom navigation: Info, Home, Search, Library, Settings. |

### Settings & Info

| File | Purpose |
|------|---------|
| `lib/ui/screens/Settings/settings_screen_controller.dart` | All settings. `currentVersion` string is here. |
| `lib/ui/screens/Info/info_screen.dart` | Credits page with owner/supporter/illustrator. |
| `lib/ui/splash_screen.dart` | Minimalist splash screen. |
| `lib/ui/utils/theme_controller.dart` | Theme management + Windows title bar color. **Has DWM crash fix.** |

---

## 3. Build System

### Windows Build

```powershell
# 1. Build
flutter build windows --release

# 2. cmake install WILL FAIL (known issue with vcruntime140.dll)
#    The exe and app.so are still compiled successfully.
#    You must copy files manually:

RELEASE="build/windows/x64/runner/Release"

# Copy app.so to data/
cp build/windows/app.so "$RELEASE/data/app.so"

# Copy flutter_assets to data/
rm -rf "$RELEASE/data/flutter_assets"
cp -r build/flutter_assets "$RELEASE/data/flutter_assets"

# FIX vcruntime140.dll (build always overwrites with 32-bit version!)
cp "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Redist/MSVC/14.44.35112/x64/Microsoft.VC143.CRT/vcruntime140.dll" "$RELEASE/vcruntime140.dll"
cp "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Redist/MSVC/14.44.35112/x64/Microsoft.VC143.CRT/msvcp140.dll" "$RELEASE/msvcp140.dll"
```

### Directory Structure After Build

```
Release/
  velqi.exe                 ← Launcher (C++), doesn't change
  flutter_windows.dll       ← Flutter engine
  data/
    app.so                  ← Compiled Dart code (AOT). THIS is the real binary.
    flutter_assets/          ← Assets, fonts, python_app.zip
    icudtl.dat              ← ICU data
  *.dll                     ← Plugin DLLs (just_audio_windows, permission_handler, etc.)
  DLLs/                     ← Python stdlib modules
  vcruntime140.dll          ← MUST be 64-bit (PE32+)
  vcruntime140_1.dll        ← MUST be 64-bit (PE32+)
  msvcp140.dll              ← MUST be 64-bit (PE32+)
```

### Android Build

```powershell
$env:JAVA_HOME = "C:\Users\Usuario\jdk17\jdk-17.0.20+8"
$env:ANDROID_HOME = "C:\Android\Sdk"

flutter build apk --release --split-per-abi --android-skip-build-dependency-validation
```

APKs output to: `build/app/outputs/flutter-apk/`

### Python Backend Requirements

System Python 3.11+ with:
```bash
pip install yt-dlp ytmusicapi
```

Current versions installed: `yt-dlp==2026.8.19`, `ytmusicapi==1.12.2`

The backend auto-extracts `python_app.zip` from Flutter assets on first launch
to `%APPDATA%\Lupyther\velqi_backend\`. To force re-extraction, delete that directory.

---

## 4. Critical Bug: Audio Playback on Desktop

### Status: FIXED (partially)

**Root cause:** `just_audio_media_kit` (libmpv) cannot stream YouTube URLs.
**Fix applied:** Replaced with `just_audio_windows` (Windows Media Foundation).

**What was changed in `lib/services/audio_handler.dart`:**

1. Removed `import 'package:just_audio_media_kit/just_audio_media_kit.dart';`
2. Removed `JustAudioMediaKit.title = 'Velqi';` initialization
3. Changed `AudioPlayer()` constructor: `useProxyForRequestHeaders: !GetPlatform.isDesktop`
   (desktop=false → no proxy, headers pass directly to WMF)
4. Added desktop position polling timer (see below)

**What was changed in `pubspec.yaml`:**
- Removed `just_audio_media_kit` (git dependency)
- Added `just_audio_windows: ^0.2.3`

**What was changed in `python/main.py`:**
- Removed any custom User-Agent/headers (WMF handles this natively)

### Position Polling Timer (NEW)

`just_audio_windows` uses Windows Media Foundation which does NOT fire
`playbackEventStream` frequently enough for smooth seekbar updates.
The fix is a polling timer:

```dart
// In audio_handler.dart
Timer? _desktopPositionTimer;

void _startDesktopPositionPolling() {
  _desktopPositionTimer?.cancel();
  if (!GetPlatform.isDesktop) return;
  _desktopPositionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
    if (!_player.playing) return;
    final pos = _player.position;
    final dur = _player.duration;
    if (dur == null || dur.inSeconds == 0) return;
    playbackState.add(playbackState.value.copyWith(
      updatePosition: pos,
      bufferedPosition: _player.bufferedPosition,
    ));
  });
}
```

This timer is:
- Started in `_bindActivePlayerListeners()`
- Cancelled in `case 'stopPlayback'` and `case 'dispose'`
- Only active on desktop (`GetPlatform.isDesktop`)

---

## 5. Critical Bug: Player UI Broken on Desktop

### Status: **OPEN — NEEDS FIX**

The player works on Android but is visually broken on desktop. The symptoms:
- Seekbar may not show correctly or update properly
- Player panel (SlidingUpPanel) may not expand/collapse correctly
- Mini player may overlap or not dock properly with BottomNavBar
- Desktop is not draggable (`isDraggable: !GetPlatform.isDesktop` in player.dart)

**Root causes to investigate:**

1. **SlidingUpPanel `isDraggable: false` on desktop:** In `lib/ui/player/player.dart` line 40:
   ```dart
   isDraggable: !GetPlatform.isDesktop,
   ```
   This means on desktop, the player panel CANNOT be swiped open/closed.
   The mini player has `onTap: playerController.playerPanelController.open`
   so clicking works, but there's no way to drag it down to close.

2. **Back button:** Desktop has a `_PlayerBackButton` that calls `playerPanelController.close()`.
   This should collapse the panel.

3. **Mini player height:** In `player_controller.dart`:
   ```dart
   final miniPlayerHeight = isWideScreen ? 105.0 : 75.0;
   playerPanelMinHeight.value = miniPlayerHeight;
   ```

4. **BottomNavBar + MiniPlayer visual integration:** They share the same background color
   (`Color(0xFF18181C)` dark / `Color(0xFFF4F4F7)` light) but may have seam issues.

**Files to check for player UI fixes:**
- `lib/ui/home.dart` — SlidingUpPanel setup (lines 210-259)
- `lib/ui/player/player.dart` — Panel wrapper, collapsed widget, desktop handling
- `lib/ui/player/components/mini_player.dart` — Collapsed mini player
- `lib/ui/player/components/standard_player.dart` — Full player view
- `lib/ui/player/player_controller.dart` — Panel controller, minHeight logic

**Recommended approach:**
- Test on a large desktop window (>800px width triggers `isWideScreen`)
- Verify that clicking mini player opens the full player
- Verify that the back arrow (▼) in full player collapses it
- Check if seekbar updates (now with 250ms polling timer)
- Check if album art, controls, and progress bar are all visible

---

## 6. Critical Bug: vcruntime140.dll

### Status: **WORKAROUND — Every build re-breaks it**

Flutter's cmake install step always copies the **32-bit** (i386) `vcruntime140.dll`
from the wrong MSVC Redist path. The app is 64-bit and crashes with `0xC0000139`
(ENTRYPOINT NOT FOUND) or `0xC0000135` (DLL NOT FOUND) when the wrong DLL is used.

**Every build must manually replace:**
```powershell
cp "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT\vcruntime140.dll" Release/vcruntime140.dll
cp "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT\msvcp140.dll" Release/msvcp140.dll
```

**Verify with:** `file Release/vcruntime140.dll` → must show `PE32+` (x86-64), not `PE32` (i386).

The `build_desktop.ps1` script does this automatically.

**To fix permanently:** Modify `CMakeLists.txt` to use the x64 MSVC Redist path.
Look for the `install(FILES ... vcruntime140.dll ...)` directive.

---

## 7. Critical Bug: Backend Zip Extraction

### Status: **WORKING — But fragile**

The Python backend is embedded in `assets/python_app.zip`. On desktop launch:

1. `backend_desktop.dart` calls `_findPython()` to locate system Python
2. Extracts `python_app.zip` to `%APPDATA%\Lupyther\velqi_backend\`
3. Runs `python main.py` on port 8765
4. Flutter polls `http://127.0.0.1:8765/init` until `{"status": "initialized"}`

**Known issues:**
- `extractArchiveToDiskAsync` from `archive` package does NOT overwrite files.
  If the zip changes, old files persist. Fix: delete `%APPDATA%\Lupyther\velqi_backend\` before launching.
- The `python_app.zip` in `build/flutter_assets/assets/` may be stale if you
  modified `assets/python_app.zip` after building. Always rebuild AND copy:
  ```powershell
  cp assets/python_app.zip build/windows/x64/runner/Release/data/flutter_assets/assets/
  ```

**Endpoint test:**
```bash
curl -s http://127.0.0.1:8765/init
# Should return: {"status": "initialized", "progress": 100, "message": "Listo"}

curl -s "http://127.0.0.1:8765/stream?videoId=dQw4w9WgXcQ"
# Should return: {"playable": true, "audioFormats": [...]}
```

---

## 8. Other Known Issues

### DWM Crash on Windows Title Bar Color

In `theme_controller.dart`, the `setWindowsTitleBarColor` method uses a platform
channel that can crash if called before the window is fully initialized. Fix is
already applied (try-catch wrapping).

### Backend Startup Time

The Python backend takes 5-15 seconds to initialize (importing yt-dlp).
During this time, the app shows a loading banner. If the backend fails to start,
the app shows a network error.

### No Desktop Position Events

Before the polling timer was added, `just_audio_windows` did not fire enough
`playbackEventStream` events to update the seekbar. The position would stay at
0:00 even while audio was playing. The 250ms polling timer fixes this.

---

## 9. Scripts Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/build_desktop.ps1` | Full automated Windows build with all fixes | `powershell -File scripts/build_desktop.ps1` |
| `scripts/build_android_full.ps1` | Full Android APK build | `powershell -File scripts/build_android_full.ps1` |
| `scripts/create_portable.ps1` | Creates portable zip for distribution | `powershell -File scripts/create_portable.ps1` |
| `scripts/backup_desktop_state.ps1` | Backs up working Release dir + source snapshots | `powershell -File scripts/backup_desktop_state.ps1` |

All scripts are in the project root under `scripts/`.

---

## 10. How to Test

### Quick Desktop Test

```powershell
# 1. Kill any running instance
taskkill //f //im velqi.exe 2>$null; taskkill //f //im python.exe 2>$null

# 2. Clean old backend (forces re-extraction)
rm -rf "$env:APPDATA\Lupyther\velqi_backend" 2>$null

# 3. Launch
cd build/windows/x64/runner/Release
.\velqi.exe

# 4. Wait 5-15 seconds for backend to initialize
# 5. Play a song — verify:
#    - Audio plays (you hear music)
#    - Seekbar progresses (moves left to right)
#    - Player opens when clicking mini player
#    - Back button collapses player
#    - Skip next/prev work
#    - Volume slider works
```

### Verify Backend Independently

```bash
# Check if backend is running
curl -s http://127.0.0.1:8765/init

# Test search
curl -s "http://127.0.0.1:8765/search?query=never+gonna+give+you+up" | python -m json.tool

# Test stream
curl -s "http://127.0.0.1:8765/stream?videoId=dQw4w9WgXcQ" | python -c "import sys,json; d=json.load(sys.stdin); print('playable:', d.get('playable'), 'formats:', len(d.get('audioFormats',[])))"
```

### Debug Log

The app writes debug output to stderr. To capture:
```powershell
.\velqi.exe 2> velqi_stderr.log
```

### Check DLL Dependencies

```powershell
# Verify all plugin DLLs are present
ls *.dll | Select-Object Name, Length, LastWriteTime

# Check if a specific DLL is 64-bit
file vcruntime140.dll
# Must show: PE32+ executable (x86-64)
```

---

## Troubleshooting Flowchart

```
App won't start?
  → Check vcruntime140.dll is 64-bit (file command)
  → Check all *_plugin.dll files are present in Release/
  → Check data/app.so exists (not in root!)

App starts but music doesn't play?
  → Check Python is installed: python --version
  → Check yt-dlp is installed: pip install yt-dlp
  → Check backend starts: curl http://127.0.0.1:8765/init
  → Delete old backend: rm -rf %APPDATA%\Lupyther\velqi_backend
  → Check python_app.zip in data/flutter_assets/assets/ is current

Seekbar doesn't move?
  → The 250ms polling timer should fix this
  → Verify _desktopPositionTimer is active in audio_handler.dart
  → Check that playbackState is being updated (add temporary print)

Player UI is broken?
  → Check SlidingUpPanel in home.dart
  → Check playerPanelMinHeight in player_controller.dart
  → Check isDraggable settings for desktop
  → The _PlayerBackButton should collapse the panel

Backend returns 404?
  → The python_app.zip is stale — rebuild and copy to flutter_assets
  → Or delete %APPDATA%\Lupyther\velqi_backend and restart
```

---

## Git State (as of 2026-08-22)

Current uncommitted changes (the desktop fix):
```
 M assets/python_app.zip            ← Backend (no custom headers needed)
 M assets/python_app.zip.hash
 M lib/services/audio_handler.dart  ← Removed media_kit, added position polling
 M lib/ui/utils/theme_controller.dart ← DWM crash fix
 M pubspec.lock                     ← just_audio_windows dependency
 M pubspec.yaml                     ← just_audio_windows replaces media_kit
 M windows/runner/resources/app_icon.ico ← Updated logo
```

**DO NOT commit until the player UI is fixed and tested.**
