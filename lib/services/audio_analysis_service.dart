import 'dart:math' as math;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';

import '../utils/helper.dart';
import 'android_visualizer.dart';
import 'audio_handler.dart';
import 'permission_service.dart';
import 'wasapi_loopback.dart';

/// REAL audio analysis for the Velqi player (desktop AND Android).
///
/// Each platform taps the actual output mix — the signal the user is
/// literally hearing:
///   * Windows: WASAPI loopback via dart:ffi (capture isolate), RMS per
///     ~11.6 ms window + energy-flux beat detection.
///   * Android: the platform [Visualizer] class (session 0 = output mix)
///     delivers real waveform bytes over an EventChannel; [AndroidVisualizer]
///     runs the SAME RMS + energy-flux detector.
///
/// This service normalizes and smooths the frames for the UI:
///
///   * [level]  — REAL loudness (0..1, adaptively normalized to the recent
///                peak so it looks right at any system volume).
///   * history  — rolling window of real samples → the circular wave ring
///                around the album art is a REAL oscilloscope of the last
///                ~1.3 s of music (drums show as real spikes).
///   * beat     — REAL onsets: every detected kick/drum hit bumps [beatCount]
///                and stamps [lastBeatAt]; the play/pause button pulses on
///                genuine hits, not a fake clock.
///
/// If the capture can't start (no permission, unusual device), `hasRealData`
/// stays false and the UI falls back to the music-clock animation — never
/// broken, just less alive.
class AudioAnalysisService extends GetxService {
  /// Display loudness 0..1 (smoothed, attack-fast / release-soft).
  double _level = 0;
  double _raw = 0;

  /// Adaptive peak follower (normalizes any system volume into 0..1).
  double _peak = 0.08;

  /// Rolling history of real samples (oldest first).
  static const int _histMax = 56;
  final List<double> _hist = [];

  DateTime _lastBeatAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _beatCount = 0;
  int _frames = 0;
  int _logged = 0;
  bool _captureAlive = false;

  /// True once REAL samples are flowing (UI switches off the fallback).
  final hasRealData = false.obs;

  WasapiLoopback? _capture;
  AndroidVisualizer? _androidCapture;
  int? _androidCaptureSessionId;

  /// Kept for shutdown paths (system tray quit) so the capture isolate dies
  /// with the app instead of leaking.
  void stopCapture() {
    _capture?.stop();
    _capture = null;
    _androidSessionSub?.cancel();
    _androidSessionSub = null;
    _androidCapture?.stop();
    _androidCapture = null;
    _androidCaptureSessionId = null;
    _captureAlive = false;
    hasRealData.value = false;
  }

  static AudioAnalysisService? tryFind() {
    try {
      return Get.find<AudioAnalysisService>();
    } catch (_) {
      return null;
    }
  }

  @override
  void onInit() {
    super.onInit();
    // ── PLATFORM LOCK (candadito) ────────────────────────────────────────
    // Real-audio analysis is DESKTOP-ONLY now. On Android the Visualizer
    // re-attaches to the audio session on EVERY song change and its
    // attach/detach glitches the audio pipeline (songs stuttered / paused /
    // jumped ahead at start), plus it captured frames forever (perf drain
    // on low-end devices). The Android beat UI (WaveRing ripples) simply
    // falls back to its static style when hasRealData stays false.
    if (GetPlatform.isWindows || GetPlatform.isLinux) {
      _startCapture();
    }
    // Android: intentionally NO capture.
  }

  Future<void> _startCapture() async {
    final cap = WasapiLoopback();
    cap.onError = (hr, msg) {
      if (hr != 0) {
        _captureAlive = false;
        hasRealData.value = false;
        printINFO('[ANALYZE] capture error (hr=0x${hr.toRadixString(16)}): $msg');
      } else {
        printINFO('[ANALYZE] $msg');
      }
    };
    cap.onFrame = (WasapiFrame f) => _onRealFrame(f.level, f.isBeat);
    _capture = cap;
    await cap.start();
  }

  /// REAL frames from the Android Visualizer EventChannel.
  ///
  /// Requires RECORD_AUDIO (visualization-only use) AND the ExoPlayer's
  /// audio session id — which only exists once playback starts. We therefore
  /// wait for AndroidAudioHandler's session stream and (re)start the
  /// capture whenever the session id appears or changes. Session 0 (output
  /// mix) fails on emulators (initCheck -3), so binding to the player's own
  /// session is what makes it work everywhere.
  StreamSubscription<int?>? _androidSessionSub;

