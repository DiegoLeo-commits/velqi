import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_Item_builder.dart';
import '/ui/player/player_controller.dart';
import '../../../utils/update_check_flag_file.dart';
import '../../../utils/helper.dart';
import '/models/album.dart';
import '/models/playlist.dart';
import '/models/quick_picks.dart';
import '/services/music_service.dart';
import '../Settings/settings_screen_controller.dart';
import '/ui/widgets/new_version_dialog.dart';

class HomeScreenController extends GetxController {
  final MusicServices _musicServices = Get.find<MusicServices>();
  final isContentFetched = false.obs;
  final tabIndex = 1.obs;
  final networkError = false.obs;
  final quickPicks = QuickPicks([]).obs;
  final middleContent = [].obs;
  final fixedContent = [].obs;
  final showVersionDialog = true.obs;
  //isHomeScreenOnTop var only useful if bottom nav enabled
  final isHomeSreenOnTop = true.obs;
  final List<ScrollController> contentScrollControllers = [];
  bool reverseAnimationtransiton = false;
  /// True once the loading shimmer has been on screen for a few seconds, so
  /// the UI can show a friendly "Preparando Velqi…" hint instead of looking
  /// frozen while the embedded backend cold-starts (first install / slow
  /// emulators can take a while to unpack the Python runtime).
  final showLoadingHint = false.obs;
  Timer? _loadingHintTimer;

  @override
  void onInit() {
    super.onInit();
    // Synchronously pre-load cached home screen data to achieve second-0 instant startup
    final homeScreenData = Hive.box("homeScreenData");
    if (homeScreenData.keys.isNotEmpty) {
      final cacheVersion = Hive.box("AppPrefs").get("homeCacheVersion");
      if (cacheVersion == "5") {
        final String? quickPicksType = homeScreenData.get("quickPicksType");
        final List? quickPicksData = homeScreenData.get("quickPicks");
        final List middleContentData = homeScreenData.get("middleContent") ?? [];
        final List fixedContentData = homeScreenData.get("fixedContent") ?? [];
        if (quickPicksData != null) {
          quickPicks.value = QuickPicks(
              quickPicksData.map((e) => MediaItemBuilder.fromJson(e)).toList(),
              title: quickPicksType ?? "Quick picks");
          middleContent.value = middleContentData
              .map((e) => e["type"] == "Album Content"
                  ? AlbumContent.fromJson(e)
                  : PlaylistContent.fromJson(e))
              .toList();
          fixedContent.value = fixedContentData
              .map((e) => e["type"] == "Album Content"
                  ? AlbumContent.fromJson(e)
                  : PlaylistContent.fromJson(e))
              .toList();
          isContentFetched.value = true;
          printINFO("Síncronamente pre-cargado desde db offline (Velqi)");
        }
      }
    }
    loadContent();
    // If nothing is shown after a few seconds, reassure the user that Velqi
    // is still preparing (backend cold start can take a while on first run).
    _loadingHintTimer = Timer(const Duration(seconds: 8), () {
      if (!isContentFetched.value && !networkError.value) {
        showLoadingHint.value = true;
      }
    });
    if (updateCheckFlag) _checkNewVersion();
  }

  Future<void> loadContent() async {
    final box = Hive.box("AppPrefs");
    final isCachedHomeScreenDataEnabled =
        box.get("cacheHomeScreenData") ?? true;
    try {
      // Force fresh network load if cache version is stale (e.g. after redesign)
      final cacheVersion = box.get("homeCacheVersion");
      if (cacheVersion != "5") {
        box.put("homeCacheVersion", "5");
        // Velqi: always uses Quick Picks (QP) as the fixed home content source.
        box.put("discoverContentType", "QP");
        // Wipe old cached data so stale pre-redesign data doesn't interfere
        try {
          final oldBox = Hive.box("homeScreenData");
          await oldBox.clear();
        } catch (_) {}

        // No cache exists yet, so load fresh from network — hard cap so a
        // slow connection can never leave the app shimmering forever (it
        // falls back to the error UI).
        await loadContentFromNetwork().timeout(
          const Duration(seconds: 75),
          onTimeout: () => _finishHomeLoadWithError(),
        );
        return;
      }

      if (isContentFetched.value) {
        // Warm up backend and refresh in background since cache is already showing
        _initBackendAndRefreshNetwork(box);
      } else {
        // Fallback: try loading cache asynchronously
        if (isCachedHomeScreenDataEnabled) {
          final loaded = await loadContentFromDb();
          if (loaded) {
            isContentFetched.value = true;
            _initBackendAndRefreshNetwork(box);
            return;
          }
        }

        // No cache at all: load from network directly.
        await loadContentFromNetwork().timeout(
          const Duration(seconds: 75),
          onTimeout: () => _finishHomeLoadWithError(),
        );
      }
    } catch (e) {
      // ANY unexpected failure (Hive, parsing, exceptions not surfaced as
      // NetworkError) must resolve the loading state — otherwise the home
      // screen stays grey forever with no error UI and no way to recover.
      printERROR("Home load failed unexpectedly: $e");
      _finishHomeLoadWithError();
    }
  }

