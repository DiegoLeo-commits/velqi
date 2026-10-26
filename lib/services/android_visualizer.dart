import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

/// REAL system-audio capture on Android via the platform [Visualizer] class.
///
/// Android has no WASAPI loopback, so we use the framework's `Visualizer`
/// with session 0 (the audio output mix) — the Android analog of the desktop
/// loopback: the actual mix the user is hearing right now. The native side
/// (MainActivity) delivers raw 8-bit centered waveform bytes ~40/s over an
/// EventChannel; this service computes the RMS of each window and runs the
/// SAME energy-flux beat detection as the desktop isolate, so the wave ring
/// and play/pause pulse match the real music on both platforms.
///
/// Falls back silently: if the permission is missing or the device/emulator
/// can't provide waveform data, no frames are emitted and the UI keeps using
/// the music-clock fallback — never broken, just less alive.
class AndroidVisualizer {
  EventChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  bool _starting = false;
  bool _disposed = false;

  late void Function(WasapiFrameLike frame) onFrame;
  late void Function(int code, String message) onError;

  // Beat detector state — identical math to the desktop isolate:
  // energy flux over a running average, with a cooldown.
  var _avgEnergy = 0.0;
  var _lastBeat = DateTime.fromMillisecondsSinceEpoch(0);
  var _acc = 0.0;
  var _accCount = 0;
  static const _windowFrames = 1024; // bytes per RMS window (half of 2048)

  // The Android waveform (8-bit centered bytes) reads quieter than the
  // float32 WASAPI mix that desktop uses, so bars/pump look tamer. A fixed
  // gain brings Android to the same visual energy — calibrated so the ring
  // and play button bounce exactly as hard as on desktop.
  static const _gain = 3.2;

  /// [sessionId] is the Android audio session id of the player that is
  /// actually reproducing (ExoPlayer's). Binding the Visualizer to that
  /// session works on every device INCLUDING emulators, while session 0
  /// (output mix) fails on BlueStacks with initCheck -3.
  Future<void> start(int sessionId) async {
    if (_starting || _disposed) return;
    _starting = true;
    try {
      _channel = const EventChannel('com.velqi.app/visualizer');
      _sub = _channel!.receiveBroadcastStream(sessionId).listen(
            _onWaveform,
            onError: (Object e) {
              onError(-1, 'channel error: $e');
            },
            onDone: () {
              onError(0, 'capture stopped');
            },
          );
      // The stream opens asynchronously; the native side starts delivering
      // waveform bytes once onListen fires.
    } catch (e) {
      onError(-1, 'start failed: $e');
    } finally {
      _starting = false;
    }
  }

  void _onWaveform(dynamic raw) {
    // Android waveform is a byte list (0..255, 128 = silence center).
    if (raw is! List || raw.isEmpty) return;
    final n = raw.length;
    double sumSq = 0;
    for (final b in raw) {
      final v = ((b as num).toDouble() - 128.0) / 128.0;
      sumSq += v * v;
      _acc += v * v;
      _accCount++;
    }

    final rms = (math.sqrt(sumSq / n) * _gain).clamp(0.0, 1.0);

    // Energy-flux beat detection over ~1024-byte windows — mirrors the
    // desktop isolate: e = rms^2, running average, flux over threshold.
    // Slightly MORE sensitive than desktop on purpose (low threshold,
    // shorter cooldown) so vocals/soft hits register too, matching the
    // desktop "exaggerated" calibration.
    if (_accCount >= _windowFrames) {
      final e = _acc / _accCount;
      _avgEnergy = _avgEnergy * 0.93 + e * 0.07;
      final flux = e - _avgEnergy;
      final now = DateTime.now();
      final isBeat = flux > _avgEnergy * 0.22 + 0.00030 &&
          now.difference(_lastBeat).inMilliseconds > 125;
      if (isBeat) _lastBeat = now;
      onFrame(WasapiFrameLike(rms, isBeat));
      _accCount = 0;
      _acc = 0.0;
    } else {
      // Keep the UI moving on light frames too — throttle to ~40/s max
      // without the beat decision.
      onFrame(WasapiFrameLike(rms, false));
    }
  }

  void stop() {
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    _channel = null;
  }
}

/// Lightweight frame carrier matching the desktop [WasapiFrame] shape so
/// AudioAnalysisService can consume both sources identically.
class WasapiFrameLike {
  WasapiFrameLike(this.level, this.isBeat);
  final double level; // linear RMS of the real output mix
  final bool isBeat;
}