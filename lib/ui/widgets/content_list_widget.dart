import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../screens/Search/search_result_screen_controller.dart';
import '/ui/widgets/content_list_widget_item.dart';

/// Netflix-style section row with horizontal scrolling cards.
class ContentListWidget extends StatelessWidget {
  const ContentListWidget(
      {super.key,
      this.content,
      this.isHomeContent = true,
      this.scrollController});

  final dynamic content;
  final bool isHomeContent;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final isAlbumContent = content.runtimeType.toString() == "AlbumContent";
    final size = MediaQuery.of(context).size;

    return Container(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title with "See all" button
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 8, bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  !isHomeContent && content.title.length > 20
                      ? "${content.title.substring(0, 20)}..."
                      : content.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (!isHomeContent)
                  TextButton(
                    onPressed: () {
                      final scrresController =
                          Get.find<SearchResultScreenController>();
                      scrresController.viewAllCallback(content.title);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("viewAll".tr,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall!
                                .copyWith(fontSize: 12)),
                        const SizedBox(width: 2),
                        Icon(Icons.arrow_forward_ios,
                            size: 10,
                            color: Theme.of(context).textTheme.titleSmall!.color),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Horizontal scrollable cards
          SizedBox(
            height: size.width > 600 ? 240 : 210,
            child: Scrollbar(
              thickness: GetPlatform.isDesktop ? null : 0,
              controller: scrollController,
              child: ListView.separated(
                controller: scrollController,
                physics: const BouncingScrollPhysics(),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 4, right: 16),
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 12),
                itemCount: isAlbumContent
                    ? content.albumList.length
                    : content.playlistList.length,
                itemBuilder: (_, index) {
                  if (isAlbumContent) {
                    return ContentListItem(content: content.albumList[index]);
                  }
                  return ContentListItem(
                      content: content.playlistList[index]);
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
