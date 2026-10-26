import 'package:buttons_tabbar/buttons_tabbar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:velqi/ui/widgets/loader.dart';
import 'package:velqi/ui/widgets/search_related_widgets.dart';

import '../../navigator.dart';
import '../../widgets/separate_tab_item_widget.dart';
import 'search_result_screen_controller.dart';

class SearchResultScreenBN extends StatelessWidget {
  const SearchResultScreenBN({super.key});

  @override
  Widget build(BuildContext context) {
    final SearchResultScreenController searchResScrController =
        Get.find<SearchResultScreenController>();
    final cs = Theme.of(context).colorScheme;
    final topPadding = context.isLandscape ? 50.0 : 80.0;
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: Column(
          children: [
            // Header row
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Center(
                      child: IconButton(
                        onPressed: () {
                          Get.nestedKey(ScreenNavigationSetup.id)!
                              .currentState!
                              .pop();
                        },
                        icon: const Icon(Icons.arrow_back_ios_new),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "searchRes".tr,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Obx(
                          () => Text(
                            '${'for1'.tr} "${searchResScrController.queryString.value}"',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Results content
            Expanded(
              child: Obx(
                () {
                  if (searchResScrController.isResultContentFetced.isTrue &&
                      searchResScrController.railItems.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "nomatch".tr,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "'${searchResScrController.queryString.value}'",
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    );
                  } else if (searchResScrController
                      .isResultContentFetced.isTrue) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // Modern tab bar
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: ButtonsTabBar(
                            onTap:
                                searchResScrController.onDestinationSelected,
                            controller: searchResScrController.tabController,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 8),
                            backgroundColor:
                                cs.onSurface.withAlpha(30),
                            unselectedBackgroundColor: Colors.transparent,
                            borderWidth: 1,
                            borderColor: cs.outline.withAlpha(60),

                            radius: 10,
                            buttonMargin: const EdgeInsets.only(right: 8),
                            labelStyle: TextStyle(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            unselectedLabelStyle: TextStyle(
                              color: cs.onSurface.withAlpha(150),
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                            tabs: [
                              Tab(text: "results".tr),
                              ...searchResScrController.railItems.map(
                                (item) => Tab(
                                  text: item
                                      .toLowerCase()
                                      .removeAllWhitespace
                                      .tr,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Results content with padding
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8, right: 8),
                            child: TabBarView(
                              controller:
                                  searchResScrController.tabController,
                              children: [
                                const ResultWidget(isv2Used: true),
                                ...searchResScrController.railItems
                                    .map((tabName) {
                                  if (tabName == "Songs" ||
                                      tabName == "Videos") {
                                    return SeparateTabItemWidget(
                                      isResultWidget: true,
                                      hideTitle: true,
                                      items: const [],
                                      title: tabName,
                                      isCompleteList: true,
                                      scrollController: searchResScrController
                                          .scrollControllers[tabName],
                                    );
                                  } else {
                                    return SeparateTabItemWidget(
                                      title: tabName,
                                      hideTitle: true,
                                      items: const [],
                                      scrollController: searchResScrController
                                          .scrollControllers[tabName],
                                    );
                                  }
                                }),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    return const Center(
                      child: LoadingIndicator(),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
