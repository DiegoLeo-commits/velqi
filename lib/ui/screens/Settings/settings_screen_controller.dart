import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:velqi/services/permission_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../utils/update_check_flag_file.dart';
import '../../../utils/helper.dart';
import '/services/music_service.dart';
import '/ui/player/player_controller.dart';
import '../Home/home_screen_controller.dart';
import '/ui/utils/theme_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '/ui/widgets/snackbar.dart';

/// Categories of the new Netflix-style settings navigation.
enum SettingsCategoryId { playback, appearance, content, downloads, advanced, backup, integrations }

class SettingsScreenController extends GetxController {
  late String _supportDir;
  final cacheSongs = false.obs;
  final setBox = Hive.box("AppPrefs");
  final themeModetype = ThemeType.dynamic.obs;
  final skipSilenceEnabled = false.obs;
  final loudnessNormalizationEnabled = false.obs;
  final noOfHomeScreenContent = 3.obs;
  final streamingQuality = AudioQuality.High.obs;
  final playerUi = 0.obs;
  final slidableActionEnabled = true.obs;
  final isIgnoringBatteryOptimizations = false.obs;
  final autoOpenPlayer = false.obs;
  final isNewVersionAvailable = false.obs;
  final stopPlyabackOnSwipeAway = false.obs;
  final currentAppLanguageCode = "en".obs;
  final downloadLocationPath = "".obs;
  final exportLocationPath = "".obs;
  final downloadingFormat = "".obs;
  final autoDownloadFavoriteSongEnabled = false.obs;
  final isTransitionAnimationDisabled = false.obs;
  final isBottomNavBarEnabled = false.obs;
  final backgroundPlayEnabled = true.obs;
  final keepScreenAwake = false.obs;
  final restorePlaybackSession = false.obs;
  final cacheHomeScreenData = true.obs;
  final fastMode = false.obs;
  final currentVersion = "V1.3.1";

  /// Currently opened settings sub-page (Netflix-style category drill-down).
  /// `null` = the category overview (root). Reset when the user leaves the
  /// settings tab (see HomeScreenController tab handlers).
  final activeCategory = Rxn<SettingsCategoryId>(null);

  // ── YouTube Cookies ────────────────────────────────────────────────────────
  final cookiesActive = false.obs;
  final cookiesSource = "bundled".obs;
  final accountName = "".obs;
  final accountEmail = "".obs;
  final accountAvatar = "".obs;

  @override
  void onInit() {
    _setInitValue();
    if (updateCheckFlag) _checkNewVersion();
    _createInAppSongDownDir();
    super.onInit();
  }

  get currentVision => currentVersion;
  get isCurrentPathsupportDownDir =>
      "$_supportDir/Music" == downloadLocationPath.toString();
  String get supportDirPath => _supportDir;

  _checkNewVersion() {
    newVersionCheck(currentVersion)
        .then((value) => isNewVersionAvailable.value = value);
  }

  Future<String> _createInAppSongDownDir() async {
    _supportDir = (await getApplicationSupportDirectory()).path;
    final directory = Directory("$_supportDir/Music/");
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return "$_supportDir/Music";
  }

