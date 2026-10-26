import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/downloader.dart';
import '../screens/Playlist/playlist_screen_controller.dart';
import '../screens/Settings/settings_screen_controller.dart';
import '/utils/helper.dart';
import '/ui/widgets/sleep_timer_bottom_sheet.dart';
import '/ui/player/player_controller.dart';
import '../screens/Library/library_controller.dart';
import '/ui/widgets/add_to_playlist.dart';
import '/ui/widgets/snackbar.dart';
import '../../models/media_Item_builder.dart';
import '../../models/playlist.dart';
import '../navigator.dart';
import 'image_widget.dart';
import 'song_info_dialog.dart';
import 'song_download_btn.dart';

class SongInfoBottomSheet extends StatelessWidget {
  const SongInfoBottomSheet(this.song,
      {super.key,
      this.playlist,
      this.calledFromPlayer = false,
      this.calledFromQueue = false});
  final MediaItem song;
  final Playlist? playlist;
  final bool calledFromPlayer;
  final bool calledFromQueue;

  @override
  Widget build(BuildContext context) {
    final songInfoController =
        Get.put(SongInfoController(song, calledFromPlayer));
    final playerController = Get.find<PlayerController>();
    final downloader = Get.find<Downloader>();
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: Get.mediaQuery.padding.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ────────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              decoration: BoxDecoration(
                border: Border.all(color: cs.outline.withAlpha(35), width: 1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.only(left: 10, top: 4, right: 8, bottom: 4),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ImageWidget(song: song, size: 52),
                ),
                title: Text(
                  song.title,
                  maxLines: 1,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(song.artist!),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SongDownloadButton(calledFromPlayer: false, song_: song),
                    const SizedBox(width: 4),
                    calledFromPlayer
                        ? IconButton(
                            onPressed: () => showDialog(
                                  context: context,
                                  builder: (context) =>
                                      SongInfoDialog(song: song),
                                ),
                            icon: Icon(
                              Icons.info_outline,
                              color: cs.onSurface.withAlpha(160),
                              size: 22,
                            ),
                            splashRadius: 18,
                          )
                        : Obx(() => IconButton(
                              onPressed: songInfoController.toggleFav,
                              icon: Icon(
                                songInfoController.isCurrentSongFav.isFalse
                                    ? Icons.favorite_border
                                    : Icons.favorite,
                                color: songInfoController
                                        .isCurrentSongFav.isFalse
                                    ? cs.onSurface.withAlpha(160)
                                    : Colors.redAccent,
                                size: 22,
                              ),
                              splashRadius: 18,
                            )),
                  ],
                ),
              ),
            ),

            // ── Playback section ──────────────────────────────────────
            _sectionHeader(context, "Playback"),
            _menuItem(context, Icons.sensors, "startRadio".tr, () {
              Navigator.of(context).pop();
              playerController.startRadio(song);
            }),
            if (!(calledFromPlayer || calledFromQueue)) ...[
              _menuItem(context, Icons.playlist_play, "playNext".tr, () {
                Navigator.of(context).pop();
                playerController.playNext(song);
                final playnextMsg = "playnextMsg".tr;
                ScaffoldMessenger.of(context).showSnackBar(snackbar(context,
                    "$playnextMsg ${song.title}",
                    size: SanckBarSize.BIG));
              }),
              _menuItem(context, Icons.merge, "enqueueSong".tr, () {
                playerController.enqueueSong(song).whenComplete(() {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(snackbar(
                      context, "songEnqueueAlert".tr,
                      size: SanckBarSize.MEDIUM));
                });
                Navigator.of(context).pop();
              }),
            ],

            // ── Library section ───────────────────────────────────────
            _sectionHeader(context, "Library"),
            _menuItem(context, Icons.playlist_add, "addToPlaylist".tr, () {
              Navigator.of(context).pop();
              showDialog(
                context: context,
                builder: (context) => AddToPlaylist([song]),
              ).whenComplete(() => Get.delete<AddToPlaylistController>());
            }),
            if (song.extras!['album'] != null)
              _menuItem(context, Icons.album, "goToAlbum".tr, () {
                Navigator.of(context).pop();
                if (calledFromPlayer || calledFromQueue) {
                  playerController.playerPanelController.close();
                }
                Get.toNamed(ScreenNavigationSetup.albumScreen,
                    id: ScreenNavigationSetup.id,
                    arguments: (null, song.extras!['album']['id']));
              }),
            ..._artistItems(song, context, calledFromPlayer, calledFromQueue),

            // ── Manage section ────────────────────────────────────────
            if (playlist != null && !playlist!.isCloudPlaylist &&
                    !(playlist!.playlistId == "LIBRP"))
              _sectionHeader(context, "Manage"),
            if (playlist != null && !playlist!.isCloudPlaylist &&
                    !(playlist!.playlistId == "LIBRP"))
              _menuItem(context, Icons.delete,
                  playlist!.title == "Library Songs"
                      ? "removeFromLib".tr
                      : "removeFromPlaylist".tr, () {
                Navigator.of(context).pop();
                songInfoController
                    .removeSongFromPlaylist(song, playlist!)
                    .whenComplete(() => ScaffoldMessenger.of(Get.context!)
                        .showSnackBar(snackbar(Get.context!,
                            "Removed from ${playlist!.title}",
                            size: SanckBarSize.MEDIUM)));
              }),
            if (calledFromQueue)
              _menuItem(context, Icons.delete, "removeFromQueue".tr, () {
                Navigator.of(context).pop();
                if (playerController.currentSong.value!.id == song.id) {
                  ScaffoldMessenger.of(context).showSnackBar(snackbar(
                      context, "songRemovedfromQueueCurrSong".tr,
                      size: SanckBarSize.BIG));
                } else {
                  playerController.removeFromQueue(song);
                  ScaffoldMessenger.of(context).showSnackBar(snackbar(
                      context, "songRemovedfromQueue".tr,
                      size: SanckBarSize.MEDIUM));
                }
              }),
            Obx(
              () => (songInfoController.isDownloaded.isTrue &&
                      (playlist?.playlistId != "SongDownloads" &&
                          playlist?.playlistId != "SongsCache"))
                  ? _menuItem(
                      context, Icons.delete, "deleteDownloadData".tr, () {
                      Navigator.of(context).pop();
                      final box = Hive.box("SongDownloads");
                      Get.find<LibrarySongsController>()
                          .removeSong(song, true,
                              url: box.get(song.id)['url'])
                          .then((value) async {
                        box.delete(song.id).then((value) {
                          if (playlist != null) {
                            Get.find<PlaylistScreenController>(
                                    tag: Key(playlist!.playlistId)
                                        .hashCode
                                        .toString())
                                .checkDownloadStatus();
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(snackbar(
                                context, "deleteDownloadedDataAlert".tr,
                                size: SanckBarSize.BIG));
                          }
                        });
                      });
                    })
                  : (!downloader.songQueue.contains(song))
                      ? _menuItem(context, Icons.download, "download".tr, () {
                          Navigator.of(context).pop();
                          downloader.download(song);
                        })
                      : const SizedBox.shrink(),
            ),

            // ── More section ──────────────────────────────────────────
            _sectionHeader(context, "More"),
            if (calledFromPlayer)
              _menuItem(context, Icons.timer, "sleepTimer".tr, () {
                Navigator.of(context).pop();
                showModalBottomSheet(
                  constraints: const BoxConstraints(maxWidth: 500),
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(10.0)),
                  ),
                  isScrollControlled: true,
                  context:
                      playerController.homeScaffoldkey.currentState!.context,
                  barrierColor: Colors.transparent.withAlpha(100),
                  builder: (context) => const SleepTimerBottomSheet(),
                );
              }),
            _menuItem(context, Icons.share, "shareSong".tr,
                () => Share.share("https://youtube.com/watch?v=${song.id}")),
            _menuItem(context, Icons.open_with, "openIn".tr, null,
                trailing: SizedBox(
                  width: 140,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        splashRadius: 16,
                        onPressed: () {
                          launchUrl(Uri.parse(
                              "https://youtube.com/watch?v=${song.id}"));
                        },
                        icon: const Icon(Icons.play_circle_outline, size: 22),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        splashRadius: 16,
                        onPressed: () {
                          launchUrl(Uri.parse(
                              "https://music.youtube.com/watch?v=${song.id}"));
                        },
                        icon: const Icon(Icons.music_note, size: 22),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: cs.onSurface.withAlpha(120),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(color: cs.outline.withAlpha(30), height: 1),
          ),
        ],
      ),
    );
  }

  Widget _menuItem(BuildContext context, IconData icon, String title,
      VoidCallback? onTap,
      {Widget? trailing}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline.withAlpha(25), width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        leading: Icon(icon, size: 20, color: cs.onSurface.withAlpha(180)),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }

  List<Widget> _artistItems(MediaItem song, BuildContext context,
      bool calledFromPlayer, bool calledFromQueue) {
    final artistList = <Map<String, dynamic>>[];
    final artists = song.extras!['artists'];
    if (artists != null) {
      for (dynamic each in artists) {
        if (each.containsKey("id") && each['id'] != null) {
          artistList.add(Map<String, dynamic>.from(each));
        }
      }
    }
    if (artistList.isEmpty) return [];
    return [
      _sectionHeader(context, "Artists"),
      ...artistList.map((e) => _menuItem(context, Icons.person,
          "viewArtist".tr + " (${e['name']})", () async {
        Navigator.of(context).pop();
        if (calledFromPlayer) {
          Get.find<PlayerController>().playerPanelController.close();
        }
        if (calledFromQueue) {
          Get.find<PlayerController>().playerPanelController.close();
        }
        await Get.toNamed(ScreenNavigationSetup.artistScreen,
            id: ScreenNavigationSetup.id,
            preventDuplicates: true,
            arguments: [true, e['id']]);
      })),
    ];
  }
}