  /// Guarantees the loading shimmer always resolves to the retryable error
  /// UI instead of hanging forever when the backend is unreachable or the
  /// data cannot be parsed.
  void _finishHomeLoadWithError() {
    showLoadingHint.value = false;
    if (!isContentFetched.value) {
      networkError.value = true;
    }
  }

  Future<void> _initBackendAndRefreshNetwork(Box box) async {
    final currTimeSecsDiff = DateTime.now().millisecondsSinceEpoch -
        (box.get("homeScreenDataTime") ??
            DateTime.now().millisecondsSinceEpoch);
    // Silent refresh if cache is older than 8 hours
    if (currTimeSecsDiff / 1000 > 3600 * 8) {
      loadContentFromNetwork(silent: true);
    }
  }


  Future<bool> loadContentFromDb() async {
    final homeScreenData = await Hive.openBox("homeScreenData");
    if (homeScreenData.keys.isNotEmpty) {
      final String quickPicksType = homeScreenData.get("quickPicksType");
      final List quickPicksData = homeScreenData.get("quickPicks");
      final List middleContentData = homeScreenData.get("middleContent") ?? [];
      final List fixedContentData = homeScreenData.get("fixedContent") ?? [];
      quickPicks.value = QuickPicks(
          quickPicksData.map((e) => MediaItemBuilder.fromJson(e)).toList(),
          title: quickPicksType);
      middleContent.value = middleContentData
          .map((e) => e["type"] == "Album Content"
              ? AlbumContent.fromJson(e)
              : PlaylistContent.fromJson(e))
          .toList();
      fixedContent.value = fixedContentData
          .map((e) => e["type"] == "Album Content"
              ? AlbumContent.fromJson(e)
              : PlaylistContent.fromJson(e))
          .toList();
      isContentFetched.value = true;
      printINFO("Loaded from offline db");
      return true;
    } else {
      return false;
    }
  }

  Future<void> loadContentFromNetwork({bool silent = false}) async {
    networkError.value = false;
    try {
      final homeContentListMap = await _musicServices.getHome(
          limit:
              Get.find<SettingsScreenController>().noOfHomeScreenContent.value);

      // Always use Quick Picks as the first section
      var qpIndex = homeContentListMap
          .indexWhere((element) => element['title'] == "Quick picks");
      if (qpIndex == -1) {
        qpIndex = homeContentListMap.indexWhere((element) {
          final contents = element["contents"];
          return contents is List &&
              contents.isNotEmpty &&
              contents.first is MediaItem;
        });
      }
      if (qpIndex != -1) {
        final con = homeContentListMap.removeAt(qpIndex);
        quickPicks.value = QuickPicks(List<MediaItem>.from(con["contents"]),
            title: "Quick picks");
      }

      fixedContent.value = _setContentList(homeContentListMap);
      isContentFetched.value = true;
      showLoadingHint.value = false;
      networkError.value = false;

      // set home content last update time
      cachedHomeScreenData(updateAll: true);
      await Hive.box("AppPrefs")
          .put("homeScreenDataTime", DateTime.now().millisecondsSinceEpoch);
      // ignore: unused_catch_stack
    } on NetworkError catch (r, e) {
      printERROR("Home Content not loaded due to ${r.message}");
      await Future.delayed(const Duration(seconds: 1));
      // Retry once more after brief delay before showing error
      if (!silent && !isContentFetched.value) {
        try {
          await Future.delayed(const Duration(seconds: 2));
          final homeContentListMapRetry = await _musicServices.getHome(
              limit: Get.find<SettingsScreenController>()
                  .noOfHomeScreenContent
                  .value);
          if (homeContentListMapRetry.isNotEmpty) {
            quickPicks.value = QuickPicks(
                List<MediaItem>.from(homeContentListMapRetry[0]["contents"]),
                title: homeContentListMapRetry[0]["title"] ?? "Quick picks");
            fixedContent.value =
                _setContentList(homeContentListMapRetry.sublist(1));
            isContentFetched.value = true;
            showLoadingHint.value = false;
            networkError.value = false;
            return;
          }
        } catch (_) {}
      }
      networkError.value = !silent;
    } catch (e) {
      // Backend data can arrive in a shape we don't expect (e.g. after a
      // YouTube/ytmusicapi format change). Any exception here must surface
      // the retryable error UI — otherwise the home screen stays grey
      // forever on the loading shimmer.
      printERROR("Home content unexpected error: $e");
      if (!silent && !isContentFetched.value) {
        networkError.value = true;
      }
    }
  }

  List _setContentList(
    List<dynamic> contents,
  ) {
    List contentTemp = [];
    for (var content in contents) {
      if ((content["contents"]).isEmpty) continue;
      if ((content["contents"][0]).runtimeType == Playlist) {
        final tmp = PlaylistContent(
            playlistList: (content["contents"]).whereType<Playlist>().toList(),
            title: content["title"]);
        if (tmp.playlistList.length >= 1) {
          contentTemp.add(tmp);
        }
      } else if ((content["contents"][0]).runtimeType == Album) {
        final tmp = AlbumContent(
            albumList: (content["contents"]).whereType<Album>().toList(),
            title: content["title"]);
        if (tmp.albumList.length >= 1) {
          contentTemp.add(tmp);
        }
      }
    }
    return contentTemp;
  }

