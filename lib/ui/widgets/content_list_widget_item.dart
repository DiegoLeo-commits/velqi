import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../navigator.dart';
import 'image_widget.dart';

/// Netflix-style content card with large rounded art and title overlay.
class ContentListItem extends StatelessWidget {
  const ContentListItem(
      {super.key, required this.content, this.isLibraryItem = false});
  final dynamic content;
  final bool isLibraryItem;

  @override
  Widget build(BuildContext context) {
    final isAlbum = content.runtimeType.toString() == "Album";
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final cardWidth = size.width > 600 ? 150.0 : 130.0;
    final artSize = size.width > 600 ? 150.0 : 130.0;

    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: () {
        if (isAlbum) {
          Get.toNamed(ScreenNavigationSetup.albumScreen,
              id: ScreenNavigationSetup.id,
              arguments: (content, content.browseId));
          return;
        }
        Get.toNamed(ScreenNavigationSetup.playlistScreen,
            id: ScreenNavigationSetup.id,
            arguments: [content, content.playlistId]);
      },
      child: Container(
        width: cardWidth,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline.withAlpha(30), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album/Playlist art with rounded corners
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
              child: isAlbum
                  ? ImageWidget(size: artSize, album: content)
                  : content.isCloudPlaylist ||
                          !(content.playlistId == 'LIBRP' ||
                              content.playlistId == 'LIBFAV' ||
                              content.playlistId == 'SongsCache' ||
                              content.playlistId == 'SongDownloads')
                      ? SizedBox.square(
                          dimension: artSize,
                          child: Stack(
                            children: [
                              ImageWidget(size: artSize, playlist: content),
                              if (!content.isCloudPlaylist)
                                Align(
                                  alignment: Alignment.bottomRight,
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Container(
                                      height: 20,
                                      width: 20,
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(5),
                                        color: cs.surfaceContainerHighest,
                                      ),
                                      child: Center(
                                          child: Text("L",
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium!
                                                  .copyWith(fontSize: 12))),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : Container(
                          height: artSize,
                          width: artSize,
                          decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(11))),
                          child: Center(
                              child: Icon(
                            content.playlistId == 'LIBRP'
                                ? Icons.history
                                : content.playlistId == 'LIBFAV'
                                    ? Icons.favorite
                                    : content.playlistId == 'SongsCache'
                                        ? Icons.flight
                                        : Icons.download,
                            color: cs.onSurface.withAlpha(180),
                            size: 36,
                          ))),
            ),
            // Details section
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    content.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium!
                        .copyWith(fontSize: 12.5, height: 1.3),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isAlbum
                        ? isLibraryItem
                            ? ""
                            : "${content.artists[0]['name'] ?? ""}${content.year != null ? " • ${content.year}" : ""}"
                        : isLibraryItem
                            ? ""
                            : content.description ?? "",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium!
                        .copyWith(fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
