import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/discord_rpc_service.dart';
import '/ui/player/player_controller.dart';
import '../../widgets/discord_mark.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/mini_player_progress_bar.dart';
import 'animated_play_button.dart';

/// Floating mini player card.
///
/// Design language matches the bottom navigation bar: pure-black surfaces
/// with a single WHITE accent pill (the navbar's active tab is a white
/// circle — the mini player's play/pause echoes it with a white circle and
/// a black icon). The card is a FREE-FLOATING pill: no border, generous
/// margins on all sides and a double soft shadow, fully detached from the
/// navbar and hovering over the app content — the sliding panel behind it
/// is transparent (as is the player scaffold), so the content visibly
/// peeks around the card edges.
///
/// It is used as the SlidingUpPanel `collapsed` widget: the package shows it
/// only while the panel is collapsed and fades it out as the panel opens.
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer>
    with SingleTickerProviderStateMixin {
  late final PlayerController _pc;
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _pc = Get.find<PlayerController>();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    // Entrance: whenever a song ARRIVES (stopped -> playing), the card
    // springs up from below. The panel strip itself is transparent, so this
    // slide is what the user perceives as the mini player appearing —
    // without it the card popped in instantly. Only fires on the
    // null -> song transition: song -> song changes are handled by the
    // AnimatedSwitcher inside the card.
    String? lastSongId;
    ever<dynamic>(_pc.currentSong, (song) {
      if (!mounted) return;
      final String? id = song?.id as String?;
      if (song != null && lastSongId == null) {
        _entrance.forward(from: 0);
      }
      lastSongId = id;
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  // ── Palette (mirrors bottom_nav_bar.dart) ─────────────────────────────────
  // Navbar: barBg dark = #000000, card floats slightly above it.
  static const _darkCard = Color(0xFF101013);
  static const _lightCard = Color(0xFFF4F4F7); // same as navbar light bg

  @override
  Widget build(BuildContext context) {
    final pc = Get.find<PlayerController>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isLight = Theme.of(context).brightness == Brightness.light;

    // Obx keeps the card fully reactive: progress, title/artist and control
    // states update live even while the panel is collapsed.
    return Obx(() {
      return Container(
        height: pc.playerPanelMinHeight.value,
        width: double.infinity,
        // Transparent stage — the card below is what carries the visuals.
        color: Colors.transparent,
        // Generous margins on every side: the card floats fully detached —
        // no border, no edge, and a clear gap above the navbar below.
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
        // Entrance choreography: the card springs up + fades in whenever a
        // new song arrives (see [_MiniPlayerState]).
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
                parent: _entrance, curve: Curves.easeOutCubic)),
            child: Container(
          decoration: BoxDecoration(
            color: isLight ? _lightCard : _darkCard,
            borderRadius: BorderRadius.circular(20),
            // No hairline border — pure float. Two soft shadows give it
            // lift: one tight, one wide, so the card reads as hovering
            // OVER the content instead of sitting ON a surface.
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isLight ? 0.10 : 0.55),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(isLight ? 0.12 : 0.45),
                blurRadius: 26,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Progress line clipped to the card's rounded top ──
              MiniPlayerProgressBar(
                progressBarStatus: pc.progressBarStatus.value,
                progressBarColor:
                    Theme.of(context).progressIndicatorTheme.color ?? cs.onSurface,
              ),

              // ── Content row ──
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  // Animated song change: when the track changes, the old
                  // info fades out while the new one slides in from below.
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.35),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: pc.currentSong.value == null
                        // "Ghost" dock guard: the panel expands as soon as a song
                        // is tapped, but currentSong arrives only after the stream
                        // resolves. Show a loading hint instead of an empty bar.
                        ? KeyedSubtree(
                            key: const ValueKey('mini-loading'),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    "loading".tr,
                                    style: tt.bodySmall?.copyWith(
                                      color: cs.onSurface.withOpacity(0.55),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : KeyedSubtree(
                            key: ValueKey(
                                'mini-${pc.currentSong.value!.id}'),
                            child: Row(
                          children: [
                            // Album art with rounded corners
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _art(pc),
                            ),
                            const SizedBox(width: 12),

                            // Song info (tap to expand, swipe to skip)
                            Expanded(
                              child: GestureDetector(
                                onTap: () => pc.playerPanelController.open(),
                                onHorizontalDragEnd: (d) {
                                  if (d.primaryVelocity! < 0) pc.next();
                                  if (d.primaryVelocity! > 0) pc.prev();
                                },
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pc.currentSong.value?.title ?? "",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: tt.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          pc.currentSong.value?.artist ?? "",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: tt.bodySmall?.copyWith(
                                            color: cs.onSurface.withOpacity(0.5),
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      _statusChip(pc, cs, isLight),
                                    ],
                                  ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(width: 8),

                            // Controls — one shared 40px axis, perfectly centered
                            _controls(pc, cs, isLight),
                          ],
                        ),
                        ),
                ),
              ),
            ),
            ],
          ),
            ),
          ),
        ),
      );
    });
  }

  /// Live status chip next to the artist:
  ///  * Desktop  → Discord mark + "Atado a Discord" / "Sin Discord".
  ///  * Mobile   → connection dot + "En línea" / "Descargada" (no Discord —
  ///               the RPC integration does not exist on mobile clients).
  Widget _statusChip(PlayerController pc, ColorScheme cs, bool isLight) {
    if (!GetPlatform.isDesktop) {
      final url = pc.currentSong.value?.extras?['url']?.toString() ?? '';
      final offline = url.isNotEmpty && !url.contains('http');
      return _chip(
        label: offline ? "streamOffline".tr : "streamOnline".tr,
        dotColor: offline
            ? cs.onSurface.withOpacity(0.30)
            : const Color(0xFF22C55E),
        cs: cs,
        isLight: isLight,
      );
    }
    try {
      final linked = DiscordRpcService.instance.isLinked.value;
      return _chip(
        label: linked ? "discordLinked".tr : "discordNotLinked".tr,
        discordMark: true,
        cs: cs,
        isLight: isLight,
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _chip({
    required String label,
    required ColorScheme cs,
    required bool isLight,
    Color? dotColor,
    bool discordMark = false,
  }) {
    final linked = label == "discordLinked".tr;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(isLight ? 0.06 : 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (discordMark) ...[
            DiscordMark(
                size: 12,
                color: linked
                    ? const Color(0xFF5865F2)
                    : const Color(0xFF8A8A92)),
            const SizedBox(width: 4),
          ] else if (dotColor != null) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: dotColor),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
              color: cs.onSurface.withOpacity(0.65),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _art(PlayerController pc) {
    return pc.currentSong.value != null
        ? ImageWidget(size: 44, song: pc.currentSong.value!)
        : const SizedBox(width: 44, height: 44);
  }

  /// Uniform control row: prev / play / next / close.
  /// Every button lives on the same 40x40 hit box and vertical center line.
  Widget _controls(PlayerController pc, ColorScheme cs, bool isLight) {
    final isFirst = pc.currentQueue.isEmpty ||
        pc.currentQueue.first.id == pc.currentSong.value?.id;
    final isLast = pc.currentQueue.isEmpty ||
        (!(pc.isShuffleModeEnabled.isTrue || pc.isQueueLoopModeEnabled.isTrue) &&
            pc.currentQueue.last.id == pc.currentSong.value?.id);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _iconBtn(
          icon: Icons.skip_previous_rounded,
          onPressed: isFirst ? null : pc.prev,
          disabled: isFirst,
          cs: cs,
          dim: 0.75,
        ),
        _playButton(pc, cs, isLight),
        _iconBtn(
          icon: Icons.skip_next_rounded,
          onPressed: isLast ? null : pc.next,
          disabled: isLast,
          cs: cs,
          dim: 0.75,
        ),
        _iconBtn(
          icon: Icons.close_rounded,
          onPressed: pc.stopPlayback,
          faded: true,
          cs: cs,
        ),
      ],
    );
  }

  /// White circular play/pause — the navbar's active-pill accent, mirrored.
  /// Dark mode: white circle, black icon. Light mode: black circle, white icon.
  Widget _playButton(PlayerController pc, ColorScheme cs, bool isLight) {
    final pillBg = isLight ? Colors.black : Colors.white;
    final pillFg = isLight ? Colors.white : Colors.black;
    return Container(
      width: 40,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(shape: BoxShape.circle, color: pillBg),
      child: Center(
        child: AnimatedPlayButton(iconSize: 24, color: pillFg),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required VoidCallback? onPressed,
    required ColorScheme cs,
    bool disabled = false,
    bool faded = false,
    double dim = 1,
  }) {
    return SizedBox(
      width: 38,
      height: 40,
      child: IconButton(
        iconSize: 24,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 38, height: 40),
        splashRadius: 20,
        onPressed: faded && onPressed != null
            ? () {
                onPressed();
              }
            : onPressed,
        icon: Icon(
          icon,
          size: faded ? 18 : 24,
          color: disabled
              ? cs.onSurface.withOpacity(0.18)
              : faded
                  ? cs.onSurface.withOpacity(0.35)
                  : cs.onSurface.withOpacity(dim),
        ),
      ),
    );
  }
}
