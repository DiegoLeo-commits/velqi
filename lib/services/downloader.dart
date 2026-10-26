import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:audiotags/audiotags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../ui/screens/Album/album_screen_controller.dart';
import '../ui/screens/Playlist/playlist_screen_controller.dart';
import '/services/stream_service.dart';
import '../ui/widgets/snackbar.dart';
import '/services/permission_service.dart';
import '../ui/screens/Settings/settings_screen_controller.dart';
import '/utils/helper.dart';
import '/models/media_Item_builder.dart';
import '../ui/screens/Library/library_controller.dart';
import 'music_service.dart';

class Downloader extends GetxService {
  final _dio = Dio();
  MediaItem? currentSong;
  RxMap<String, List<MediaItem>> playlistQueue =
      <String, List<MediaItem>>{}.obs;
  final currentPlaylistId = "".obs;
  final songDownloadingProgress = 0.obs;
  final playlistDownloadingProgress = 0.obs;
  final isJobRunning = false.obs;

  RxList<MediaItem> songQueue = <MediaItem>[].obs;

  Future<bool> checkPermissionNDir() async {
    final settingsScreenController = Get.find<SettingsScreenController>();

    final dirPath = settingsScreenController.downloadLocationPath.string;
    if (dirPath.isEmpty) {
      printERROR("Download path is empty");
      return false;
    }

    if (!settingsScreenController.isCurrentPathsupportDownDir &&
        !await PermissionService.getExtStoragePermission()) {
      return false;
    }

    try {
      final directory = Directory(dirPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
    } catch (e) {
      printERROR("Failed to create download directory: $e");
      return false;
    }
    return true;
  }

  Future<void> downloadPlaylist(
      String playlistId, List<MediaItem> songList) async {
    if (!(await checkPermissionNDir())) {
      if (Get.context != null) {
        ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
            Get.context!, "Storage permission is required to download songs. Please grant 'All files access' in Settings.",
            size: SanckBarSize.BIG,
            duration: const Duration(seconds: 3),
            top: !GetPlatform.isDesktop));
      }
      return;
    }

    // for toggle between downloading request & cancelling
    if (playlistQueue.containsKey(playlistId)) {
      songQueue.removeWhere((element) => songList.contains(element));
      playlistQueue.remove(playlistId);
      return;
    }

    playlistQueue[playlistId] = songList;
    songQueue.addAll(songList);

