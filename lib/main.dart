import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:terminate_restart/terminate_restart.dart';

import '/ui/screens/Search/search_screen_controller.dart';
import '/utils/get_localization.dart';
import '/services/downloader.dart';
import 'utils/app_link_controller.dart';
import '/services/audio_handler.dart';
import '/services/discord_rpc_service.dart';
import '/services/audio_analysis_service.dart';
import '/services/music_service.dart';
import '/ui/home.dart';
import '/ui/player/player_controller.dart';
import 'ui/screens/Settings/settings_screen_controller.dart';
import '/ui/utils/theme_controller.dart';
import 'ui/screens/Home/home_screen_controller.dart';
import 'ui/screens/Library/library_controller.dart';
import 'utils/system_tray.dart';
import 'utils/update_check_flag_file.dart';
import '/services/permission_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHive();
  _setAppInitPrefs();
  // Everything is pure Dart now — no embedded backend to start.
  startApplicationServices();
  Get.put<AudioHandler>(await initAudioService(), permanent: true);
  // Android 13+: request the notification permission once the UI is visible so
  // the media-control notification can be shown while playing. It is also
  // re-requested at playback start (audio_handler.dart) as a safety net.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    PermissionService.getNotificationPermission();
  });
  WidgetsBinding.instance.addObserver(LifecycleHandler());
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  TerminateRestart.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    if (!GetPlatform.isDesktop) Get.put(AppLinksController());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    return GetMaterialApp(
        title: 'Velqi',
        // No splash: everything is pure Dart and ready from second zero —
        // the loading animation only delayed the app for no reason.
        // Soft cross-fade for every pushed screen (album, playlist, artist,
        // settings...) — matches the dark, calm design language.
        defaultTransition: Transition.fade,
        transitionDuration: const Duration(milliseconds: 260),
        home: const Home(),
        debugShowCheckedModeBanner: false,
        translations: Languages(),
        locale:
            Locale(Hive.box("AppPrefs").get('currentAppLanguageCode') ?? "es"),
        fallbackLocale: const Locale("es"),
        builder: (context, child) {
          final mQuery = MediaQuery.of(context);
          final scale =
              mQuery.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.1);
          return Stack(
            children: [
              GetX<ThemeController>(
                builder: (controller) => MediaQuery(
                  data: mQuery.copyWith(textScaler: scale),
                  child: AnimatedTheme(
                      duration: const Duration(milliseconds: 700),
                      data: controller.themedata.value!,
                      child: child!),
                ),
              ),
              GestureDetector(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    color: Colors.transparent,
                    height: mQuery.padding.bottom,
                    width: mQuery.size.width,
                  ),
                ),
              )
            ],
          );
        });
  }
}

Future<void> startApplicationServices() async {
  Get.lazyPut(() => MusicServices(), fenix: true);
  // REAL audio analysis — drives the beat pulse + equalizer (wave ring,
  // play/pause pump). Both platforms capture the actual output mix:
  // WASAPI loopback on desktop, Android Visualizer on Android.
  Get.put(AudioAnalysisService(), permanent: true);
  if (GetPlatform.isDesktop) {
    // Discord Rich Presence ("Listening to Velqi") — desktop only.
    Get.put(DiscordRpcService(), permanent: true);
  }
  Get.lazyPut(() => ThemeController(), fenix: true);
  Get.lazyPut(() => PlayerController(), fenix: true);
  Get.lazyPut(() => HomeScreenController(), fenix: true);
  Get.lazyPut(() => LibrarySongsController(), fenix: true);
  Get.lazyPut(() => LibraryPlaylistsController(), fenix: true);
  Get.lazyPut(() => LibraryAlbumsController(), fenix: true);
  Get.lazyPut(() => LibraryArtistsController(), fenix: true);
  Get.lazyPut(() => SettingsScreenController(), fenix: true);
  Get.lazyPut(() => Downloader(), fenix: true);
  if (GetPlatform.isDesktop) {
    Get.lazyPut(() => SearchScreenController(), fenix: true);
    Get.put(DesktopSystemTray());
  }
}

Future<void> initHive() async {
  String applicationDataDirectoryPath;
  if (GetPlatform.isDesktop) {
    applicationDataDirectoryPath =
        "${(await getApplicationSupportDirectory()).path}/db";
  } else {
    applicationDataDirectoryPath =
        (await getApplicationDocumentsDirectory()).path;
  }
  await Hive.initFlutter(applicationDataDirectoryPath);

  // Open every box defensively: if a previous run was killed mid-write the
  // box file can be corrupted and Hive.openBox would throw, crashing the app
  // on every launch (the classic crash-loop on reopen). Recovery: delete the
  // corrupt box from disk and open it fresh so the app always starts.
  const boxes = [
    "SongsCache",
    "SongDownloads",
    "SongsUrlCache",
    "AppPrefs",
    "homeScreenData",
  ];
  for (final boxName in boxes) {
    try {
      await Hive.openBox(boxName);
    } catch (e) {
      debugPrint("[HIVE] box '$boxName' corrupt ($e) — deleting and retrying");
      try {
        await Hive.deleteBoxFromDisk(boxName);
        await Hive.openBox(boxName);
      } catch (e2) {
        debugPrint("[HIVE] box '$boxName' recovery failed: $e2");
      }
    }
  }
}

void _setAppInitPrefs() {
  final appPrefs = Hive.box("AppPrefs");
  if (appPrefs.isEmpty) {
    appPrefs.putAll({
      'themeModeType': 2, // dark by default
      "cacheSongs": false,
      "skipSilenceEnabled": false,
      'streamingQuality': 1,
      'themePrimaryColor': 0xFF7C3AED, // Velqi violet
      'discoverContentType': "QP",
      'currentAppLanguageCode': 'es', // Velqi: Spanish by default
      'newVersionVisibility': updateCheckFlag,
      "cacheHomeScreenData": true
    });
  }
}

class LifecycleHandler extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else if (state == AppLifecycleState.detached) {
      await Get.find<AudioHandler>().customAction("saveSession");
    }
  }
}
