import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '/models/playling_from.dart';
import '/models/thumbnail.dart';
import '/ui/widgets/playlist_album_scroll_behaviour.dart';
import '../../../services/downloader.dart';
import '../../navigator.dart';
import '../../player/player_controller.dart';
import '../../widgets/create_playlist_dialog.dart';
import '../../widgets/loader.dart';
import '../../widgets/playlist_export_dialog.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/song_list_tile.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import '../../widgets/sort_widget.dart';
import 'playlist_screen_controller.dart';

/// Wraps content in a bordered container matching the app's design system.
Widget _borderedContainer({
  required BuildContext context,
  required Widget child,
  EdgeInsetsGeometry margin =
      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
  EdgeInsetsGeometry padding = const EdgeInsets.all(6),
  int alpha = 25,
  double radius = 10,
}) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    margin: margin,
    padding: padding,
    decoration: BoxDecoration(
      border: Border.all(color: cs.outline.withAlpha(alpha), width: 1),
      borderRadius: BorderRadius.circular(radius),
    ),
    child: child,
  );
}

class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tag = key.hashCode.toString();
    final playlistController =
        (Get.isRegistered<PlaylistScreenController>(tag: tag))
            ? Get.find<PlaylistScreenController>(tag: tag)
            : Get.put(PlaylistScreenController(), tag: tag);
    final size = MediaQuery.of(context).size;
    final playerController = Get.find<PlayerController>();
    final landscape = size.width > size.height;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification scrollInfo) {
          final scrollOffset = scrollInfo.metrics.pixels;

          if (landscape) {
            playlistController.scrollOffset.value = 0;
          } else {
            playlistController.scrollOffset.value = scrollOffset;
          }
          if (scrollOffset > 270 || (landscape && scrollOffset > 215)) {
            playlistController.appBarTitleVisible.value = true;
          } else {
            playlistController.appBarTitleVisible.value = false;
          }
          return true;
        },
        child: Stack(
          children: [
            // ── Background image with parallax ──────────────────────────────
            Obx(
              () => playlistController.isContentFetched.isTrue
                  ? Positioned(
                      top: landscape
                          ? 0
                          : -.25 * playlistController.scrollOffset.value,
                      right: landscape ? 0 : null,
                      child: Obx(() {
                        final opacityValue = 1 -
                            playlistController.scrollOffset.value /
                                (size.width - 100);
                        return Opacity(
                          opacity: opacityValue < 0 ||
                                  playlistController.isSearchingOn.isTrue &&
                                      !landscape
                              ? 0
                              : opacityValue,
                          child: DecoratedBox(
                            position: DecorationPosition.foreground,
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context).canvasColor,
                                  spreadRadius: 200,
                                  blurRadius: 100,
                                  offset: Offset(-size.height, 0),
                                ),
                                BoxShadow(
                                  color: Theme.of(context).canvasColor,
                                  spreadRadius: 200,
                                  blurRadius: 100,
                                  offset: Offset(
                                      0,
                                      landscape
                                          ? size.height
                                          : size.width + 80),
                                )
                              ],
                            ),
                            child: CachedNetworkImage(
                              imageUrl: Thumbnail(playlistController
                                      .playlist.value.thumbnailUrl)
                                  .extraHigh,
                              fit: landscape ? BoxFit.fitHeight : BoxFit.cover,
                              width: landscape ? null : size.width,
                              height: landscape ? size.height : size.width,
                            ),
                          ),
                        );
                      }))
                  : SizedBox(
                      height: size.width,
                      width: size.width,
                    ),
            ),

            // ── Foreground content ──────────────────────────────────────────
            Column(
              children: [
                // ── AppBar row ──────────────────────────────────────────────
                Container(
                  padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 10,
                      left: 10,
                      right: 10),
                  height: 80,
                  child: Center(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 50,
                          child: IconButton(
                            tooltip: "back".tr,
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.arrow_back_ios)),
                        ),
                        Expanded(
                          child: Obx(
                            () => Marquee(
                              delay: const Duration(milliseconds: 300),
                              duration: const Duration(seconds: 5),
                              id:
                                  "${playlistController.playlist.value.title.hashCode.toString()}_appbar",
                              child: Text(
                                playlistController.appBarTitleVisible.isTrue
                                    ? playlistController
                                        .playlist.value.title
                                    : "",
                                maxLines: 1,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          ),
                        ),
                        if (!playlistController
                                .playlist.value.isCloudPlaylist &&
                            playlistController.isDefaultPlaylist.isFalse)
                          SizedBox(
                            width: 50,
                            child: IconButton(
                              onPressed: () =>
                                  _showMoreOptions(context, playlistController),
                              icon: const Icon(Icons.more_vert)),
                          )
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Obx(
                        () => ScrollConfiguration(
                          behavior: PlaylistAlbumScrollBehaviour(),
                          child: ListView.builder(
                            addRepaintBoundaries: false,
                            padding: EdgeInsets.only(
                              top: playlistController.isSearchingOn.isTrue
                                  ? 0
                                  : landscape
                                      ? 150
                                      : 200,
                              bottom: 200,
                            ),
                            itemCount:
                                playlistController.songList.isEmpty ||
                                        playlistController
                                            .isContentFetched.isFalse
                                    ? 4
                                    : playlistController.songList.length + 3,
                            itemBuilder: (_, index) {
                              // ── Index 0: Action buttons row ────────────────
                              if (index == 0) {
                                return _borderedContainer(
                                  context: context,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: SizedBox(
                                    height: 40,
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          // Bookmark button
                                          Obx(() => (!playlistController
                                                  .playlist
                                                  .value
                                                  .isCloudPlaylist)
                                              ? const SizedBox.shrink()
                                              : IconButton(
                                                  tooltip: playlistController
                                                          .isAddedToLibrary
                                                          .isFalse
                                                      ? "addToLibrary".tr
                                                      : "removeFromLibrary".tr,
                                                  splashRadius: 10,
                                                  onPressed: () {
                                                    final add =
                                                        playlistController
                                                            .isAddedToLibrary
                                                            .isFalse;
                                                    playlistController
                                                        .addNremoveFromLibrary(
                                                            playlistController
                                                                .playlist.value,
                                                            add: add)
                                                        .then((value) {
                                                      if (!context.mounted) {
                                                        return;
                                                      }
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                              snackbar(
                                                        context,
                                                        value
                                                            ? add
                                                                ? "playlistBookmarkAddAlert"
                                                                    .tr
                                                                : "listBookmarkRemoveAlert"
                                                                    .tr
                                                            : "operationFailed"
                                                                .tr,
                                                        size:
                                                            SanckBarSize.MEDIUM,
                                                      ));
                                                    });
                                                  },
                                                  icon: Icon(
                                                    playlistController
                                                            .isAddedToLibrary
                                                            .isFalse
                                                        ? Icons.bookmark_add
                                                        : Icons.bookmark_added,
                                                    color: cs.onSurface,
                                                  ))),
                                          // Play button
                                          IconButton(
                                            tooltip: "play".tr,
                                            onPressed: () {
                                              playerController
                                                  .playPlayListSong(
                                                List<MediaItem>.from(
                                                    playlistController
                                                        .songList),
                                                0,
                                                playfrom: PlaylingFrom(
                                                  name: playlistController
                                                      .playlist.value.title,
                                                  type:
                                                      PlaylingFromType.PLAYLIST,
                                                ),
                                              );
                                            },
                                            icon: Icon(
                                              Icons.play_circle_filled,
                                              color: cs.onSurface,
                                            ),
                                          ),
                                          // Enqueue button
                                          IconButton(
                                            tooltip: "enqueueSongs".tr,
                                            onPressed: () {
                                              Get.find<PlayerController>()
                                                  .enqueueSongList(
                                                      playlistController
                                                          .songList.toList())
                                                  .whenComplete(() {
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(snackbar(
                                                    context,
                                                    "songEnqueueAlert".tr,
                                                    size:
                                                        SanckBarSize.MEDIUM,
                                                  ));
                                                }
                                              });
                                            },
                                            icon: Icon(
                                              Icons.merge,
                                              color: cs.onSurface,
                                            ),
                                          ),
                                          // Shuffle button
                                          IconButton(
                                            tooltip: "shuffle".tr,
                                            onPressed: () {
                                              final songsToplay =
                                                  List<MediaItem>.from(
                                                      playlistController
                                                          .songList);
                                              songsToplay.shuffle();
                                              songsToplay.shuffle();
                                              playerController
                                                  .playPlayListSong(
                                                songsToplay,
                                                0,
                                                playfrom: PlaylingFrom(
                                                  name: playlistController
                                                      .playlist
                                                      .value
                                                      .title,
                                                  type:
                                                      PlaylingFromType.PLAYLIST,
                                                ),
                                              );
                                            },
                                            icon: Icon(
                                              Icons.shuffle,
                                              color: cs.onSurface,
                                            ),
                                          ),
                                          // Download button
                                          GetX<Downloader>(
                                              builder: (controller) {
                                            final id = playlistController
                                                .playlist.value.playlistId;
                                            return IconButton(
                                              tooltip:
                                                  "downloadPlaylist".tr,
                                              onPressed: () {
                                                if (playlistController
                                                    .isDownloaded.isTrue) {
                                                  return;
                                                }
                                                controller.downloadPlaylist(
                                                    id,
                                                    playlistController
                                                        .songList.toList());
                                              },
                                              icon: playlistController
                                                      .isDownloaded.isTrue
                                                  ? Icon(Icons.download_done,
                                                      color: cs.onSurface)
                                                  : controller
                                                              .playlistQueue
                                                              .containsKey(
                                                                  id) &&
                                                          controller
                                                                  .currentPlaylistId
                                                                  .toString() ==
                                                              id
                                                      ? Stack(
                                                          children: [
                                                            Center(
                                                                child: Text(
                                                              "${controller.playlistDownloadingProgress.value}/${playlistController.songList.length}",
                                                              style: Theme.of(
                                                                      context)
                                                                  .textTheme
                                                                  .titleMedium!
                                                                  .copyWith(
                                                                      fontSize:
                                                                          10,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold),
                                                            )),
                                                            const Center(
                                                                child:
                                                                    LoadingIndicator(
                                                              dimension: 30,
                                                            ))
                                                          ],
                                                        )
                                                      : controller
                                                              .playlistQueue
                                                              .containsKey(id)
                                                          ? const Stack(
                                                              children: [
                                                                Center(
                                                                    child: Icon(
                                                                  Icons
                                                                      .hourglass_bottom,
                                                                  size: 20,
                                                                )),
                                                                Center(
                                                                    child:
                                                                        LoadingIndicator(
                                                                  dimension: 30,
                                                                ))
                                                              ],
                                                            )
                                                          : Icon(
                                                              Icons.download,
                                                              color:
                                                                  cs.onSurface),
                                            );
                                          }),
                                          if (playlistController
                                              .isAddedToLibrary.isTrue)
                                            IconButton(
                                              tooltip:
                                                  "syncPlaylistSongs".tr,
                                              onPressed: () {
                                                playlistController
                                                    .syncPlaylistSongs();
                                              },
                                              icon: Icon(Icons.cloud_sync,
                                                  color: cs.onSurface),
                                            ),
                                          if (playlistController
                                              .playlist.value.isCloudPlaylist)
                                            IconButton(
                                              tooltip: "sharePlaylist".tr,
                                              visualDensity:
                                                  const VisualDensity(
                                                vertical: -3,
                                              ),
                                              splashRadius: 10,
                                              onPressed: () {
                                                final content =
                                                    playlistController
                                                        .playlist.value;
                                                final isPlaylistIdPrefixAvlbl =
                                                    content.playlistId
                                                            .substring(
                                                                0, 2) ==
                                                        "VL";
                                                String url =
                                                    "https://youtube.com/playlist?list=";

                                                url = isPlaylistIdPrefixAvlbl
                                                    ? url +
                                                        content.playlistId
                                                            .substring(2)
                                                    : url +
                                                        content.playlistId;
                                                Share.share(url);
                                              },
                                              icon: Icon(
                                                Icons.share,
                                                size: 20,
                                                color: cs.onSurface,
                                              ),
                                            ),
                                          // Export button
                                          IconButton(
                                            onPressed: () {
                                              showDialog(
                                                context: context,
                                                builder: (dialogContext) =>
                                                    PlaylistExportDialog(
                                                  controller:
                                                      playlistController,
                                                  parentContext: context,
                                                ),
                                              );
                                            },
                                            icon: Icon(Icons.file_upload,
                                                color: cs.onSurface),
                                            tooltip: "exportPlaylist".tr,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }

                              // ── Index 1: Title + description ───────────────
                              if (index == 1) {
                                final title = playlistController
                                    .playlist.value.title;
                                final description = playlistController
                                    .playlist.value.description;

                                return AnimatedBuilder(
                                  animation: playlistController
                                      .animationController,
                                  builder: (context, child) {
                                    return SizedBox(
                                      height: playlistController
                                          .heightAnimation.value,
                                      child: Transform.scale(
                                        scale: playlistController
                                            .scaleAnimation.value,
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: _borderedContainer(
                                    context: context,
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 4),
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 12, 16, 12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Marquee(
                                          delay: const Duration(
                                              milliseconds: 300),
                                          duration:
                                              const Duration(seconds: 5),
                                          id: title.hashCode.toString(),
                                          child: Text(
                                            title.length > 50
                                                ? title.substring(0, 50)
                                                : title,
                                            maxLines: 1,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge!
                                                .copyWith(fontSize: 28),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Marquee(
                                          delay: const Duration(
                                              milliseconds: 300),
                                          duration:
                                              const Duration(seconds: 5),
                                          id:
                                              description.hashCode.toString(),
                                          child: Text(
                                            description ?? "playlist".tr,
                                            maxLines: 1,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              // ── Index 2: Sort widget ────────────────────────
                              if (index == 2) {
                                return _borderedContainer(
                                  context: context,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 4),
                                  padding: EdgeInsets.zero,
                                  child: SizedBox(
                                    height: playlistController
                                            .isSearchingOn.isTrue
                                        ? 60
                                        : 40,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          left: 8, right: 4),
                                      child: Obx(
                                        () => SortWidget(
                                          tag: playlistController
                                              .playlist.value.playlistId,
                                          screenController:
                                              playlistController,
                                          isSearchFeatureRequired: true,
                                          isPlaylistRearrageFeatureRequired:
                                              !playlistController
                                                  .playlist
                                                  .value
                                                  .isCloudPlaylist &&
                                              playlistController
                                                      .playlist
                                                      .value
                                                      .playlistId !=
                                                  "LIBRP" &&
                                              playlistController
                                                      .playlist
                                                      .value
                                                      .playlistId !=
                                                  "SongDownloads" &&
                                              playlistController
                                                      .playlist
                                                      .value
                                                      .playlistId !=
                                                  "SongsCache",
                                          isSongDeletetioFeatureRequired:
                                              !playlistController
                                                  .playlist
                                                  .value
                                                  .isCloudPlaylist,
                                          itemCountTitle:
                                              "${playlistController.songList.length}",
                                          itemIcon: Icons.music_note,
                                          titleLeftPadding: 9,
                                          requiredSortTypes:
                                              buildSortTypeSet(
                                                  false, true),
                                          onSort:
                                              playlistController.onSort,
                                          onSearch:
                                              playlistController.onSearch,
                                          onSearchClose: playlistController
                                              .onSearchClose,
                                          onSearchStart: playlistController
                                              .onSearchStart,
                                          startAdditionalOperation:
                                              playlistController
                                                  .startAdditionalOperation,
                                          selectAll:
                                              playlistController.selectAll,
                                          performAdditionalOperation:
                                              playlistController
                                                  .performAdditionalOperation,
                                          cancelAdditionalOperation:
                                              playlistController
                                                  .cancelAdditionalOperation,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }

                              // ── Loading / empty state ───────────────────────
                              if (playlistController
                                          .isContentFetched.isFalse ||
                                  playlistController.songList.isEmpty) {
                                return SizedBox(
                                  height: 300,
                                  child: Center(
                                    child: playlistController
                                            .isContentFetched.isFalse
                                        ? const LoadingIndicator()
                                        : Text(
                                            "emptyPlaylist".tr,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall,
                                          ),
                                  ),
                                );
                              }

                              // ── Song tiles ─────────────────────────────────
                              return Padding(
                                padding: const EdgeInsets.only(
                                    left: 14, right: 10),
                                child: SongListTile(
                                  onTap: () {
                                    playerController.playPlayListSong(
                                      List<MediaItem>.from(
                                          playlistController.songList),
                                      index - 3,
                                      playfrom: PlaylingFrom(
                                        name: playlistController
                                            .playlist.value.title,
                                        type: PlaylingFromType.PLAYLIST,
                                      ),
                                    );
                                  },
                                  song:
                                      playlistController.songList[index - 3],
                                  isPlaylistOrAlbum: true,
                                  playlist:
                                      playlistController.playlist.value,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Bottom sheet with rename / delete options (bordered style).
  void _showMoreOptions(
    BuildContext context,
    PlaylistScreenController playlistController,
  ) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      constraints: const BoxConstraints(maxWidth: 500),
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(12.0)),
      ),
      context:
          Get.find<PlayerController>().homeScaffoldkey.currentState!.context,
      barrierColor: Colors.transparent.withAlpha(100),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).padding.bottom + 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // Rename option
            Container(
              margin:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(
                    color: cs.outline.withAlpha(25), width: 1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                leading: Icon(Icons.edit_outlined,
                    color: cs.onSurface.withAlpha(180)),
                title: Text("renamePlaylist".tr,
                    style: const TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showDialog(
                    context: context,
                    builder: (dialogContext) =>
                        CreateNRenamePlaylistPopup(
                      renamePlaylist: true,
                      playlist: playlistController.playlist.value,
                    ),
                  );
                },
                visualDensity: const VisualDensity(vertical: -2),
              ),
            ),
            // Delete option
            Container(
              margin:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(
                    color: cs.outline.withAlpha(25), width: 1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                leading: Icon(Icons.delete_outline,
                    color: cs.onSurface.withAlpha(180)),
                title: Text("removePlaylist".tr,
                    style: const TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  playlistController
                      .addNremoveFromLibrary(
                          playlistController.playlist.value,
                          add: false)
                      .then((value) {
                    Get.nestedKey(ScreenNavigationSetup.id)!
                        .currentState!
                        .pop();
                    ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
                        Get.context!,
                        value
                            ? "playlistRemovedAlert".tr
                            : "operationFailed".tr,
                        size: SanckBarSize.MEDIUM));
                  });
                },
                visualDensity: const VisualDensity(vertical: -2),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Future openBottomSheet(BuildContext context, MediaItem song) {
    return showModalBottomSheet(
      constraints: const BoxConstraints(maxWidth: 500),
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(10.0)),
      ),
      isScrollControlled: true,
      context: context,
      barrierColor: Colors.transparent.withAlpha(100),
      builder: (context) => SongInfoBottomSheet(song),
    ).whenComplete(() => Get.delete<SongInfoController>());
  }
}
