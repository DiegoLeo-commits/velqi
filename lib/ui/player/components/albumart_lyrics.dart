import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/player/components/lyrics_widget.dart';
import '/ui/player/player_controller.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/sleep_timer_bottom_sheet.dart';
import '../../widgets/songinfo_bottom_sheet.dart';

class AlbumArtNLyrics extends StatelessWidget {
  const AlbumArtNLyrics({super.key, required this.playerArtImageSize});
  final double playerArtImageSize;

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    final cs = Theme.of(context).colorScheme;
    return Obx(() => playerController.currentSong.value != null
        ? Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: cs.onSurface.withAlpha(25), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(60),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Stack(
                children: [
                  GestureDetector(
                    onLongPress: () {
                      showModalBottomSheet(
                        constraints: const BoxConstraints(maxWidth: 500),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(10.0)),
                        ),
                        isScrollControlled: true,
                        context: playerController
                            .homeScaffoldkey.currentState!.context,
                        barrierColor: Colors.transparent.withAlpha(100),
                        builder: (context) => SongInfoBottomSheet(
                          playerController.currentSong.value!,
                          calledFromPlayer: true,
                        ),
                      ).whenComplete(() => Get.delete<SongInfoController>());
                    },
                    onTap: () {
                      playerController.showLyrics();
                    },
                    onHorizontalDragEnd: (DragEndDetails details) {
                      if (playerController.showLyricsflag.isTrue) return;
                      if (details.primaryVelocity! < 0) {
                        playerController.next();
                      } else if (details.primaryVelocity! > 0) {
                        playerController.prev();
                      }
                    },
                    child: ImageWidget(
                      size: playerArtImageSize,
                      song: playerController.currentSong.value!,
                      isPlayerArtImage: true,
                    ),
                  ),
                  // Lyrics overlay
                  Obx(() => playerController.showLyricsflag.isTrue
                      ? InkWell(
                          onTap: () {
                            playerController.showLyrics();
                          },
                          child: Container(
                            height: playerArtImageSize,
                            width: playerArtImageSize,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.85),
                            ),
                            child: Stack(
                              children: [
                                LyricsWidget(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: playerArtImageSize / 3.5)),
                                IgnorePointer(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withOpacity(0.9),
                                          Colors.transparent,
                                          Colors.transparent,
                                          Colors.transparent,
                                          Colors.black.withOpacity(0.9),
                                        ],
                                        stops: const [0, 0.2, 0.5, 0.8, 1],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink()),
                  // Sleep timer badge
                  if (playerController.isSleepTimerActive.isTrue)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        height: 44,
                        width: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cs.onSurface.withOpacity(0.3),
                            width: 1.2,
                          ),
                          color: cs.surfaceContainerHighest.withAlpha(180),
                        ),
                        child: IconButton(
                          onPressed: () {
                            showModalBottomSheet(
                              constraints: const BoxConstraints(maxWidth: 500),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(10.0)),
                              ),
                              isScrollControlled: true,
                              context: playerController
                                  .homeScaffoldkey.currentState!.context,
                              barrierColor: Colors.transparent.withAlpha(100),
                              builder: (context) =>
                                  const SleepTimerBottomSheet(),
                            );
                          },
                          icon: Icon(
                            Icons.timer,
                            color: cs.onSurface,
                            size: 20,
                          ),
                          splashRadius: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          )
        : Container());
  }
}