  Future<void> _setInitValue() async {
    final isDesktop = GetPlatform.isDesktop;
    final appLang = setBox.get('currentAppLanguageCode') ?? "es";
    currentAppLanguageCode.value = appLang == "zh_Hant"
        ? "zh-TW"
        : appLang == "zh_Hans"
            ? "zh-CN"
            : appLang;
    // Velqi: single fixed bottom navigation bar (no side rail, no toggle).
    isBottomNavBarEnabled.value = true;
    noOfHomeScreenContent.value = setBox.get("noOfHomeScreenContent") ?? 3;
    isTransitionAnimationDisabled.value =
        setBox.get("isTransitionAnimationDisabled") ?? false;
    cacheSongs.value = setBox.get('cacheSongs') ?? false;
    // Dark-only app: coerce a saved light/system preference from older
    // builds to dark.
    final savedTheme =
        ThemeType.values[setBox.get('themeModeType') ?? 0];
    themeModetype.value =
        savedTheme == ThemeType.light ? ThemeType.dark : savedTheme;
    skipSilenceEnabled.value =
        isDesktop ? false : setBox.get("skipSilenceEnabled");
    loudnessNormalizationEnabled.value = isDesktop
        ? false
        : (setBox.get("loudnessNormalizationEnabled") ?? false);
    autoOpenPlayer.value = (setBox.get("autoOpenPlayer") ?? true);
    restorePlaybackSession.value =
        setBox.get("restrorePlaybackSession") ?? false;
    fastMode.value = setBox.get("fastMode") ?? false;
    cacheHomeScreenData.value = setBox.get("cacheHomeScreenData") ?? true;
    streamingQuality.value =
        AudioQuality.values[setBox.get('streamingQuality') ?? 1];
    playerUi.value = isDesktop ? 0 : (setBox.get('playerUi') ?? 0);
    backgroundPlayEnabled.value = setBox.get("backgroundPlayEnabled") ?? true;
    keepScreenAwake.value =
        setBox.get("keepScreenAwake") ?? GetPlatform.isDesktop ? true : false;
    final downloadPath =
        setBox.get('downloadLocationPath') ?? await _createInAppSongDownDir();
    downloadLocationPath.value =
        (isDesktop && downloadPath.contains("emulated"))
            ? await _createInAppSongDownDir()
            : downloadPath;

    // Default export path: user-accessible Downloads/Velqi folder
    final defaultExportPath = GetPlatform.isAndroid
        ? "/storage/emulated/0/Download/Velqi"
        : _supportDir;
    exportLocationPath.value =
        setBox.get("exportLocationPath") ?? defaultExportPath;
    downloadingFormat.value = setBox.get('downloadingFormat') ?? "m4a";
    slidableActionEnabled.value = setBox.get('slidableActionEnabled') ?? true;
    stopPlyabackOnSwipeAway.value =
        setBox.get('stopPlyabackOnSwipeAway') ?? false;
    if (GetPlatform.isAndroid) {
      isIgnoringBatteryOptimizations.value =
          (await Permission.ignoreBatteryOptimizations.isGranted);
    }
    autoDownloadFavoriteSongEnabled.value =
        setBox.get("autoDownloadFavoriteSongEnabled") ?? false;
    // Init account state from the persisted session. MusicServices already
    // installed the cookie during startup; here we only mirror it into the
    // settings observables and refresh the account card.
    final savedCookies = setBox.get('userCookiesContent') as String?;
    final hasSession = savedCookies != null && savedCookies.isNotEmpty;
    cookiesSource.value = hasSession ? "user" : "bundled";
    cookiesActive.value = hasSession;
    if (hasSession) {
      _loadAccountInfo();
    }
  }

