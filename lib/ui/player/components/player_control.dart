import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '/services/audio_analysis_service.dart';
import '/ui/player/components/animated_play_button.dart';
import '/ui/widgets/sleep_timer_bottom_sheet.dart';
import '/ui/widgets/song_download_btn.dart';
import 'music_clock.dart';
import '../player_controller.dart';

/// Glassmorphism control panel for the full-screen player.
class PlayerControlWidget extends StatelessWidget {
  const PlayerControlWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isLight = Theme.of(context).brightness == Brightness.light;

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(isLight ? 0.6 : 0.34),
            border: Border.all(
              color: cs.outline.withOpacity(0.1),
              width: 0.7,
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Title + Artist ──────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Obx(() {
                          return Marquee(
                            delay: const Duration(milliseconds: 300),
                            duration: const Duration(seconds: 10),
                            id: "${playerController.currentSong.value}_title",
                            child: Text(
                              playerController.currentSong.value != null
                                  ? playerController.currentSong.value!.title
                                  : "NA",
                              style: tt.titleMedium?.copyWith(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 3),
                        Obx(() {
                          return Marquee(
                            delay: const Duration(milliseconds: 300),
                            duration: const Duration(seconds: 10),
                            id:
                                "${playerController.currentSong.value}_subtitle",
                            child: Text(
                              playerController.currentSong.value != null
                                  // artist is NULLABLE on MediaItem — some
                                  // random-selection songs carry no artist.
                                  // The old `artist!` threw "Null check
                                  // operator used on a null value" on every
                                  // rebuild for those tracks.
                                  ? (playerController.currentSong.value!.artist ??
                                      "NA")
                                  : "NA",
                              overflow: TextOverflow.ellipsis,
                              style: tt.labelSmall?.copyWith(
                                fontSize: 13.5,
                                color: cs.onSurface.withOpacity(0.55),
                                letterSpacing: -0.2,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Now-playing indicator: mini equalizer (music-clocked)
                  const _MiniEq(),
                ],
              ),
              const SizedBox(height: 18),

              // ── Progress Bar ────────────────────────────────────────────
              GetX<PlayerController>(builder: (controller) {
                return ProgressBar(
                  thumbRadius: 7,
                  barHeight: 5,
                  baseBarColor: cs.outline.withOpacity(0.16),
                  bufferedBarColor: cs.outline.withOpacity(0.3),
                  progressBarColor: cs.primary,
                  thumbColor: cs.primary,
                  thumbGlowRadius: 14,
                  timeLabelLocation: TimeLabelLocation.sides,
                  timeLabelPadding: 6,
                  timeLabelTextStyle: tt.titleMedium?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withOpacity(0.55),
                  ),
                  progress: controller.progressBarStatus.value.current,
                  total: controller.progressBarStatus.value.total,
                  buffered: controller.progressBarStatus.value.buffered,
                  onSeek: controller.seek,
                );
              }),
              const SizedBox(height: 20),

              // ── Main Controls Row (prev, play, next) ────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ctrlChip(
                    icon: Icons.skip_previous_rounded,
                    size: 30,
                    onPressed: () => playerController.prev(),
                    cs: cs,
                  ),
                  const _PulsePlayButton(),
                  _nextChip(playerController, cs),
                ],
              ),
              const SizedBox(height: 18),

              // ── Secondary Controls Row (shuffle, fav, loop, download) ───
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Shuffle
                  Obx(() => _secBtn(
                        icon: Icons.shuffle_rounded,
                        active: playerController.isShuffleModeEnabled.value,
                        onPressed: playerController.toggleShuffleMode,
                        cs: cs,
                      )),
                  const SizedBox(width: 10),
                  // Favorite — pops when active
                  Obx(() => AnimatedScale(
                        scale: playerController.isCurrentSongFav.isTrue
                            ? 1.18
                            : 1.0,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutBack,
                        child: _secBtn(
                          icon: playerController.isCurrentSongFav.isFalse
                              ? Icons.favorite_outline_rounded
                              : Icons.favorite_rounded,
                          customColor:
                              playerController.isCurrentSongFav.isFalse
                                  ? null
                                  : Colors.redAccent,
                          active: playerController.isCurrentSongFav.value,
                          onPressed: playerController.toggleFavourite,
                          cs: cs,
                        ),
                      )),
                  const SizedBox(width: 10),
                  // Loop
                  Obx(() => _secBtn(
                        icon: Icons.repeat_rounded,
                        active: playerController.isLoopModeEnabled.value,
                        onPressed: playerController.toggleLoopMode,
                        cs: cs,
                      )),
                  const SizedBox(width: 10),
                  // Download
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: cs.outline.withOpacity(0.12),
                        width: 0.7,
                      ),
                    ),
                    child: SongDownloadButton(calledFromPlayer: true),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Widgets row: lyrics · sleep timer ───────────────────────
              // (The queue has its own slide-up panel at the bottom of the
              // player, so a separate queue button here would be redundant.)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Obx(() => _widgetChip(
                        context: context,
                        icon: Icons.lyrics_outlined,
                        label: 'Letras',
                        active: playerController.showLyricsflag.value,
                        onTap: playerController.showLyrics,
                        cs: cs,
                      )),
                  Obx(() => _widgetChip(
                        context: context,
                        icon: Icons.timer_outlined,
                        label: 'Temporizador',
                        active: playerController.isSleepTimerActive.value,
                        onTap: () => _openSleepTimer(playerController),
                        cs: cs,
                      )),
                ],
              ),
              const SizedBox(height: 14),

              // ── Volume ──────────────────────────────────────────────────
              _volumeRow(playerController, context, cs, tt),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Opens the sleep timer bottom sheet.
