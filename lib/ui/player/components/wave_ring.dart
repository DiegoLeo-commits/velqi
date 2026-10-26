import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/audio_analysis_service.dart';
import '../player_controller.dart';
import 'music_clock.dart';

/// REAL circular equalizer rendered BEHIND the album art.
///
/// ~88 bars radiate outward around the art, each one fed by the rolling
/// window of REAL audio samples (mpv astats): the ring is literally the last
/// ~1.3 s of the music drawn in a circle — kicks and drums appear as real
/// spikes, quiet passages shrink the ring. A slow drift rotates the window
/// so the ring breathes clockwise like a living oscilloscope.
///
/// On every REAL beat (energy-flux onset from [AudioAnalysisService]) the
/// whole ring surges outward and glows, then relaxes.
///
/// Fallback: if no real samples are available (analysis off, or Android),
/// the same geometry is driven by the music clock so it still moves — but
/// when real data exists, everything here is genuine.
class WaveRing extends StatefulWidget {
  const WaveRing({super.key, required this.artSize});

  /// Size of the album art the ring surrounds.
  final double artSize;

  @override
  State<WaveRing> createState() => _WaveRingState();
}

class _WaveRingState extends State<WaveRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tick;
  final MusicTime _mt = MusicTime();
  DateTime _lastBeat = DateTime.fromMillisecondsSinceEpoch(0);
  int _seenBeats = -1;

  @override
  void initState() {
    super.initState();
    _tick = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    );
    // PLATFORM LOCK: Android has no real-audio analysis (see
    // AudioAnalysisService.onInit) — the ring is static there, so the
    // 60fps tick would be pure wasted repaints.
    if (!GetPlatform.isAndroid) {
      _tick.repeat();
    }
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GetX<PlayerController>(builder: (controller) {
      final playing =
          controller.buttonState.value == PlayButtonState.playing;
      final songId = controller.currentSong.value?.id;
      _mt.sync(controller.progressBarStatus.value.current, playing);

      // Real beat events (desktop analysis service / Android Visualizer).
      final analysis = AudioAnalysisService.tryFind();
      if (analysis != null && analysis.beatCount != _seenBeats) {
        _seenBeats = analysis.beatCount;
        _lastBeat = analysis.lastBeatAt;
      }

      // ── PLATFORM LOCK (candadito) ─────────────────────────────────────
      // ANDROID: the 88 radial bars overwhelm the smaller screens and read
      // as clutter. There the ring becomes minimal RIPPLE CIRCLES: a thin
      // base ring that breathes with the music's level, plus two soft
      // rings expanding outward on every REAL beat (Android Visualizer).
      // Desktop (Windows/Linux) keeps the full oscilloscope ring below —
      // both branches are fed by the same real-audio analysis service.
      if (GetPlatform.isAndroid) {
        // PLATFORM LOCK: no ring at all on Android — user decision after
        // testing (visual noise on small screens, and no analysis data
        // exists there anyway). Desktop keeps the oscilloscope ring.
        return const SizedBox.shrink();
      }

      return RepaintBoundary(
        child: AnimatedBuilder(
          animation: _tick,
          builder: (_, __) {
            final real = analysis != null && analysis.hasRealData.value;
            final now = DateTime.now();
            // Exaggerated bounce: strong surge on every real beat + a fast
            // decaying oscillation riding it (visible "rebote", not a fade).
            final dt = now.difference(_lastBeat).inMilliseconds;
            final base = math.exp(-dt / 110.0);
            final bounce = base * (1.0 + 0.35 * math.cos(dt * 0.028));
            final surge = bounce.clamp(0.0, 1.4);

            return CustomPaint(
              size: Size.square(widget.artSize + 96),
              painter: _WaveRingPainter(
                artSize: widget.artSize,
                samples: real
                    ? analysis.recentHistory(88)
                    : _clockSamples(now, playing, songId),
                playing: playing,
                surge: playing ? surge : 0.0,
                drift: _mt.now(playing) * 0.22,
                color: cs.onSurface,
              ),
            );
          },
        ),
      );
    });
  }

  /// Fallback samples from the music clock (no real data available).
  List<double> _clockSamples(DateTime now, bool playing, String? songId) {
    final t = _mt.now(playing);
    final out = List<double>.filled(88, 0);
    for (var i = 0; i < out.length; i++) {
      final w = 0.5 +
          0.5 * math.sin(t * 5.0 + i * 0.55) * (0.6 + 0.4 * (i % 3 == 0 ? 1 : 0.7));
      out[i] = playing ? (0.15 + 0.6 * w.clamp(0.0, 1.0)) : 0.06;
    }
    return out;
  }
}

class _WaveRingPainter extends CustomPainter {
  _WaveRingPainter({
    required this.artSize,
    required this.samples,
    required this.playing,
    required this.surge,
    required this.drift,
    required this.color,
  });

  final double artSize;
  final List<double> samples;
  final bool playing;
  final double surge;
  final double drift;
  final Color color;

  static const double _maxBar = 44.0; // exaggerated reach

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final inner = artSize / 2 + 10; // just outside the art edge
    final n = samples.length;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    // Slow clockwise drift of the sample window (living oscilloscope feel).
    for (var i = 0; i < n; i++) {
      // Punchy curve: mids get pushed up so quiet-to-loud contrast is strong.
      final v = math.pow(samples[i].clamp(0.0, 1.0), 0.78).toDouble();
      final len = 3.0 + _maxBar * v * (1.0 + 0.95 * surge);
      final angle = (i / n) * 2 * math.pi + drift;
      final dir = Offset(math.cos(angle), math.sin(angle));
      final from = center + dir * inner;
      final to = center + dir * (inner + len);

      paint.color = color.withValues(
        alpha: (0.12 + 0.40 * v * (0.5 + 0.5 * (1 - surge)) + 0.16 * surge)
            .clamp(0.0, 0.75),
      );
      canvas.drawLine(from, to, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveRingPainter oldDelegate) => true;
}
