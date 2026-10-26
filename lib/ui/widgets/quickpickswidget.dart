import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/quick_picks.dart';
import '../player/player_controller.dart';
import 'image_widget.dart';
import 'songinfo_bottom_sheet.dart';

/// Netflix-style horizontal carousel for Quick Picks.
/// Large horizontal cards with album art, song title, and artist.
class QuickPicksWidget extends StatelessWidget {
  const QuickPicksWidget(
      {super.key, required this.content, this.scrollController});
  final QuickPicks content;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    final size = MediaQuery.of(context).size;
    final cardWidth = size.width > 600 ? 340.0 : (size.width - 40);
    final artSize = size.width > 600 ? 100.0 : 80.0;

    return SizedBox(
      height: 300,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              content.title.toLowerCase().removeAllWhitespace.tr,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: Scrollbar(
              thickness: GetPlatform.isDesktop ? null : 0,
              controller: scrollController,
              child: ListView.separated(
                controller: scrollController,
                physics: const BouncingScrollPhysics(),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 4, right: 16),
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemCount: content.songList.length,
                itemBuilder: (_, item) {
                  return Listener(
                    onPointerDown: (PointerDownEvent event) {
                      if (event.buttons == kSecondaryMouseButton) {
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
                            content.songList[item],
                          ),
                        ).whenComplete(
                            () => Get.delete<SongInfoController>());
                      }
                    },
                    child: Container(
                      width: cardWidth,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surface
                            .withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.06),
                          width: 1,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: ClipRRect(
                          borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(12)),
                          child: ImageWidget(
                            song: content.songList[item],
                            size: artSize,
                          ),
                        ),
                        title: Text(
                          content.songList[item].title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium!
                              .copyWith(
                                fontSize: size.width > 600 ? 16 : 14,
                              ),
                        ),
                        subtitle: Text(
                          content.songList[item].artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium!
                              .copyWith(fontSize: 13),
                        ),
                        onTap: () {
                          playerController
                              .pushSongToQueue(content.songList[item]);
                        },
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
                            builder: (context) =>
                                SongInfoBottomSheet(content.songList[item]),
                          ).whenComplete(
                              () => Get.delete<SongInfoController>());
                        },
                        trailing: GetPlatform.isDesktop
                            ? IconButton(
                                splashRadius: 18,
                                onPressed: () {
                                  showModalBottomSheet(
                                    constraints:
                                        const BoxConstraints(maxWidth: 500),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(10.0)),
                                    ),
                                    isScrollControlled: true,
                                    context: playerController
                                        .homeScaffoldkey.currentState!.context,
                                    barrierColor:
                                        Colors.transparent.withAlpha(100),
                                    builder: (context) => SongInfoBottomSheet(
                                        content.songList[item]),
                                  ).whenComplete(
                                      () => Get.delete<SongInfoController>());
                                },
                                icon: const Icon(Icons.more_vert, size: 20),
                              )
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