    if (isJobRunning.isFalse) {
      await triggerDownloadingJob();
    }
  }

  Future<void> download(MediaItem? song, {List<MediaItem>? songList}) async {
    if (!(await checkPermissionNDir())) {
      if (Get.context != null) {
        ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
            Get.context!, "Storage permission is required to download songs. Please grant 'All files access' in Settings.",
            size: SanckBarSize.BIG,
            duration: const Duration(seconds: 3),
            top: !GetPlatform.isDesktop));
      }
      return;
    }
    if (songList != null) {
      songQueue.addAll(songList);
    } else {
      songQueue.add(song!);
    }
    if (isJobRunning.isFalse) {
      await triggerDownloadingJob();
    }
  }

  Future<void> triggerDownloadingJob() async {
    //check if playlist download in queue => download playlistsongs else download from general songs queue
    if (playlistQueue.isNotEmpty) {
      isJobRunning.value = true;
      for (String playlistId in playlistQueue.keys.toList()) {
        //checked in case download cancel request
        if (playlistQueue.containsKey(playlistId)) {
          currentPlaylistId.value = playlistId;
          await downloadSongList((playlistQueue[playlistId]!).toList(),
              isPlaylist: true);
          if (Get.isRegistered<PlaylistScreenController>(
                  tag: Key(playlistId).hashCode.toString()) &&
              playlistQueue.containsKey(playlistId)) {
            Get.find<PlaylistScreenController>(
                    tag: Key(playlistId).hashCode.toString())
                .isDownloaded
                .value = true;
          } 
          // in case of album
          else if (Get.isRegistered<AlbumScreenController>(
                  tag: Key(playlistId).hashCode.toString()) &&
              playlistQueue.containsKey(playlistId)) {
            Get.find<AlbumScreenController>(
                    tag: Key(playlistId).hashCode.toString())
                .isDownloaded
                .value = true;
          }
          playlistQueue.remove(playlistId);
        }
        currentPlaylistId.value = "";
        playlistDownloadingProgress.value = 0;
      }
    } else {
      isJobRunning.value = true;
      await downloadSongList(songQueue.toList());
    }

    if (songQueue.isNotEmpty) {
      triggerDownloadingJob();
    } else {
      isJobRunning.value = false;
      currentSong = null;
    }
  }

  Future<void> downloadSongList(List<MediaItem> jobSongList,
      {bool isPlaylist = false}) async {
    for (MediaItem song in jobSongList) {
      // intrrupt downloading task in case of playlist download cancel request
      if (isPlaylist && !playlistQueue.containsKey(currentPlaylistId.value)) {
        currentPlaylistId.value = "";
        playlistDownloadingProgress.value = 0;
        return;
      }

      if (!Hive.box("SongDownloads").containsKey(song.id)) {
        currentSong = song;
        songDownloadingProgress.value = 0;
        await writeFileStream(song);
      }
      songQueue.remove(song);
      //for playlist downloading counter update
      if (isPlaylist) {
        playlistDownloadingProgress.value = jobSongList.indexOf(song) + 1;
      }
    }
  }

  Future<void> writeFileStream(MediaItem song) async {
    Completer<void> complete = Completer();

    final settingsScreenController = Get.find<SettingsScreenController>();
    final downloadingFormat = settingsScreenController.downloadingFormat.string;

    final playerResponse = await StreamProvider.fetch(song.id);

    if (!playerResponse.playable) {
      if (Get.context != null) {
        ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
            Get.context!,
            playerResponse.statusMSG == "networkError"
                ? playerResponse.statusMSG.tr
                : playerResponse.statusMSG,
            size: SanckBarSize.BIG,
            duration: const Duration(seconds: 2),
            top: !GetPlatform.isDesktop));
      }
      printINFO("Requested song is not downloadable. You may try again");
      complete.complete();
      return complete.future;
    }

    // Guard against empty audio formats
    if (playerResponse.audioFormats == null || playerResponse.audioFormats!.isEmpty) {
      printERROR("No audio formats available for download");
      if (Get.context != null) {
        ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
            Get.context!, "downloadError3".tr,
            size: SanckBarSize.BIG,
            duration: const Duration(seconds: 2),
            top: !GetPlatform.isDesktop));
      }
      complete.complete();
      return complete.future;
    }

    // Downloads go through the muxed progressive stream (itag 18) when
    // available: it accepts plain GETs and multi-MiB ranges, so the chunked
    // downloader never hits the 403 that adaptive URLs throw on large ranges.
    Audio? requiredAudioStream = playerResponse.progressiveAudio;
    if (requiredAudioStream == null) {
      requiredAudioStream = downloadingFormat == "opus"
          ? playerResponse.highestBitrateOpusAudio
          : playerResponse.highestBitrateMp4aAudio;
      // Fallback: try any available format
      requiredAudioStream ??= playerResponse.highestQualityAudio;
    }
    if (requiredAudioStream == null) {
      printERROR("Failed to select audio format for download");
      complete.complete();
      return complete.future;
    }

    final dirPath = settingsScreenController.downloadLocationPath.string;
    if (dirPath.isEmpty) {
      printERROR("Download path is empty");
      complete.complete();
      return complete.future;
    }

    final actualDownformat =
        requiredAudioStream.audioCodec.name.contains("mp") ? "m4a" : "opus";
    final RegExp invalidChar =
        RegExp(r'Container.|\/|\\|\"|\<|\>|\*|\?|\:|\!|\[|\]|\¡|\||\%');
    final songTitle = "${song.title.trim()} (${song.artist?.trim()})"
        .replaceAll(invalidChar, "");
    // Base path without extension — the backend appends the real one.
    final basePath = "$dirPath/$songTitle";
    printINFO("Downloading basePath: $basePath");

    final String filePath = "$basePath.$actualDownformat";

    _downloadFile(requiredAudioStream.url, filePath,
            totalBytes: requiredAudioStream.size)
        .then((value) async {
      await _finalizeSongDownload(song, filePath, requiredAudioStream!);
      complete.complete();
    }).onError((error, stackTrace) {
      if (Get.context != null) {
        ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
            Get.context!, "downloadError3".tr,
            size: SanckBarSize.BIG,
            duration: const Duration(seconds: 2),
            top: !GetPlatform.isDesktop));
      }
      printINFO(
          "Downloading failed due to network/stream error! Please try again");
      complete.complete();
    });

    return complete.future;
  }

  static const _downloadUA =
      'com.google.android.youtube/20.01.35 (Linux; U; Android 13) gzip';
  static const _chunkSize = 2 * 1024 * 1024; // 2 MiB — safe size for ranged GETs

  /// Downloads [url] into [filePath], preferring the fastest path:
  ///
  /// 1. Progressive streams (itag 18) accept a single Range-less GET — one
  ///    connection, full speed, real-time progress.
  /// 2. If the server rejects it (adaptive URLs 403 on big ranges), fall back
  ///    to streaming the file in bounded ~2 MiB ranged requests, which
  ///    YouTube always serves.
  Future<void> _downloadFile(String url, String filePath,
      {required int totalBytes}) async {
    try {
      await _dio.download(
        url,
        filePath,
        options: Options(headers: {'User-Agent': _downloadUA}),
        onReceiveProgress: (count, total) {
          final effectiveTotal = total > 0 ? total : totalBytes;
          songDownloadingProgress.value = effectiveTotal > 0
              ? ((count / effectiveTotal) * 100).toInt().clamp(0, 100)
              : -1;
        },
      );
      songDownloadingProgress.value = 100;
      return;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // 403/40x on a plain GET = adaptive URL; use bounded chunks instead.
      if (status == null || status >= 500) rethrow;
      printINFO('Download plain GET rejected ($status) -> chunked fallback');
    }

    await _downloadChunked(url, filePath,
        totalBytes: totalBytes,
        onProgress: (pct) => songDownloadingProgress.value = pct);
  }

  /// Streams [url] into [filePath] with bounded Range requests.
  Future<void> _downloadChunked(String url, String filePath,
      {required int totalBytes,
      required void Function(int pct) onProgress}) async {
    final file = File(filePath);
    if (await file.exists()) await file.delete();
    final raf = await file.open(mode: FileMode.writeOnlyAppend);
    var downloaded = 0;
    try {
      while (true) {
        final end = downloaded + _chunkSize - 1;
        final res = await _dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {
              'Range': 'bytes=$downloaded-$end',
              'User-Agent': _downloadUA,
            },
          ),
        );
        final data = res.data ?? const <int>[];
        if (data.isEmpty) break;
        await raf.writeFrom(data);
        downloaded += data.length;
        // Recover the real total from Content-Range when unknown up front.
        if (totalBytes <= 0 && res.headers.value('content-range') != null) {
          final m = RegExp(r'/(\d+)$')
              .firstMatch(res.headers.value('content-range')!);
          if (m != null) totalBytes = int.parse(m.group(1)!);
        }
        onProgress(totalBytes > 0
            ? ((downloaded / totalBytes) * 100).toInt().clamp(0, 100)
            : -1);
        // A short chunk means we reached the end of the file.
        if (data.length < _chunkSize) break;
        if (totalBytes > 0 && downloaded >= totalBytes) break;
      }
    } finally {
      await raf.close();
    }
    onProgress(100);
  }

  /// Writes metadata, thumbnail and audio tags for a finished download.
  Future<void> _finalizeSongDownload(
      MediaItem song, String filePath, Audio requiredAudioStream) async {
    final settingsScreenController = Get.find<SettingsScreenController>();

    String? year;
    try {
      if (song.extras?['year'] != null) {
        year = song.extras?['year'];
      } else {
        if (song.album != null) {
          final musicServ = Get.find<MusicServices>();
          year = await musicServ.getSongYear(song.id);
        }
      }
    } catch (_) {}

    // Save Thumbnail
    try {
      final thumbnailPath =
          "${settingsScreenController.supportDirPath}/thumbnails/${song.id}.png";
      await _dio.downloadUri(song.artUri!, thumbnailPath);
      // ignore: empty_catches
    } catch (e) {}

    song.extras?['url'] = filePath;
    final songJson = MediaItemBuilder.toJson(song);
    final streamInfoJson = requiredAudioStream.toJson();
    streamInfoJson['url'] = filePath;
    // [playbility status, info map]
    songJson["streamInfo"] = [true, streamInfoJson];

    Hive.box("SongDownloads").put(song.id, songJson);
    Get.find<LibrarySongsController>().librarySongsList.add(song);
    printINFO("Downloaded successfully");

    final trackDetails = (song.extras?['trackDetails'])?.split("/");
    final int? trackNumber = int.tryParse(trackDetails?[0] ?? "");
    final int? totalTracks = int.tryParse(trackDetails?[1] ?? "");

    try {
      final imageUrl = song.artUri!.toString();
      Tag tag = Tag(
          title: song.title,
          trackArtist: song.artist,
          album: song.album,
          year: int.tryParse(year ?? ""),
          trackNumber: trackNumber,
          trackTotal: totalTracks,
          albumArtist: song.artist,
          genre: song.genre,
          pictures: [
            Picture(
                bytes: (await NetworkAssetBundle(Uri.parse((imageUrl)))
                        .load(imageUrl))
                    .buffer
                    .asUint8List(),
                mimeType: MimeType.png,
                pictureType: PictureType.coverFront)
          ]);

      await AudioTags.write(filePath, tag);
    } catch (e) {
      printERROR("$e");
    }
  }
}
