import 'dart:io';

import 'package:audio_service/audio_service.dart';
import '/services/discord_rpc_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:velqi/ui/player/player_controller.dart';
import 'package:velqi/ui/screens/Settings/settings_screen_controller.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class DesktopSystemTray extends GetxService with TrayListener {
  late WindowListener listener;

  @override
  void onInit() {
    trayManager.addListener(this);
    Future.delayed(const Duration(seconds: 2), () => initSystemTray());
    super.onInit();
  }

  Future<void> initSystemTray() async {
    // tray_manager needs a real filesystem path for the icon. Relying on a
    // build script copying velqi_tray.ico next to the exe left the tray
    // iconless in every `flutter run` (debug) session. Extract the .ico from
    // the asset bundle to a temp file instead — works in debug AND release.
    String iconPath;
    if (GetPlatform.isWindows) {
      try {
        final bytes = await rootBundle.load('assets/images/velqi_tray.ico');
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/velqi_tray.ico');
        await f.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        iconPath = f.path;
      } catch (_) {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        iconPath = '$exeDir\\velqi_tray.ico';
      }
    } else {
      iconPath = 'assets/images/velqi.png';
    }

    await windowManager.ensureInitialized();
    final playerController = Get.find<PlayerController>();

    await trayManager.setIcon(iconPath);

    // create context menu
    final Menu menu = Menu(items: [
      MenuItem(
        label: 'Show/Hide',
        onClick: (menuItem) async => await windowManager.isVisible()
            ? await windowManager.hide()
            : await windowManager.show(),
      ),
      MenuItem.separator(),
      MenuItem(
        label: 'Prev',
        onClick: (menuItem) {
          if (playerController.currentQueue.isNotEmpty) {
            playerController.prev();
          }
        },
      ),
      MenuItem(
        label: 'Play/Pause',
        onClick: (menuItem) {
          if (playerController.currentQueue.isNotEmpty) {
            playerController.playPause();
          }
        },
      ),
      MenuItem(
        label: 'Next',
        onClick: (menuItem) {
          if (playerController.currentQueue.isNotEmpty) {
            playerController.next();
          }
        },
      ),
      MenuItem.separator(),
      MenuItem(
        label: 'Quit',
        onClick: (menuItem) async {
          await Get.find<AudioHandler>().customAction("saveSession");
          // Drop the Discord presence before the process dies.
          try {
            await DiscordRpcService.instance.shutdown();
          } catch (_) {}
          exit(0);
        },
      ),
    ]);

    // set context menu
    await trayManager.setContextMenu(menu);

    await windowManager.setPreventClose(true);
    listener = CloseWindowListener();
    windowManager.addListener(listener);
  }

  @override
  void onClose() {
    trayManager.removeListener(this);
    windowManager.removeListener(listener);
    super.onClose();
  }

  @override
  void onTrayIconMouseDown() {
    if (GetPlatform.isWindows) {
      windowManager.show();
    } else {
      trayManager.popUpContextMenu();
    }

    super.onTrayIconMouseDown();
  }

  @override
  void onTrayIconRightMouseDown() {
    if (GetPlatform.isWindows) {
      trayManager.popUpContextMenu();
    } else {
      windowManager.show();
    }

    super.onTrayIconRightMouseDown();
  }
}

class CloseWindowListener extends WindowListener {
  bool _dialogOpen = false;
  bool _shuttingDown = false;

  @override
  Future<void> onWindowClose() async {
    if (_shuttingDown) return; // real close already in progress
    final settingsScrnController = Get.find<SettingsScreenController>();
    final playerController = Get.find<PlayerController>();
    final canGoBackground = settingsScrnController.backgroundPlayEnabled.isTrue &&
        playerController.buttonState.value == PlayButtonState.playing;

    await windowManager.show();
    if (_dialogOpen) return;
    _dialogOpen = true;
    Get.defaultDialog(
      title: "Cerrar Velqi",
      titleStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      middleText: canGoBackground
          ? "¿Qué quieres hacer?\n\nPuedes dejarlo en segundo plano (la música sigue) o cerrarlo por completo."
          : "¿Quieres cerrar Velqi por completo?\n\nEsto detiene la música y el motor de búsqueda.",
      textConfirm: "Cerrar",
      confirmTextColor: Colors.white,
      onConfirm: () async {
        Get.back();
        _dialogOpen = false;
        await _shutdownCompletely();
      },
      textCancel: canGoBackground ? "Segundo plano" : "Cancelar",
      onCancel: canGoBackground
          ? () async {
              Get.back();
              _dialogOpen = false;
              await windowManager.hide();
            }
          : () {
              Get.back();
              _dialogOpen = false;
            },
    );
  }

  /// Full shutdown: save session (there is no embedded backend to stop —
  /// everything is pure Dart now), then exit.
  Future<void> _shutdownCompletely() async {
    if (_shuttingDown) return;
    _shuttingDown = true;
    try {
      await Get.find<AudioHandler>().customAction("saveSession");
    } catch (_) {}
    // Drop the Discord Rich Presence before the process dies so the activity
    // disappears from the profile immediately.
    try {
      await DiscordRpcService.instance.shutdown();
    } catch (_) {}
    exit(0);
  }
}
