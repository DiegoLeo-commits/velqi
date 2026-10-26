import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get/get.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../models/playlist.dart';
import '../player/player_controller.dart';
import '../screens/Settings/settings_screen_controller.dart';
import 'add_to_playlist.dart';
import 'image_widget.dart';
import 'snackbar.dart';
import 'songinfo_bottom_sheet.dart';
import 'song_download_btn.dart';

class SongListTile extends StatelessWidget with RemoveSongFromPlaylistMixin {
  const SongListTile(
      {super.key,
      this.onTap,
      required this.song,
      this.playlist,
      this.isPlaylistOrAlbum = false,
      this.thumbReplacementWithIndex = false,
      this.index});
  final Playlist? playlist;
  final MediaItem song;
  final VoidCallback? onTap;
  final bool isPlaylistOrAlbum;

  /// Valid for Album songs
  final bool thumbReplacementWithIndex;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline.withAlpha(25), width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Listener(
          onPointerDown: (PointerDownEvent event) {
            if (event.buttons == kSecondaryMouseButton) {
              showModalBottomSheet(
                constraints: const BoxConstraints(maxWidth: 500),
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(10.0)),
                ),
                isScrollControlled: true,
                context: playerController.homeScaffoldkey.currentState!.context,
                barrierColor: Colors.transparent.withAlpha(100),
                builder: (context) => SongInfoBottomSheet(
                  song,
                  playlist: playlist,
                ),
              ).whenComplete(() => Get.delete<SongInfoController>());
            }
          },
          child: Slidable(
            enabled:
                Get.find<SettingsScreenController>().slidableActionEnabled.isTrue,
            startActionPane: ActionPane(motion: const DrawerMotion(), children: [
              SlidableAction(
                onPressed: (context) {
                  showDialog(
                    context: context,
                    builder: (context) => AddToPlaylist([song]),
                  ).whenComplete(() => Get.delete<AddToPlaylistController>());
                },
                backgroundColor: cs.surfaceContainerHighest,
                foregroundColor: cs.onSurface,
                icon: Icons.playlist_add,
              ),
              if (playlist != null && !playlist!.isCloudPlaylist)
                SlidableAction(
                  onPressed: (context) {
                    removeSongFromPlaylist(song, playlist!);
                  },
                  backgroundColor: cs.surfaceContainerHighest,
                  foregroundColor: cs.onSurface,
                  icon: Icons.delete,
                ),
            ]),
            endActionPane: ActionPane(motion: const DrawerMotion(), children: [
              SlidableAction(
                onPressed: (context) {
                  playerController.enqueueSong(song).whenComplete(() {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(snackbar(
                        context, "songEnqueueAlert".tr,
                        size: SanckBarSize.MEDIUM));
                  });
                },
                backgroundColor: cs.surfaceContainerHighest,
                foregroundColor: cs.onSurface,
                icon: Icons.merge,
              ),
              SlidableAction(
                onPressed: (context) {
                  playerController.playNext(song);
                  ScaffoldMessenger.of(context).showSnackBar(snackbar(
                      context, '${'playnextMsg'.tr} ${(song).title}',
                      size: SanckBarSize.BIG));
                },
                backgroundColor: cs.surfaceContainerHighest,
                foregroundColor: cs.onSurface,
                icon: Icons.next_plan_outlined,
              ),
            ]),
            child: ListTile(
              onTap: onTap,
              onLongPress: () async {
                showModalBottomSheet(
                  constraints: const BoxConstraints(maxWidth: 500),
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(10.0)),
                  ),
                  isScrollControlled: true,
                  context: playerController.homeScaffoldkey.currentState!.context,
                  barrierColor: Colors.transparent.withAlpha(100),
                  builder: (context) => SongInfoBottomSheet(
                    song,
                    playlist: playlist,
                  ),
                ).whenComplete(() => Get.delete<SongInfoController>());
              },
              contentPadding: const EdgeInsets.only(top: 0, left: 8, right: 16),
              leading: thumbReplacementWithIndex
                  ? SizedBox(
                      width: 27.5,
                      height: 55,
                      child: Center(
                        child: Text(
                          "$index.",
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ImageWidget(
                        size: 52,
                        song: song,
                      ),
                    ),
              title: Marquee(
                delay: const Duration(milliseconds: 300),
                duration: const Duration(seconds: 5),
                id: song.title.hashCode.toString(),
                child: Text(
                  song.title.length > 50
                      ? song.title.substring(0, 50)
                      : song.title,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              subtitle: Text(
                "${song.artist}",
                maxLines: 1,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              trailing: SizedBox(
                width: Get.size.width > 800 ? (GetPlatform.isDesktop ? 160 : 120) : 90,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SongDownloadButton(calledFromPlayer: false, song_: song),
                    const SizedBox(width: 6),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isPlaylistOrAlbum)
                          Obx(() =>
                              playerController.currentSong.value?.id == song.id
                                  ? const Icon(
                                      Icons.equalizer,
                                    )
                                  : const SizedBox.shrink()),
                        Text(
                          song.extras!['length'] ?? "",
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                    if (GetPlatform.isDesktop) ...[
                      const SizedBox(width: 4),
                      IconButton(
                          splashRadius: 20,
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
                              builder: (context) => SongInfoBottomSheet(
                                song,
                                playlist: playlist,
                              ),
                            ).whenComplete(
                                () => Get.delete<SongInfoController>());
                          },
                          icon: const Icon(Icons.more_vert))
                    ]
                  ],
                ),
              ),
            ),
          )),
    );
  }
}
