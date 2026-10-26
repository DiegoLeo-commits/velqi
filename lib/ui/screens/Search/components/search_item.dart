import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '/ui/screens/Search/search_screen_controller.dart';

import '../../../navigator.dart';

class SearchItem extends StatelessWidget {
  final String queryString;
  final bool isHistoryString;
  const SearchItem(
      {super.key, required this.queryString, required this.isHistoryString});

  @override
  Widget build(BuildContext context) {
    final searchScreenController = Get.find<SearchScreenController>();
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline.withAlpha(35), width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 12, right: 8),
        onTap: () {
          Get.toNamed(ScreenNavigationSetup.searchResultScreen,
              id: ScreenNavigationSetup.id, arguments: queryString);
          searchScreenController.addToHistryQueryList(queryString);
          if (GetPlatform.isDesktop) {
            searchScreenController.focusNode.unfocus();
          }
        },
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cs.secondary.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isHistoryString ? Icons.history : Icons.search,
            size: 18,
            color: cs.onSurface,
          ),
        ),
        minLeadingWidth: 20,
        dense: true,
        // maxLines + ellipsis: long queries must never push the trailing
        // buttons off-screen (the classic "RIGHT OVERFLOWED BY X PIXELS").
        title: Text(
          queryString,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
        // Intrinsic-size row (no fixed SizedBox): two icon buttons always
        // fit, whatever the density/scaling — no horizontal overflow.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isHistoryString)
              IconButton(
                iconSize: 16,
                splashRadius: 16,
                visualDensity: const VisualDensity(horizontal: -2),
                onPressed: () {
                  searchScreenController.removeQueryFromHistory(queryString);
                },
                icon: Icon(
                  Icons.clear,
                  color: cs.onSurface.withAlpha(120),
                ),
              ),
            IconButton(
              iconSize: 18,
              splashRadius: 16,
              visualDensity: const VisualDensity(horizontal: -2),
              onPressed: () {
                searchScreenController.suggestionInput(queryString);
              },
              icon: Icon(
                Icons.north_west,
                color: cs.onSurface.withAlpha(120),
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
