import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'components/search_item.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/ui/widgets/velqi_mascot.dart';
import '../../widgets/modified_text_field.dart';
import '/ui/navigator.dart';
import 'search_screen_controller.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final searchScreenController = Get.put(SearchScreenController());
    final settingsScreenController = Get.find<SettingsScreenController>();
    final cs = Theme.of(context).colorScheme;
    final topPadding = context.isLandscape ? 50.0 : 80.0;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Obx(
        () => Row(
          children: [
            settingsScreenController.isBottomNavBarEnabled.isFalse
                ? Container(
                    width: 60,
                    color:
                        Theme.of(context).navigationRailTheme.backgroundColor,
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: topPadding),
                          child: IconButton(
                            icon: Icon(
                              Icons.arrow_back_ios_new,
                              color: Theme.of(context)
                                  .textTheme
                                  .titleMedium!
                                  .color,
                            ),
                            onPressed: () {
                              Get.nestedKey(ScreenNavigationSetup.id)!
                                  .currentState!
                                  .pop();
                            },
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(
                    width: 15,
                  ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: topPadding, left: 5, right: 12),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "search".tr,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Styled search field with border
                    IgnorePointer(
                      ignoring: !searchScreenController.isBackendReady.value,
                      child: Opacity(
                        opacity: searchScreenController.isBackendReady.value
                            ? 1.0
                            : 0.4,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: cs.outline.withAlpha(80), width: 1.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ModifiedTextField(
                            textCapitalization: TextCapitalization.sentences,
                            controller:
                                searchScreenController.textInputController,
                            textInputAction: TextInputAction.search,
                            onChanged: searchScreenController.onChanged,
                            onSubmitted: (val) {
                              if (val.contains("https://")) {
                                searchScreenController
                                    .filterLinks(Uri.parse(val));
                                searchScreenController.reset();
                                return;
                              }
                              Get.toNamed(
                                  ScreenNavigationSetup.searchResultScreen,
                                  id: ScreenNavigationSetup.id,
                                  arguments: val);
                              searchScreenController.addToHistryQueryList(val);
                            },
                            autofocus: settingsScreenController
                                .isBottomNavBarEnabled.isFalse,
                            cursorColor:
                                Theme.of(context).textTheme.bodySmall!.color,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 14),
                              focusColor: Colors.white,
                              hintText: searchScreenController
                                      .isBackendReady.value
                                  ? "searchDes".tr
                                  : 'Velqi está descargando recursos...',
                              border: InputBorder.none,
                              suffixIcon: IconButton(
                                onPressed: searchScreenController.reset,
                                icon: const Icon(Icons.close, size: 19),
                                splashRadius: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Obx(() {
                        final isEmpty = searchScreenController
                                .suggestionList.isEmpty ||
                            searchScreenController.textInputController.text ==
                                "";
                        final list = isEmpty
                            ? searchScreenController.historyQuerylist.toList()
                            : searchScreenController.suggestionList.toList();
                        if (isEmpty && list.isEmpty) {
                          return const VelqiMascot(
                            pose: VelqiPose.headphones,
                            size: 140,
                            customText: 'Busca tu música favorita',
                          );
                        }
                        return ListView(
                          padding: const EdgeInsets.only(top: 4, bottom: 400),
                          physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics()),
                          children: searchScreenController.urlPasted.isTrue
                              ? [
                                  Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: cs.outline.withAlpha(35),
                                          width: 1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: InkWell(
                                      onTap: () {
                                        searchScreenController.filterLinks(
                                            Uri.parse(searchScreenController
                                                .textInputController.text));
                                        searchScreenController.reset();
                                      },
                                      borderRadius: BorderRadius.circular(10),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16.0),
                                        child: Center(
                                          child: Text(
                                            "urlSearchDes".tr,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ]
                              : list
                                  .map((item) => SearchItem(
                                      queryString: item,
                                      isHistoryString: isEmpty))
                                  .toList(),
                        );
                      }),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