  Future<void> _startAndroidCapture() async {
    final granted = await PermissionService.getMicrophonePermission();
    if (!granted) {
      printINFO('[ANALYZE] mic permission denied — music-clock fallback');
      return;
    }
    // The AudioHandler is created in main() right after this service, so it
    // may not be put yet — wait for it briefly.
    MyAudioHandler handler;
    while (true) {
      try {
        handler = Get.find<AudioHandler>() as MyAudioHandler;
        break;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    _androidSessionSub = handler.androidAudioSessionIdStream.listen((id) {
      if (id == null || id <= 0) return;
      _ensureAndroidCapture(id);
    });
    // Session may already exist (e.g. queue resumed from a previous run).
    final existing = handler.androidAudioSessionId;
    if (existing != null && existing > 0) {
      _ensureAndroidCapture(existing);
    }
  }

  void _ensureAndroidCapture(int sessionId) {
    if (_androidCapture != null) {
      // Same session: nothing to do. Different session (player re-created):
      // restart the capture bound to the new session.
      if (_androidCaptureSessionId == sessionId) return;
      _androidCapture!.stop();
      _androidCapture = null;
    }
    printINFO('[ANALYZE] binding Visualizer to session $sessionId');
    final cap = AndroidVisualizer();
    cap.onError = (code, msg) {
      if (code != 0) {
        _captureAlive = false;
        hasRealData.value = false;
        printINFO('[ANALYZE] android capture error ($code): $msg');
      } else {
        printINFO('[ANALYZE] $msg');
      }
    };
    cap.onFrame = (f) => _onRealFrame(f.level, f.isBeat);
    _androidCapture = cap;
    _androidCaptureSessionId = sessionId;
    cap.start(sessionId);
  }

  /// Real output-mix frame (shared by desktop + Android sources).
  void _onRealFrame(double rms, bool isBeat) {
    _captureAlive = true;

    // Adaptive normalization: decaying peak follower → same 0..1 feel at any
    // system/app volume, while quiet passages still read as quiet.
    _peak = math.max(_peak * 0.9997, rms);
    final target = ((rms - 0.004) / (_peak + 0.015)).clamp(0.0, 1.0);

    _raw = target;
    _level = target > _level
        ? _level + (target - _level) * 0.55 // fast attack
        : _level + (target - _level) * 0.16; // soft release

    _hist.add(target);
    if (_hist.length > _histMax) _hist.removeRange(0, _hist.length - _histMax);

    if (isBeat) {
      _lastBeatAt = DateTime.now();
      _beatCount++;
      if (_beatCount % 20 == 1) {
        printINFO(
            '[ANALYZE] REAL beat #$_beatCount (rms ${rms.toStringAsFixed(3)})');
      }
    }

    _frames++;
    if (_logged < 4) {
      _logged++;
      printINFO(
          '[ANALYZE] real sample: rms=${rms.toStringAsFixed(4)} → level ${target.toStringAsFixed(2)}');
    }
    if (_frames % 600 == 0) {
      printINFO(diag);
    }
    if (!hasRealData.value) hasRealData.value = true;
  }

  // ── Public surface for the UI (polled at 60 fps — no Rx churn) ─────────────

  /// Smoothed real loudness 0..1.
  double get level => _level;

  /// Latest raw sample 0..1.
  double get rawLevel => _raw;

  /// True while the loopback capture is alive and real samples arrived.
  bool get active => _captureAlive && _frames > 0;

  /// How many REAL beats were detected (increments on every onset).
  int get beatCount => _beatCount;

  /// When the last real beat fired.
  DateTime get lastBeatAt => _lastBeatAt;

  /// Resampled window of the last [count] real samples (oldest first).
  List<double> recentHistory(int count) {
    if (_hist.isEmpty) return List<double>.filled(count, 0);
    final out = List<double>.filled(count, 0);
    final n = _hist.length;
    for (var i = 0; i < count; i++) {
      final src = (i * n / count).floor().clamp(0, n - 1);
      out[i] = _hist[src];
    }
    return out;
  }

  /// Diagnostics snapshot for the dlog.
  String get diag =>
      '[ANALYZE] capture=$_captureAlive frames=$_frames beats=$_beatCount '
      'level=${_level.toStringAsFixed(2)} peak=${_peak.toStringAsFixed(3)}';
}
