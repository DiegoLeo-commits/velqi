import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/songinfo_bottom_sheet.dart';
import '../player_controller.dart';
import 'albumart_lyrics.dart';
import 'backgroud_image.dart';
import 'wave_ring.dart';
import 'lyrics_switch.dart';
import 'player_control.dart';

/// Full-screen "Now Playing" view.
///
/// Immersive blurred artwork background, a glass top bar, the album art
/// framed in a slow rotating light ring, and the redesigned control panel.
class StandardPlayer extends StatelessWidget {
  const StandardPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final playerController = Get.find<PlayerController>();
    final cs = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bottomPad = Get.mediaQuery.padding.bottom;

    // Reserve enough space for: top bar (~80) + controls area (~400) + bottom padding
    double playerArtImageSize = size.width - 84;
    final controlsEstimate = 400.0;
    final topBarEstimate = playerController.showLyricsflag.value ? 80.0 : 128.0;
    final lyricsSwitchHeight = 30.0;
    final reservedHeight =
        topBarEstimate + lyricsSwitchHeight + controlsEstimate + bottomPad + 60;
    final spaceAvailableForArtImage = size.height - reservedHeight;
    playerArtImageSize = playerArtImageSize > spaceAvailableForArtImage
        ? (spaceAvailableForArtImage > 84 ? spaceAvailableForArtImage : 84)
        : playerArtImageSize;

    // Desktop/landscape: the art frame must also respect the window HEIGHT,
    // not just the width — on short windows a width-based size overflows the
    // column and visually breaks the whole player.
    final double landscapeArtSize = math.min(
      size.width * .29,
      math.max(120.0, size.height - 170),
    );

    return Stack(
      children: [
        BackgroudImage(
          key: Key("${playerController.currentSong.value?.id}_background"),
          cacheHeight: 480,
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26.0, sigmaY: 26.0),
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isLight
                          ? [
                              cs.surface.withOpacity(0.72),
                              cs.surface.withOpacity(0.88),
                              cs.surface,
                            ]
                          : [
                              cs.surface.withOpacity(0.6),
                              cs.surface.withOpacity(0.82),
                              cs.surface,
                            ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
              ),
              // Subtle top vignette for depth
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(isLight ? 0.08 : 0.3),
                          Colors.transparent,
                        ],
                        stops: const [0, 0.4],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: context.isLandscape
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: size.width * .45,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 90),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Center(
                            child: _ArtFrame(
                              size: landscapeArtSize,
                              child: AlbumArtNLyrics(
                                playerArtImageSize: landscapeArtSize,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: size.width * .48,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: 16,
                          right: 10,
                          bottom: bottomPad,
                        ),
                        // Scroll instead of overflowing when the window is
                        // too short to fit the control panel.
                        child: LayoutBuilder(builder: (context, constraints) {
                          return SingleChildScrollView(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight,
                              ),
                              child: const Center(child: PlayerControlWidget()),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    Obx(
                      () => playerController.showLyricsflag.value
                          ? SizedBox(height: size.height < 750 ? 60 : 80)
                          : SizedBox(height: size.height < 750 ? 98 : 118),
                    ),
                    Expanded(
                      // Open/close choreography: the art scales up and the
                      // controls rise in, driven by the panel's own slide
                      // position — opening the player feels like the card
                      // "blossoms" into the full screen.
                      child: Obx(() {
                        final slide = playerController.playerPanelSlide.value
                            .clamp(0.0, 1.0);
                        final t = Curves.easeOutCubic.transform(slide);
                        return Transform.scale(
                          scale: 0.90 + 0.10 * t,
                          child: Opacity(
                            opacity: t,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const LyricsSwitch(),
                                const SizedBox(height: 10),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 480),
                                  child: _ArtFrame(
                                    size: playerArtImageSize,
                                    child: AlbumArtNLyrics(
                                      playerArtImageSize: playerArtImageSize,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: 58 + bottomPad,
                      ),
                      child: Obx(() {
                        final slide = playerController.playerPanelSlide.value
                            .clamp(0.0, 1.0);
                        final t = Curves.easeOutCubic.transform(slide);
                        return Transform.translate(
                          offset: Offset(0, 34 * (1 - t)),
                          child: Opacity(
                            opacity: t,
                            child: Container(
                              constraints:
                                  const BoxConstraints(maxWidth: 500),
                              child: const PlayerControlWidget(),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
        ),
        if (!(context.isLandscape && GetPlatform.isMobile))
          Padding(
            padding: EdgeInsets.only(
              top: Get.mediaQuery.padding.top + 12,
              left: 14,
              right: 14,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Collapse button lives in home.dart's top Stack layer —
                // inside the panel subtree its clicks were unreachable.
                const SizedBox(width: 42, height: 42),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Obx(
                      () => Column(
                        children: [
                          const SizedBox(height: 6),
                          // "Playing from" pill
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withOpacity(
                                  isLight ? 0.6 : 0.4),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: cs.outline.withOpacity(0.12),
                                width: 0.7,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.queue_music_rounded,
                                  size: 14,
                                  color: cs.onSurface.withAlpha(170),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    () {
                                      final from = playerController
                                          .playinfrom.value;
                                      return from.typeString.isEmpty
                                          ? from.nameString
                                          : "${from.typeString} · ${from.nameString}";
                                    }(),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface.withAlpha(190),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _glassChip(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Material(
      color: cs.surfaceContainerHighest.withOpacity(isLight ? 0.65 : 0.42),
      shape: CircleBorder(
        side: BorderSide(color: cs.outline.withOpacity(0.14), width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, size: 22, color: cs.onSurface),
        ),
      ),
    );
  }
}

/// Frames the album art in a slow rotating light ring.
///
/// The ring glows subtly while paused and brightens while playing.
class _ArtFrame extends StatefulWidget {
  const _ArtFrame({required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  State<_ArtFrame> createState() => _ArtFrameState();
}

class _ArtFrameState extends State<_ArtFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // NOTE: no GetX wrapper here — nothing in this frame needs reactivity and
    // an empty GetX builder throws ("improper use of GetX") = the red error
    // card that appeared over the player. WaveRing handles its own state.
    return AnimatedBuilder(
      animation: _spin,
      builder: (_, __) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          // Clip.none: the WaveRing radiates OUTSIDE the art square — the
          // default hardEdge clip was cutting the entire ring out of view.
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
                  // ── REAL circular equalizer behind the art ──────────
                  // The old rotating light ring is gone: the ring around the
                  // cover is now the WaveRing — a live oscilloscope of the
                  // actual audio, pulsing on real beats.
                  SizedBox.expand(
                    child: WaveRing(artSize: widget.size),
                  ),
                  // Album art
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(17),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(80),
                          blurRadius: 30,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: widget.child,
                    ),
                  ),
                ],
              ),
        );
      },
    );
  }
}
