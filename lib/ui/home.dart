import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/ui/screens/Home/home_screen_controller.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '../utils/helper.dart';
import '../ui/navigator.dart';
import '../ui/player/player.dart';
import 'player/components/mini_player.dart';
import 'player/player_controller.dart';
import 'widgets/bottom_nav_bar.dart';
import 'widgets/scroll_to_hide.dart';
import 'widgets/sliding_up_panel.dart';
import 'widgets/snackbar.dart';
import 'widgets/up_next_queue.dart';

class Home extends StatelessWidget {
  const Home({super.key});
  static const routeName = '/appHome';
  static bool _escHandlerRegistered = false;
  @override
  Widget build(BuildContext context) {
    printINFO("Home");
    final PlayerController playerController = Get.find<PlayerController>();
    final settingsScreenController = Get.find<SettingsScreenController>();
    final homeScreenController = Get.find<HomeScreenController>();
    final size = MediaQuery.of(context).size;
    final isWideScreen = size.width > 800;
    final isLight = Theme.of(context).brightness == Brightness.light;
    if (!playerController.initFlagForPlayer &&
        settingsScreenController.isBottomNavBarEnabled.isFalse) {
      // Constant compact mini player — same size with or without the bottom
      // navbar (the user wants the compact docked look at all times).
      playerController.playerPanelMinHeight.value = isWideScreen ? 105.0 : 75.0;
    }
    // Desktop escape hatch: ESC collapses the full player back to the
    // miniplayer. Raw keyboard handler — independent of the gesture arena,
    // so it works even if a click thief ever blocks the on-screen button.
    if (GetPlatform.isDesktop && !_escHandlerRegistered) {
      _escHandlerRegistered = true;
      HardwareKeyboard.instance.addHandler((event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          final c = playerController.playerPanelController;
          if (c.isAttached && c.panelPosition > 0.01) {
            c.close();
            return true;
          }
        }
        return false;
      });
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (playerController.playerPanelController.isPanelOpen) {
          playerController.playerPanelController.close();
        } else {
          if (Get.nestedKey(ScreenNavigationSetup.id)!.currentState!.canPop()) {
            Get.nestedKey(ScreenNavigationSetup.id)!.currentState!.pop();
          } else {
            if (homeScreenController.tabIndex.value != 1) {
              settingsScreenController.isBottomNavBarEnabled.isTrue
                  ? homeScreenController.onBottonBarTabSelected(1)
                  : homeScreenController.onSideBarTabSelected(1);
            } else if (playerController.buttonState.value ==
                PlayButtonState.playing) {
              SystemNavigator.pop();
            } else {
              await Get.find<AudioHandler>().customAction("saveSession");
              exit(0);
            }
          }
        }
      },
      child: CallbackShortcuts(
        bindings: {
          LogicalKeySet(LogicalKeyboardKey.space): playerController.playPause
        },
        child: Obx(
          () => Scaffold(
              bottomNavigationBar: settingsScreenController
                      .isBottomNavBarEnabled.isTrue
                  ? ScrollToHideWidget(
                      isVisible: homeScreenController.isHomeSreenOnTop.isTrue &&
                          playerController.isPanelGTHOpened.isFalse,
                      child: const BottomNavBar())
                  : null,
              key: playerController.homeScaffoldkey,
              endDrawer: GetPlatform.isDesktop || isWideScreen
                  ? Container(
                      constraints: const BoxConstraints(maxWidth: 600),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(10)),
                        border: Border(
                          left: BorderSide(
                              color: Theme.of(context).colorScheme.secondary),
                          top: BorderSide(
                              color: Theme.of(context).colorScheme.secondary),
                        ),
                      ),
                      margin: const EdgeInsets.only(
                        top: 5,
                        bottom: 106,
                      ),
                      child: SizedBox(
                        child: Column(
                          children: [
                            SizedBox(
                              height: 60,
                              child: ColoredBox(
                                color: Theme.of(context).canvasColor,
                                child: Center(
                                    child: Padding(
                                  padding: const EdgeInsets.only(
                                      left: 15.0, right: 15),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                          "${playerController.currentQueue.length} ${'songs'.tr}"),
                                      Text(
                                        "upNext".tr,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                      Row(
                                        children: [
                                          InkWell(
                                            onTap: () {
                                              playerController
                                                  .toggleQueueLoopMode();
                                            },
                                            child: Obx(
                                              () => Container(
                                                height: 30,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 20),
                                                decoration: BoxDecoration(
                                                  color: playerController
                                                          .isQueueLoopModeEnabled
                                                          .isFalse
                                                      ? (isLight
                                                          ? Colors.black
                                                              .withAlpha(14)
                                                          : Colors.white24)
                                                      : (isLight
                                                          ? Colors.black
                                                              .withAlpha(190)
                                                          : Colors.white
                                                              .withOpacity(
                                                                  0.8)),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Center(
                                                    child: Text(
                                                      "queueLoop".tr,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: playerController
                                                                .isQueueLoopModeEnabled
                                                                .isTrue
                                                            ? (isLight
                                                                ? Colors.white
                                                                : Colors.black)
                                                            : null,
                                                      ),
                                                    )),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                              onPressed: () {
                                                if (playerController
                                                    .isShuffleModeEnabled
                                                    .isTrue) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(snackbar(
                                                          context,
                                                          "queueShufflingDeniedMsg"
                                                              .tr,
                                                          size: SanckBarSize
                                                              .BIG));
                                                  return;
                                                }
                                                playerController.shuffleQueue();
                                              },
                                              icon: const Icon(Icons.shuffle)),
                                          IconButton(
                                              onPressed: () {
                                                playerController.clearQueue();
                                              },
                                              icon: const Icon(
                                                  Icons.playlist_remove)),
                                        ],
                                      )
                                    ],
                                  ),
                                )),
                              ),
                            ),
                            const Expanded(
                              child: UpNextQueue(
                                isQueueInSlidePanel: false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : null,
              drawerScrimColor: Colors.transparent,
              body: Stack(
                children: [
                  Obx(() => SlidingUpPanel(
                        onPanelSlide: playerController.panellistener,
                        controller: playerController.playerPanelController,
                        minHeight: playerController.playerPanelMinHeight.value,
                        maxHeight: size.height,
                        // Fully transparent stage: the panel package defaults
                        // to a WHITE background, which filled the collapsed
                        // strip once the player's own backdrop was hidden —
                        // only the mini player card itself must float here,
                        // over the live app content.
                        color: Colors.transparent,
                        boxShadow: const [],
                        isDraggable: !isWideScreen,
                        // While the queue panel is open, only the queue should
                        // react to vertical drags (swipe down = back to the
                        // player, not collapse of the whole player). Evaluated
                        // live on every gesture, so no rebuild is needed.
                        // NOTE: uses panelPosition (> fully collapsed) rather
                        // than isPanelOpen (== 1.0): the latter unlocks as soon
                        // as the queue starts moving down, letting a slow drag
                        // collapse the whole player again.
                        isDragLocked: () =>
                            playerController.queuePanelController.isAttached &&
                            playerController.queuePanelController.panelPosition >
                                0.05,
                        onSwipeUp: () {
                          playerController.queuePanelController.open();
                        },
                        // Free-floating mini player: the full player's own
                        // background (blurred art + gradient) used to peek in
                        // the collapsed strip behind the card, reading as a
                        // dark band glued to the navbar. Offstage hides every
                        // pixel of it until the panel actually slides up,
                        // while keeping it mounted (no remount jank).
                        panel: Obx(
                          () => Visibility(
                            visible:
                                playerController.playerPanelSlide.value > 0.02,
                            maintainState: true,
                            child: const Player(),
                          ),
                        ),
                        body: Column(
                          children: [
                            Expanded(child: ScreenNavigation()),
                          ],
                        ),
                        collapsed: GestureDetector(
                                onTap: playerController.playerPanelController.open,
                                child: const MiniPlayer(),
                              ),
                      )),
                  // Floating collapse button: rendered as the TOP sibling of
                  // the whole player stack, so no widget inside the sliding
                  // panels can ever swallow its clicks (the in-player button
                  // was unreachable on desktop). Desktop only — mobile uses
                  // the swipe-down gesture.
                  //
                  // It rides the panel's own slide animation: opacity and a
                  // slight upward drift track playerPanelSlide continuously,
                  // so it never lingers after the panel collapses (the old
                  // binary flag left a "ghost button" for a few ms).
                  if (GetPlatform.isDesktop)
                    Obx(() {
                      final slide = playerController.playerPanelSlide.value;
                      final visible = slide > 0.01;
                      if (!visible) return const SizedBox.shrink();
                      final t = ((slide - 0.05) / 0.15).clamp(0.0, 1.0);
                      final curve = Curves.easeOutCubic.transform(t);
                      return Positioned(
                        top: 12 - 6 * (1 - curve),
                        left: 14,
                        child: IgnorePointer(
                          ignoring: t < 0.5,
                          child: Opacity(
                            opacity: curve,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap:
                                    playerController.collapsePlayerPanel,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surface
                                        .withOpacity(0.5 * curve),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.keyboard_arrow_down,
                                    color: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.color
                                        ?.withOpacity(curve),
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
              ),
        ),
      ),
    );
  }
}