void _openSleepTimer(PlayerController pc) {
  showModalBottomSheet(
    constraints: const BoxConstraints(maxWidth: 500),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    isScrollControlled: true,
    context: pc.homeScaffoldkey.currentState!.context,
    barrierColor: Colors.black87,
    builder: (_) => const SleepTimerBottomSheet(),
  );
}

/// Small glass action chip with icon + label (lyrics / queue / sleep timer).
Widget _widgetChip({
  required BuildContext context,
  required IconData icon,
  required String label,
  required bool active,
  required VoidCallback onTap,
  required ColorScheme cs,
}) {
  final isLight = Theme.of(context).brightness == Brightness.light;
  return Material(
    color: active
        ? cs.primaryContainer.withOpacity(isLight ? 0.5 : 0.35)
        : cs.surfaceContainerHighest.withOpacity(isLight ? 0.5 : 0.32),
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? cs.primary.withOpacity(0.35)
                : cs.outline.withOpacity(0.12),
            width: 0.7,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: active
                  ? cs.primary
                  : cs.onSurface.withOpacity(0.6),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withOpacity(active ? 0.95 : 0.7),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Compact volume row: mute toggle + slider + percentage.
Widget _volumeRow(
  PlayerController pc,
  BuildContext context,
  ColorScheme cs,
  TextTheme tt,
) {
  return Obx(() {
    final v = pc.volume.value;
    return Row(
      children: [
        InkWell(
          onTap: pc.mute,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              v == 0
                  ? Icons.volume_off_rounded
                  : v < 50
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
              size: 18,
              color: v == 0
                  ? cs.onSurface.withOpacity(0.4)
                  : cs.onSurface.withOpacity(0.7),
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: cs.primary,
              inactiveTrackColor: cs.outline.withOpacity(0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              thumbColor: cs.primary,
            ),
            child: Slider(
              value: (v / 100).clamp(0.0, 1.0),
              onChanged: (val) => pc.setVolume((val * 100).round()),
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '$v%',
            textAlign: TextAlign.end,
            style: tt.labelSmall?.copyWith(
              fontSize: 11,
              color: cs.onSurface.withOpacity(0.55),
            ),
          ),
        ),
      ],
    );
  });
}

/// Circular glass chip used for prev/next.
Widget _ctrlChip({
  required IconData icon,
  required double size,
  VoidCallback? onPressed,
  required ColorScheme cs,
}) {
  return Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: cs.surfaceContainerHighest.withOpacity(0.55),
      border: Border.all(color: cs.outline.withOpacity(0.12), width: 0.7),
    ),
    child: IconButton(
      icon: Icon(icon, size: size),
      color: onPressed == null
          ? cs.onSurface.withOpacity(0.2)
          : cs.onSurface,
      onPressed: onPressed,
      splashRadius: 24,
    ),
  );
}

