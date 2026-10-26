import 'package:audio_service/audio_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/album.dart';
import '/models/artist.dart';
import '/ui/navigator.dart';
import '/ui/player/player_controller.dart';
import 'image_widget.dart';

/// PlayStation-store style horizontal carousel of "game cover" cards.
///
/// Supports MediaItem (song/video), Album and Artist items — each renders
/// as a physical-feeling box: big square art with rounded corners, a glass
/// light sweep on the top edge, a hairline rim, a deep drop shadow and a
/// subtle perspective tilt when hovered (desktop). The song currently
/// playing gets a live equalizer pill on its cover.
class CoverCardRow extends StatefulWidget {
  const CoverCardRow({
    super.key,
    required this.songs,
    this.onPlay,
    this.cardWidth = 158,
  });

  /// MediaItem / Album / Artist list. Typed loose on purpose — the library,
  /// the search overview and the search tabs all feed it.
  final List<dynamic> songs;

  /// Called with the tapped index for SONG items. If null, tapping a song
  /// pushes it to the queue (the search behavior). Albums/artists navigate
  /// to their screens regardless.
  final void Function(int index)? onPlay;

  final double cardWidth;

  @override
  State<CoverCardRow> createState() => _CoverCardRowState();
}

class _CoverCardRowState extends State<CoverCardRow> {
  final _scrollCtrl = ScrollController();
  bool _canLeft = false;
  bool _canRight = false;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_updateArrows);
    // Measure once the layout is done (maxScrollExtent needs a layout pass).
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  void _updateArrows() {
    if (!mounted || !_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    final canLeft = _scrollCtrl.offset > 12;
    final canRight = _scrollCtrl.offset < max - 12;
    if (canLeft != _canLeft || canRight != _canRight) {
      setState(() {
        _canLeft = canLeft;
        _canRight = canRight;
      });
    }
  }

  void _scrollPage(int direction) {
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    // ~4 cards per click.
    final step = (widget.cardWidth + 14) * 4 * direction;
    final target = (_scrollCtrl.offset + step).clamp(0.0, max);
    _scrollCtrl.animateTo(target,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.songs.isEmpty) return const SizedBox.shrink();
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      onHover: (_) => _updateArrows(),
      child: Stack(
        children: [
          // Mouse-draggable: Flutter desktop does NOT allow dragging lists
          // with the mouse by default — this behavior re-enables it, so the
          // shelf scrolls like a touch surface (plus the arrow buttons).
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.stylus,
                PointerDeviceKind.trackpad,
              },
            ),
            child: SizedBox(
              height: widget.cardWidth + 74,
              child: ListView.separated(
                controller: _scrollCtrl,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                itemCount: widget.songs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) => _CoverCard(
                  item: widget.songs[index],
                  width: widget.cardWidth,
                  onSongTap: widget.onPlay == null
                      ? () => Get.find<PlayerController>()
                          .pushSongToQueue(widget.songs[index])
                      : () => widget.onPlay!(index),
                ),
              ),
            ),
          ),
          // ── Shelf arrows (desktop, while hovering) ───────────────────
          if (GetPlatform.isDesktop) ...[
            _shelfArrow(
              visible: _hover && _canLeft,
              icon: Icons.chevron_left_rounded,
              alignment: Alignment.centerLeft,
              onTap: () => _scrollPage(-1),
            ),
            _shelfArrow(
              visible: _hover && _canRight,
              icon: Icons.chevron_right_rounded,
              alignment: Alignment.centerRight,
              onTap: () => _scrollPage(1),
            ),
          ],
        ],
      ),
    );
  }

  Widget _shelfArrow({
    required bool visible,
    required IconData icon,
    required Alignment alignment,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !visible,
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AnimatedOpacity(
              opacity: visible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 160),
              child: Material(
                color: cs.surface.withOpacity(0.85),
                shape: const CircleBorder(
                  side: BorderSide(color: Colors.white12, width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                elevation: 4,
                shadowColor: Colors.black54,
                child: InkWell(
                  onTap: onTap,
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(icon, size: 26, color: cs.onSurface),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverCard extends StatefulWidget {
  const _CoverCard({
    required this.item,
    required this.width,
    required this.onSongTap,
  });

  final dynamic item; // MediaItem | Album | Artist
  final double width;
  final VoidCallback onSongTap;

  @override
  State<_CoverCard> createState() => _CoverCardState();
}

class _CoverCardState extends State<_CoverCard> {
  bool _hover = false;

  String get _title {
    final item = widget.item;
    if (item is MediaItem) return item.title;
    if (item is Album) return item.title;
    if (item is Artist) return item.name;
    return "";
  }

  String get _subtitle {
    final item = widget.item;
    if (item is MediaItem) return item.artist ?? "NA";
    if (item is Album) {
      final artists = item.artists;
      if (artists == null || artists.isEmpty) return item.year ?? "";
      final first = artists.first['name']?.toString() ?? "";
      return artists.length > 1 && item.year != null
          ? "$first • ${item.year}"
          : first;
    }
    if (item is Artist) return item.subscribers ?? "";
    return "";
  }

  Widget _art(double size) {
    final item = widget.item;
    if (item is Album) return ImageWidget(size: size, album: item);
    if (item is Artist) return ImageWidget(size: size, artist: item);
    return ImageWidget(size: size, song: item as MediaItem);
  }

  void _handleTap() {
    final item = widget.item;
    if (item is Album) {
      Get.toNamed(ScreenNavigationSetup.albumScreen,
          id: ScreenNavigationSetup.id, arguments: (item, item.browseId));
    } else if (item is Artist) {
      Get.toNamed(ScreenNavigationSetup.artistScreen,
          id: ScreenNavigationSetup.id, arguments: [false, item]);
    } else {
      widget.onSongTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isSong = widget.item is MediaItem;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: _handleTap,
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── The "game box" ────────────────────────────────────────
              TweenAnimationBuilder<double>(
                tween: Tween(end: _hover ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) {
                  return Transform(
                    alignment: Alignment.center,
                    // Perspective + slight Y-tilt on hover: the box "leans"
                    // toward the cursor like a shelf game.
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0014)
                      ..rotateY(0.10 * t),
                    child: AnimatedScale(
                      scale: 1.0 + 0.05 * t,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: child,
                    ),
                  );
                },
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        // Deep floor shadow — the box sits ABOVE the shelf.
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Cover art
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: _art(widget.width),
                          ),
                        ),
                        // Glass light sweep + bottom darkening — sells the
                        // physical "printed cover" look.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.10),
                                    width: 1,
                                  ),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0x24FFFFFF),
                                      Color(0x05FFFFFF),
                                      Color(0x00000000),
                                      Color(0x33000000),
                                    ],
                                    stops: [0, 0.18, 0.55, 1],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Live "now playing" pill (songs only)
                        if (isSong)
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: _NowPlayingBadge(
                                songId: (widget.item as MediaItem).id),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Title
              Text(
                _title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              // Subtitle
              Text(
                _subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(
                  fontSize: 11.5,
                  color: cs.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// White pill with three live bars — shown on the cover of the song that is
/// currently playing.
class _NowPlayingBadge extends StatefulWidget {
  const _NowPlayingBadge({required this.songId});
  final String songId;

  @override
  State<_NowPlayingBadge> createState() => _NowPlayingBadgeState();
}

class _NowPlayingBadgeState extends State<_NowPlayingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final playing =
          Get.find<PlayerController>().currentSong.value?.id == widget.songId;
      if (!playing) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.65),
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                // Three bars bouncing out of phase.
                final phase = (_ctrl.value * 2 + i * 0.33) % 1.0;
                final h = 5.0 + 8.0 * (0.5 - (phase - 0.5).abs()) * 2;
                return Container(
                  width: 3,
                  height: h,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            );
          },
        ),
      );
    });
  }
}