class SongInfoController extends GetxController
    with RemoveSongFromPlaylistMixin {
  final isCurrentSongFav = false.obs;
  final MediaItem song;
  final bool calledFromPlayer;
  List artistList = [].obs;
  final isDownloaded = false.obs;
  SongInfoController(this.song, this.calledFromPlayer) {
    _setInitStatus(song);
  }
  _setInitStatus(MediaItem song) async {
    isDownloaded.value = Hive.box("SongDownloads").containsKey(song.id);
    isCurrentSongFav.value =
        (await Hive.openBox("LIBFAV")).containsKey(song.id);
    final artists = song.extras!['artists'];
    if (artists != null) {
      for (dynamic each in artists) {
        if (each.containsKey("id") && each['id'] != null) artistList.add(each);
      }
    }
  }

  void setDownloadStatus(bool isDownloaded_) {
    if (isDownloaded_) {
      Future.delayed(const Duration(milliseconds: 100),
          () => isDownloaded.value = isDownloaded_);
    }
  }

  Future<void> toggleFav() async {
    if (calledFromPlayer) {
      final cntrl = Get.find<PlayerController>();
      if (cntrl.currentSong.value == song) {
        cntrl.toggleFavourite();
        isCurrentSongFav.value = !isCurrentSongFav.value;
        return;
      }
    }
    final box = await Hive.openBox("LIBFAV");
    isCurrentSongFav.isFalse
        ? box.put(song.id, MediaItemBuilder.toJson(song))
        : box.delete(song.id);
    isCurrentSongFav.value = !isCurrentSongFav.value;
    if (Get.find<SettingsScreenController>()
            .autoDownloadFavoriteSongEnabled
            .isTrue &&
        isCurrentSongFav.isTrue) {
      Get.find<Downloader>().download(song);
    }
  }
}