Widget _nextChip(PlayerController playerController, ColorScheme cs) {
  return Obx(() {
    final isLastSong = playerController.currentQueue.isEmpty ||
        (!(playerController.isShuffleModeEnabled.isTrue ||
                playerController.isQueueLoopModeEnabled.isTrue) &&
            (playerController.currentQueue.last.id ==
                playerController.currentSong.value?.id));
    return _ctrlChip(
      icon: Icons.skip_next_rounded,
      size: 30,
      onPressed: isLastSong ? null : () => playerController.next(),
      cs: cs,
    );
  });
}

/// Secondary control button (shuffle/fav/loop) — glass pill, highlight on.
Widget _secBtn({
  required IconData icon,
  required bool active,
  required VoidCallback onPressed,
  required ColorScheme cs,
  Color? customColor,
}) {
  final color = customColor ??
      (active ? cs.onSurface : cs.onSurface.withOpacity(0.4));
  return AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    decoration: BoxDecoration(
      color: active
          ? cs.primaryContainer.withOpacity(0.4)
          : cs.surfaceContainerHighest.withOpacity(0.35),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: active
            ? cs.primary.withOpacity(0.3)
            : cs.outline.withOpacity(0.1),
        width: 0.7,
      ),
    ),
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      color: color,
      splashRadius: 18,
      constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
    ),
  );
}

/// Big gradient play/pause button that PULSES TO THE REAL MUSIC.
///
/// Primary driver: REAL beat detection from [AudioAnalysisService] — every
/// energy-flux onset (an actual kick/drum hit in the audio) fires the rings
/// and the micro-pump, and the button's glow breathes with the REAL loudness.
/// Fallback (no real samples — analysis unavailable): the music-clock phase
/// keeps the pulse alive so the button never goes dead.
class _PulsePlayButton extends StatefulWidget {
  const _PulsePlayButton();

  @override
  State<_PulsePlayButton> createState() => _PulsePlayButtonState();
}