  Future<void> _loadAccountInfo() async {
    try {
      final services = Get.find<MusicServices>();
      final info =
          services.accountInfo ?? await services.refreshAccountInfo();
      if (info != null) {
        accountName.value = info['name'] ?? '';
        accountEmail.value = info['email'] ?? '';
        accountAvatar.value = info['thumbnailUrl'] ?? '';
        cookiesActive.value = true;
      } else {
        cookiesActive.value = false;
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> saveCookies(String content) async {
    if (content.trim().isEmpty) {
      await clearCookies();
      return null;
    }
    final info = await Get.find<MusicServices>().postCookies(content);
    if (info == null) {
      throw StateError('invalidCookies');
    }
    setBox.put('userCookiesContent', content);
    cookiesSource.value = "user";
    cookiesActive.value = true;
    accountName.value = info['name'] ?? '';
    accountEmail.value = info['email'] ?? '';
    accountAvatar.value = info['thumbnailUrl'] ?? '';
    return info;
  }

  Future<void> clearCookies() async {
    setBox.delete('userCookiesContent');
    cookiesSource.value = "bundled";
    cookiesActive.value = false;
    accountName.value = '';
    accountEmail.value = '';
    accountAvatar.value = '';
    await Get.find<MusicServices>().clearCookies();
  }

  void setAppLanguage(String? val) {
    Get.updateLocale(Locale(val!));
    Get.find<MusicServices>().hlCode = val;
    Get.find<HomeScreenController>().loadContentFromNetwork(silent: true);
    currentAppLanguageCode.value = val;
    setBox.put('currentAppLanguageCode', val);
  }

  void setContentNumber(int? no) {
    noOfHomeScreenContent.value = no!;
    setBox.put("noOfHomeScreenContent", no);
  }

  void setStreamingQuality(dynamic val) {
    setBox.put("streamingQuality", AudioQuality.values.indexOf(val));
    streamingQuality.value = val;
  }

  void setPlayerUi(dynamic val) {
    final playerCon = Get.find<PlayerController>();
    setBox.put("playerUi", val);
    if (val == 1 && playerCon.gesturePlayerStateAnimationController == null) {
      playerCon.initGesturePlayerStateAnimationController();
    }

    playerUi.value = val;
  }

  void enableBottomNavBar(bool val) {
    final homeScrCon = Get.find<HomeScreenController>();
    final playerCon = Get.find<PlayerController>();
    if (val) {
      homeScrCon.onSideBarTabSelected(3);
      isBottomNavBarEnabled.value = true;
    } else {
      isBottomNavBarEnabled.value = false;
      homeScrCon.onSideBarTabSelected(5);
    }
    if (!Get.find<PlayerController>().initFlagForPlayer) {
      playerCon.playerPanelMinHeight.value =
          val ? 75.0 : 75.0 + Get.mediaQuery.viewPadding.bottom;
    }
    setBox.put("isBottomNavBarEnabled", val);
  }

  void toggleSlidableAction(bool val) {
    setBox.put("slidableActionEnabled", val);
    slidableActionEnabled.value = val;
  }

  void changeDownloadingFormat(String? val) {
    setBox.put("downloadingFormat", val);
    downloadingFormat.value = val!;
  }

  Future<void> setExportedLocation() async {
    if (GetPlatform.isAndroid) {
      if (!await PermissionService.getExtStoragePermission()) {
        // Permission was denied — settings page was opened.
        // Show a clear message so the user knows what to do.
        if (Get.context != null) {
          ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
              Get.context!,
              "Ve a Ajustes → 'Permitir acceso a todos los archivos' → Actívalo, luego vuelve y toca esta opción de nuevo.",
              size: SanckBarSize.BIG,
              duration: const Duration(seconds: 5),
              top: true));
        }
        return;
      }
    }

    final String? pickedFolderPath = await _pickDirectory(
        dialogTitle: "Select export file folder");
    if (pickedFolderPath == '/' || pickedFolderPath == null) {
      return;
    }

    setBox.put("exportLocationPath", pickedFolderPath);
    exportLocationPath.value = pickedFolderPath;

    if (Get.context != null) {
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!, "Ubicación de exportación actualizada: $pickedFolderPath",
          size: SanckBarSize.BIG,
          duration: const Duration(seconds: 3),
          top: true));
    }
  }

  Future<void> setDownloadLocation() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final String? pickedFolderPath = await _pickDirectory(
        dialogTitle: "Select downloads folder");
    if (pickedFolderPath == '/' || pickedFolderPath == null) {
      return;
    }

    setBox.put("downloadLocationPath", pickedFolderPath);
    downloadLocationPath.value = pickedFolderPath;
  }

  /// Folder picker that does NOT crash Windows.
  ///
  /// file_picker's Windows directory dialog crashes the whole app with an
  /// access violation inside comdlg32.dll when the folder is accepted
  /// (confirmed in the Windows Event Viewer, app persisted fine). The
  /// official file_selector package uses Flutter's maintained Windows
  /// implementation and doesn't have that bug — desktop uses it, Android
  /// keeps file_picker (file_selector would return a content:// URI there).
  Future<String?> _pickDirectory({required String dialogTitle}) async {
    try {
      if (GetPlatform.isDesktop) {
        return await fs.getDirectoryPath(
          confirmButtonText: dialogTitle,
        );
      }
      return await FilePicker.platform
          .getDirectoryPath(dialogTitle: dialogTitle);
    } catch (e) {
      printERROR("Directory picker failed: $e");
      return null;
    }
  }

  void disableTransitionAnimation(bool val) {
    setBox.put('isTransitionAnimationDisabled', val);
    isTransitionAnimationDisabled.value = val;
  }

  Future<void> clearImagesCache() async {
    final tempImgDirPath =
        "${(await getApplicationCacheDirectory()).path}/libCachedImageData";
    final tempImgDir = Directory(tempImgDirPath);
    try {
      if (await tempImgDir.exists()) {
        await tempImgDir.delete(recursive: true);
      }
    } catch (e) {
      printERROR("Failed to clear image cache: $e");
    }
  }

  void resetDownloadLocation() {
    final defaultPath = "$_supportDir/Music";
    setBox.put("downloadLocationPath", defaultPath);
    downloadLocationPath.value = defaultPath;
  }

  void onThemeChange(dynamic val) {
    setBox.put('themeModeType', ThemeType.values.indexOf(val));
    themeModetype.value = val;
    Get.find<ThemeController>().changeThemeModeType(val);
  }

  void toggleCachingSongsValue(bool value) {
    setBox.put("cacheSongs", value);
    cacheSongs.value = value;
  }

  void toggleSkipSilence(bool val) {
    Get.find<PlayerController>().toggleSkipSilence(val);
    setBox.put('skipSilenceEnabled', val);
    skipSilenceEnabled.value = val;
  }

  void toggleLoudnessNormalization(bool val) {
    Get.find<PlayerController>().toggleLoudnessNormalization(val);
    setBox.put("loudnessNormalizationEnabled", val);
    loudnessNormalizationEnabled.value = val;
  }

  void toggleRestorePlaybackSession(bool val) {
    setBox.put("restrorePlaybackSession", val);
    restorePlaybackSession.value = val;
  }

  void toggleFastMode(bool val) {
    setBox.put("fastMode", val);
    fastMode.value = val;
    if (val) {
      // Guardar calidad anterior y forzar Low
      final prev = setBox.get('streamingQualityPrev') ??
          setBox.get('streamingQuality', defaultValue: 1);
      setBox.put('streamingQualityPrev', prev);
      setBox.put("streamingQuality", 0);
      streamingQuality.value = AudioQuality.Low;
    } else {
      // Restaurar calidad anterior
      final prev = setBox.get('streamingQualityPrev', defaultValue: 1);
      setBox.put("streamingQuality", prev);
      streamingQuality.value = AudioQuality.values[prev];
    }
  }

  Future<void> toggleCacheHomeScreenData(bool val) async {
    setBox.put("cacheHomeScreenData", val);
    cacheHomeScreenData.value = val;
    if (!val) {
      Hive.openBox("homeScreenData").then((box) async {
        await box.clear();
        await box.close();
      });
    } else {
      await Hive.openBox("homeScreenData");
      Get.find<HomeScreenController>().cachedHomeScreenData(updateAll: true);
    }
  }

  void toggleAutoDownloadFavoriteSong(bool val) {
    setBox.put("autoDownloadFavoriteSongEnabled", val);
    autoDownloadFavoriteSongEnabled.value = val;
  }

  void toggleBackgroundPlay(bool val) {
    setBox.put('backgroundPlayEnabled', val);
    backgroundPlayEnabled.value = val;
  }

  void toggleKeepScreenAwake(bool val) {
    setBox.put('keepScreenAwake', val);
    keepScreenAwake.value = val;
    try {
        if (val) {
          // enable wakelock immediately if music is playing
          if (Get.find<PlayerController>().buttonState.value ==
              PlayButtonState.playing) {
            WakelockPlus.enable();
          }
        } else {
          WakelockPlus.disable();
        }
     
    } catch (e) {
      // ignore if player/controller not available
    }
  }

  Future<void> enableIgnoringBatteryOptimizations() async {
    await Permission.ignoreBatteryOptimizations.request();
    isIgnoringBatteryOptimizations.value =
        await Permission.ignoreBatteryOptimizations.isGranted;
  }

  void toggleAutoOpenPlayer(bool val) {
    setBox.put('autoOpenPlayer', val);
    autoOpenPlayer.value = val;
  }

  Future<void> resetAppSettingsToDefault() async {
    await setBox.clear();
  }

  void toggleStopPlyabackOnSwipeAway(bool val) {
    setBox.put('stopPlyabackOnSwipeAway', val);
    stopPlyabackOnSwipeAway.value = val;
  }

  Future<void> closeAllDatabases() async {
    await Hive.close();
  }

  Future<String> get dbDir async {
    if (GetPlatform.isDesktop) {
      return "$supportDirPath/db";
    } else {
      return (await getApplicationDocumentsDirectory()).path;
    }
  }
}
