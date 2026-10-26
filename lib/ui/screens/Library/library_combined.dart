import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/create_playlist_dialog.dart';
import 'library.dart';

class CombinedLibrary extends StatelessWidget {
  const CombinedLibrary({super.key});

  @override
  Widget build(BuildContext context) {
    final con = Get.put(CombinedLibraryController2());
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        toolbarHeight: 75,
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(top: 35.0, right: 12),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: cs.outline.withAlpha(60), width: 1.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: IconButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => const CreateNRenamePlaylistPopup(),
                  );
                },
                icon: const Icon(Icons.add, size: 22),
                splashRadius: 18,
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              ),
            ),
          ),
        ],
        title: Padding(
          padding: const EdgeInsets.only(top: 40.0, left: 4),
          child:
              Text('library'.tr, style: Theme.of(context).textTheme.titleLarge),
        ),
      ),
      body: Column(
        children: [
          // ── Section buttons ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Obx(() => Row(
                  children: [
                    _sectionBtn(context, con, 0, Icons.music_note, "songs".tr),
                    const SizedBox(width: 8),
                    _sectionBtn(context, con, 1, Icons.playlist_play, "playlists".tr),
                    const SizedBox(width: 8),
                    _sectionBtn(context, con, 2, Icons.album, "albums".tr),
                    const SizedBox(width: 8),
                    _sectionBtn(context, con, 3, Icons.person, "artists".tr),
                  ],
                )),
          ),
          // ── Content ─────────────────────────────────────────────────
          Expanded(
            child: Obx(() {
              switch (con.selectedIndex.value) {
                case 0:
                  return const SongsLibraryWidget(isBottomNavActive: true);
                case 1:
                  return const PlaylistNAlbumLibraryWidget(
                      isAlbumContent: false, isBottomNavActive: true);
                case 2:
                  return const PlaylistNAlbumLibraryWidget(
                      isBottomNavActive: true);
                case 3:
                  return const LibraryArtistWidget(isBottomNavActive: true);
                default:
                  return const SizedBox.shrink();
              }
            }),
          ),
        ],
      ),
    );
  }

  Widget _sectionBtn(BuildContext context, CombinedLibraryController2 con,
      int index, IconData icon, String label) {
    final isActive = con.selectedIndex.value == index;
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: () => con.selectedIndex.value = index,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? cs.onSurface.withAlpha(25) : Colors.transparent,
            border: Border.all(
              color: isActive
                  ? cs.onSurface.withAlpha(60)
                  : cs.outline.withAlpha(40),
              width: isActive ? 1.2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: isActive
                    ? cs.onSurface
                    : cs.onSurface.withAlpha(120),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive
                      ? cs.onSurface
                      : cs.onSurface.withAlpha(120),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CombinedLibraryController2 extends GetxController {
  final selectedIndex = 0.obs;
}
