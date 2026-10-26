import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../Search/components/desktop_search_bar.dart';
import '/ui/screens/Search/search_screen_controller.dart';
import '/ui/widgets/animated_screen_transition.dart';
import '/ui/widgets/velqi_mascot.dart';
import '../Library/library_combined.dart';
import '../../widgets/side_nav_bar.dart';
import '../Library/library.dart';
import '../Search/search_screen.dart';
import '../Settings/settings_screen_controller.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/create_playlist_dialog.dart';
import '../../navigator.dart';
import '../../widgets/content_list_widget.dart';
import '../../widgets/quickpickswidget.dart';
import '../../widgets/shimmer_widgets/home_shimmer.dart';
import '../../widgets/snackbar.dart';
import 'home_screen_controller.dart';
import '../Settings/settings_screen.dart';
import '../Info/info_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    final HomeScreenController homeScreenController =
        Get.find<HomeScreenController>();
    final SettingsScreenController settingsScreenController =
        Get.find<SettingsScreenController>();

    return Scaffold(
        floatingActionButton: Obx(
          () => ((homeScreenController.tabIndex.value == 1 &&
                          !GetPlatform.isDesktop) ||
                      homeScreenController.tabIndex.value == 3) &&
                  settingsScreenController.isBottomNavBarEnabled.isFalse
              ? Obx(
                  () => Padding(
                    padding: EdgeInsets.only(
                        bottom: playerController.playerPanelMinHeight.value >
                                Get.mediaQuery.padding.bottom
                            ? playerController.playerPanelMinHeight.value -
                                Get.mediaQuery.padding.bottom
                            : playerController.playerPanelMinHeight.value),
                    child: SizedBox(
                      height: 60,
                      width: 60,
                      child: FittedBox(
                        child: FloatingActionButton(
                            focusElevation: 0,
                            shape: const RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(14))),
                            elevation: 0,
                            onPressed: () async {
                              if (homeScreenController.tabIndex.value == 3) {
                                showDialog(
                                    context: context,
                                    builder: (context) =>
                                        const CreateNRenamePlaylistPopup());
                              } else {
                                Get.toNamed(ScreenNavigationSetup.searchScreen,
                                    id: ScreenNavigationSetup.id);
                              }
                              // Velqi cache directories
                            },
                            child: Icon(homeScreenController.tabIndex.value == 3
                                ? Icons.add
                                : Icons.search)),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        body: Obx(
          () => Row(
            children: <Widget>[
              // create a navigation rail
              settingsScreenController.isBottomNavBarEnabled.isFalse
                  ? const SideNavBar()
                  : const SizedBox(
                      width: 0,
                    ),
              //const VerticalDivider(thickness: 1, width: 2),
              Expanded(
                child: Obx(() => AnimatedScreenTransition(
                    enabled: settingsScreenController
                        .isTransitionAnimationDisabled.isFalse,
                    resverse: homeScreenController.reverseAnimationtransiton,
                    horizontalTransition:
                        settingsScreenController.isBottomNavBarEnabled.isTrue,
                    child: Center(
                      key: ValueKey<int>(homeScreenController.tabIndex.value),
                      child: const Body(),
                    ))),
              ),
            ],
          ),
        ));
  }
}

class Body extends StatelessWidget {
  const Body({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final homeScreenController = Get.find<HomeScreenController>();
    final settingsScreenController = Get.find<SettingsScreenController>();
    final size = MediaQuery.of(context).size;
    final topPadding = GetPlatform.isDesktop
        ? 95.0
        : context.isLandscape
            ? 60.0
            : size.height < 750
                ? 85.0
                : 90.0;
    final leftPadding =
        settingsScreenController.isBottomNavBarEnabled.isTrue ? 16.0 : 4.0;
    if (homeScreenController.tabIndex.value == 0) {
      return InfoScreen(
          isBottomNavActive:
              settingsScreenController.isBottomNavBarEnabled.isTrue);
    } else if (homeScreenController.tabIndex.value == 1) {
      return Padding(
        padding: EdgeInsets.only(left: leftPadding),
        child: Stack(
          children: [
            GestureDetector(
              onTap: () {
                // for Desktop search bar
                if (GetPlatform.isDesktop) {
                  final sscontroller = Get.find<SearchScreenController>();
                  if (sscontroller.focusNode.hasFocus) {
                    sscontroller.focusNode.unfocus();
                  }
                }
              },
              child: Obx(
                () => homeScreenController.networkError.isTrue
                    ? SizedBox(
                        height: MediaQuery.of(context).size.height - 180,
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                "home".tr,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            Expanded(
                              child: VelqiErrorState(
                                message: "networkError1".tr,
                                onRetry: () {
                                  homeScreenController
                                      .loadContentFromNetwork();
                                },
                                mascotSize: 140,
                              ),
                            )
                          ],
                        ),
                      )
                    : Obx(() {
                        // dispose all detachached scroll controllers
                        homeScreenController.disposeDetachedScrollControllers();
                        final items = homeScreenController
                                .isContentFetched.value
                            ? [
                                const GreetingHeader(),
                                if (homeScreenController
                                    .quickPicks.value.songList.isNotEmpty)
                                  Obx(() {
                                    final scrollController = ScrollController();
                                    homeScreenController
                                        .contentScrollControllers
                                        .add(scrollController);
                                    return QuickPicksWidget(
                                        content: homeScreenController
                                            .quickPicks.value,
                                        scrollController: scrollController);
                                  }),
                                ...getWidgetList(
                                    homeScreenController.middleContent,
                                    homeScreenController),
                                ...getWidgetList(
                                    homeScreenController.fixedContent,
                                    homeScreenController)
                              ]
                            : [
                                // While the embedded backend cold-starts
                                // (first install / slow emulators can take
                                // a while) reassure the user that Velqi is
                                // actually working and not frozen.
                                if (homeScreenController
                                    .showLoadingHint.isTrue)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 14),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Flexible(
                                          child: Text(
                                            "Preparando Velqi…",
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withOpacity(0.55),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                const HomeShimmer(),
                              ];
                        return ListView.builder(
                          padding:
                              EdgeInsets.only(bottom: 200, top: topPadding),
                          itemCount: items.length,
                          itemBuilder: (context, index) => items[index],
                        );
                      }),
              ),
            ),
            if (GetPlatform.isDesktop)
              Align(
                alignment: Alignment.topCenter,
                child: LayoutBuilder(builder: (context, constraints) {
                  return SizedBox(
                    width: constraints.maxWidth > 800
                        ? 800
                        : constraints.maxWidth - 40,
                    child: const Padding(
                        padding: EdgeInsets.only(top: 15.0),
                        child: DesktopSearchBar()),
                  );
                }),
              )
          ],
        ),
      );
    } else if (homeScreenController.tabIndex.value == 2) {
      return settingsScreenController.isBottomNavBarEnabled.isTrue
          ? const SearchScreen()
          : const SongsLibraryWidget();
    } else if (homeScreenController.tabIndex.value == 3) {
      return settingsScreenController.isBottomNavBarEnabled.isTrue
          ? const CombinedLibrary()
          : const PlaylistNAlbumLibraryWidget(isAlbumContent: false);
    } else if (homeScreenController.tabIndex.value == 4) {
      return settingsScreenController.isBottomNavBarEnabled.isTrue
          ? const SettingsScreen(isBottomNavActive: true)
          : const PlaylistNAlbumLibraryWidget();
    } else if (homeScreenController.tabIndex.value == 5) {
      return const LibraryArtistWidget();
    } else if (homeScreenController.tabIndex.value == 6) {
      return const SettingsScreen();
    } else {
      return Center(
        child: Text("${homeScreenController.tabIndex.value}"),
      );
    }
  }

  List<Widget> getWidgetList(
      dynamic list, HomeScreenController homeScreenController) {
    return list
        .map((content) {
          final scrollController = ScrollController();
          homeScreenController.contentScrollControllers.add(scrollController);
          return ContentListWidget(
              content: content, scrollController: scrollController);
        })
        .whereType<Widget>()
        .toList();
  }
}

class GreetingHeader extends StatelessWidget {
  const GreetingHeader({super.key});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    final lang = Get.locale?.languageCode ?? 'es';
    if (lang == 'es') {
      if (hour < 6) return '¡Buenas noches!';
      if (hour < 12) return '¡Buenos días!';
      if (hour < 19) return '¡Buenas tardes!';
      return '¡Buenas noches!';
    } else {
      if (hour < 6) return 'Good night!';
      if (hour < 12) return 'Good morning!';
      if (hour < 18) return 'Good afternoon!';
      return 'Good evening!';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDesktop = GetPlatform.isDesktop;
    
    return Padding(
      padding: EdgeInsets.only(
        left: 14.0, 
        right: 14.0, 
        top: isDesktop ? 20.0 : 16.0, 
        bottom: 12.0
      ),
      child: Row(
        children: [
          // Decorative music avatar with gradient & shadow
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  cs.primary,
                  cs.primary.withOpacity(0.6),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.music_note_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Dynamic Greeting
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _getGreeting(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  Get.locale?.languageCode == 'es' 
                      ? 'Disfruta tu música libre' 
                      : 'Enjoy your free music',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // ⚡ Modo Rápido quick toggle (also in Ajustes → Avanzado)
          Obx(() {
            final fast = Get.find<SettingsScreenController>().fastMode.isTrue;
            return Tooltip(
              message:
                  fast ? 'Modo Rápido activado' : 'Activar Modo Rápido',
              child: InkWell(
                onTap: () => _toggleFastMode(context),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: fast
                        ? cs.primary.withAlpha(40)
                        : Colors.transparent,
                    border: Border.all(
                      color: fast
                          ? cs.primary.withAlpha(130)
                          : cs.outline.withAlpha(30),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    fast ? Icons.bolt_rounded : Icons.bolt_outlined,
                    color: fast
                        ? cs.primary
                        : cs.onSurface.withOpacity(0.55),
                    size: 20,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _toggleFastMode(BuildContext context) {
    final controller = Get.find<SettingsScreenController>();
    final val = !controller.fastMode.value;
    controller.toggleFastMode(val);
    ScaffoldMessenger.of(context).showSnackBar(snackbar(
      context,
      val
          ? '⚡ Modo Rápido activado: menor calidad y menos esperas'
          : 'Modo Rápido desactivado',
      size: SanckBarSize.SMALL,
      duration: const Duration(seconds: 2),
    ));
  }
}