mixin RemoveSongFromPlaylistMixin {
  Future<void> removeSongFromPlaylist(MediaItem item, Playlist playlist) async {
    final box = await Hive.openBox(playlist.playlistId);
    if (playlist.playlistId == "SongsCache") {
      if (!box.containsKey(item.id)) {
        Hive.box("SongDownloads").delete(item.id);
        Get.find<LibrarySongsController>().removeSong(item, true);
      } else {
        Get.find<LibrarySongsController>().removeSong(item, false);
        box.delete(item.id);
      }
    } else if (playlist.playlistId == "SongDownloads") {
      box.delete(item.id);
      Get.find<LibrarySongsController>().removeSong(item, true);      } else {
      final index =
          box.values.toList().indexWhere((ele) => ele['videoId'] == item.id);
      await box.deleteAt(index);
    }

    try {
      final plstCntroller = Get.find<PlaylistScreenController>(
          tag: Key(playlist.playlistId).hashCode.toString());
      try {
        plstCntroller.addNRemoveItemsinList(item, action: 'remove');
      } catch (e) {}
    } catch (e) {
      printERROR("Some Error in removeSongFromPlaylist (might irrelavant): $e");
    }

    if (playlist.playlistId == "SongDownloads" ||
        playlist.playlistId == "SongsCache") {
      return;
    }
    box.close();
  }
}