class _PulsePlayButtonState extends State<_PulsePlayButton>
    with SingleTickerProviderStateMixin {
  // 60 fps tick only; the motion itself is music-driven.
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
    )..repeat();
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GetX<PlayerController>(
      builder: (controller) {
        final playing =
            controller.buttonState.value == PlayButtonState.playing;
        _mt.sync(controller.progressBarStatus.value.current, playing);
        final songId = controller.currentSong.value?.id;

        // Real beat events (desktop analysis service).
        final analysis = AudioAnalysisService.tryFind();
        if (analysis != null && analysis.beatCount != _seenBeats) {
          _seenBeats = analysis.beatCount;
          _lastBeat = analysis.lastBeatAt;
        }

        return AnimatedBuilder(
          animation: _tick,
          builder: (_, __) {
            final now = DateTime.now();
            final real = analysis != null && analysis.hasRealData.value;
            final level = real ? analysis.level : 0.0;

            double pump, glow, ringT1, ringT2;
            if (playing) {
              if (real) {
                // REAL beat: rings fire on detected onsets.
                final dt = now.difference(_lastBeat).inMilliseconds;
                final p1 = (dt / 340.0).clamp(0.0, 1.0); // main ring life
                final p2 = ((dt - 140) / 340.0).clamp(0.0, 1.0); // echo ring
                pump = math.exp(-dt / 80.0);
                ringT1 = Curves.easeOut.transform(p1);
                ringT2 = p2 < 1.0 ? Curves.easeOut.transform(p2) : -1.0;
                glow = 0.30 + level * 0.24 + pump * 0.30;
              } else {
                // Fallback: music-clocked phase.
                final t = _mt.now(playing);
                final phase = MusicClock.beatPhase(
                  positionSec: t,
                  songId: songId,
                );
                pump = MusicClock.beatEnvelope(phase, sharpness: 7);
                ringT1 = phase;
                ringT2 = (phase + 0.5) % 1;
                glow = 0.30 + 0.24 * pump;
              }
            } else {
              pump = 0;
              ringT1 = -1;
              ringT2 = -1;
              glow = 0.30;
            }

            return SizedBox(
              width: 86,
              height: 86,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (ringT2 >= 0)
                    _beatRing(cs.primary, t: ringT2, maxOpacity: 0.22),
                  if (ringT1 >= 0)
                    _beatRing(cs.primary, t: ringT1, maxOpacity: 0.6),
                  // Button body — micro-pump on every (real) beat.
                  Transform.scale(
                    scale: 1 + 0.08 * pump,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            cs.primary,
                            cs.primary.withOpacity(0.75),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withOpacity(glow.clamp(0.0, 0.85)),
                            blurRadius: 20 + 18 * pump,
                            spreadRadius: 1 + 2 * pump,
                          ),
                        ],
                      ),
                      child: AnimatedPlayButton(
                        key: const Key("playButton"),
                        iconSize: 36,
                        color: cs.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// One ring that expands + fades across a single beat span.
  Widget _beatRing(Color color,
      {required double t, required double maxOpacity}) {
    final size = 74 + 56 * t;
    final opacity =
        maxOpacity * math.pow((1 - t).clamp(0.0, 1.0), 1.6).toDouble();
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withOpacity(opacity),
            width: 1.8,
          ),
        ),
      ),
    );
  }
}

/// Animated 3-bar equalizer shown next to the title — REAL audio level
/// when the analysis service is flowing (three slices of the real sample
/// window), music-clocked fallback otherwise. Freezes when paused.
class _MiniEq extends StatefulWidget {
  const _MiniEq();

  @override
  State<_MiniEq> createState() => _MiniEqState();
}

class _MiniEqState extends State<_MiniEq>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tick;
  final MusicTime _mt = MusicTime();

  @override
  void initState() {
    super.initState();
    _tick = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..repeat();
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

      final analysis = AudioAnalysisService.tryFind();
      final real = analysis != null && analysis.hasRealData.value;

      return AnimatedBuilder(
        animation: _tick,
        builder: (_, __) {
          List<double> amps;
          if (playing && real) {
            // Real slices of the live sample window (older → newer).
            final hist = analysis.recentHistory(24);
            amps = [
              (hist[2] * 1.15).clamp(0.1, 1.0),
              (hist[12] * 1.15).clamp(0.1, 1.0),
              (hist[22] * 1.15).clamp(0.1, 1.0),
            ];
          } else {
            final t = _mt.now(playing);
            final phase = MusicClock.beatPhase(positionSec: t, songId: songId);
            final beat =
                playing ? MusicClock.beatEnvelope(phase, sharpness: 4) : 0.0;
            amps = [
              playing ? _amp(t, 0.0, beat) : 0.22,
              playing ? _amp(t, 0.5, beat) : 0.22,
              playing ? _amp(t, 1.0, beat) : 0.22,
            ];
          }
          return SizedBox(
            width: 18,
            height: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _bar(cs, amps[0]),
                _bar(cs, amps[1]),
                _bar(cs, amps[2]),
              ],
            ),
          );
        },
      );
    });
  }

  double _amp(double t, double barPhase, double beat) {
    final w = 0.5 + 0.5 * math.sin(t * 6.5 + barPhase * math.pi);
    return (0.25 + 0.75 * w * (0.35 + 0.65 * beat)).clamp(0.12, 1.0);
  }

  Widget _bar(ColorScheme cs, double h) {
    return Container(
      width: 3,
      height: 16 * h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        color: h > 0.3 ? cs.primary : cs.onSurface.withOpacity(0.25),
      ),
    );
  }
}