  String getContentHlCode() {
    const List<String> unsupportedLangIds = ["ia", "ga", "fj", "eo"];
    final userLangId =
        Get.find<SettingsScreenController>().currentAppLanguageCode.value;
    return unsupportedLangIds.contains(userLangId) ? "en" : userLangId;
  }

  void onSideBarTabSelected(int index) {
    reverseAnimationtransiton = index > tabIndex.value;
    _resetSettingsSubpageIfNeeded();
    tabIndex.value = index;
  }

  void onBottonBarTabSelected(int index) {
    reverseAnimationtransiton = index > tabIndex.value;
    _resetSettingsSubpageIfNeeded();
    tabIndex.value = index;
  }

  /// Leaving the settings tab (or re-entering it) always returns the settings
  /// screen to its category overview instead of a stale drill-down page.
  void _resetSettingsSubpageIfNeeded() {
    if (Get.isRegistered<SettingsScreenController>()) {
      Get.find<SettingsScreenController>().activeCategory.value = null;
    }
  }

  void _checkNewVersion() {
    showVersionDialog.value =
        Hive.box("AppPrefs").get("newVersionVisibility") ?? true;
    if (showVersionDialog.isTrue) {
      newVersionCheck(Get.find<SettingsScreenController>().currentVersion)
          .then((value) {
        if (value) {
          showDialog(
              context: Get.context!,
              builder: (context) => const NewVersionDialog());
        }
      });
    }
  }

  void onChangeVersionVisibility(bool val) {
    Hive.box("AppPrefs").put("newVersionVisibility", !val);
    showVersionDialog.value = !val;
  }

  ///This is used to minimized bottom navigation bar by setting [isHomeSreenOnTop.value] to `true` and set mini player height.
  ///
  ///and applicable/useful if bottom nav enabled
  void whenHomeScreenOnTop() {
    if (Get.find<SettingsScreenController>().isBottomNavBarEnabled.isTrue) {
      final currentRoute = getCurrentRouteName();
      final isHomeOnTop = currentRoute == '/homeScreen';
      final isResultScreenOnTop = currentRoute == '/searchResultScreen';
      final playerCon = Get.find<PlayerController>();

      isHomeSreenOnTop.value = isHomeOnTop;

      // Set miniplayer height accordingly
      if (!playerCon.initFlagForPlayer) {
        if (isHomeOnTop) {
          playerCon.playerPanelMinHeight.value = 75.0;
        } else {
          Future.delayed(
              isResultScreenOnTop
                  ? const Duration(milliseconds: 300)
                  : Duration.zero, () {
            playerCon.playerPanelMinHeight.value =
                75.0 + Get.mediaQuery.viewPadding.bottom;
          });
        }
      }
    }
  }

  Future<void> cachedHomeScreenData({
    bool updateAll = false,
    bool updateQuickPicksNMiddleContent = false,
  }) async {
    if (Get.find<SettingsScreenController>().cacheHomeScreenData.isFalse ||
        quickPicks.value.songList.isEmpty) {
      return;
    }

    final homeScreenData = Hive.box("homeScreenData");

    if (updateQuickPicksNMiddleContent) {
      await homeScreenData.putAll({
        "quickPicksType": quickPicks.value.title,
        "quickPicks": _getContentDataInJson(quickPicks.value.songList,
            isQuickPicks: true),
        "middleContent": _getContentDataInJson(middleContent.toList()),
      });
    } else if (updateAll) {
      await homeScreenData.putAll({
        "quickPicksType": quickPicks.value.title,
        "quickPicks": _getContentDataInJson(quickPicks.value.songList,
            isQuickPicks: true),
        "middleContent": _getContentDataInJson(middleContent.toList()),
        "fixedContent": _getContentDataInJson(fixedContent.toList())
      });
    }

    printINFO("Saved Homescreen data data");
  }

  List<Map<String, dynamic>> _getContentDataInJson(List content,
      {bool isQuickPicks = false}) {
    if (isQuickPicks) {
      return content.toList().map((e) => MediaItemBuilder.toJson(e)).toList();
    } else {
      return content.map((e) {
        if (e.runtimeType == AlbumContent) {
          return (e as AlbumContent).toJson();
        } else {
          return (e as PlaylistContent).toJson();
        }
      }).toList();
    }
  }

  void disposeDetachedScrollControllers({bool disposeAll = false}) {
    final scrollControllersCopy = contentScrollControllers.toList();
    for (final contoller in scrollControllersCopy) {
      if (!contoller.hasClients || disposeAll) {
        contentScrollControllers.remove(contoller);
        contoller.dispose();
      }
    }
  }

  @override
  void dispose() {
    _loadingHintTimer?.cancel();
    disposeDetachedScrollControllers(disposeAll: true);
    super.dispose();
  }
}
