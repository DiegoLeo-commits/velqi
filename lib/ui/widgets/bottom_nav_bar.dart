import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:velqi/ui/screens/Home/home_screen_controller.dart';

/// Docked bottom navigation bar.
///
/// A full-width bar (no floating margins) whose surface is designed to
/// visually merge with the mini player above it: both share the same solid
/// background, so when a song is playing they read as ONE bottom dock.
class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    final homeScreenController = Get.find<HomeScreenController>();
    final cs = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;

    final pillBg = isLight ? Colors.black : Colors.white;
    final pillFg = isLight ? Colors.white : Colors.black;
    final iconUnselected =
        isLight ? const Color(0xFF9A9AA2) : const Color(0xFF8A8A92);
    final barBg = isLight ? const Color(0xFFF4F4F7) : const Color(0xFF000000);

    final destinations = <(IconData, IconData)>[
      (Icons.home_outlined, Icons.home_rounded),
      (Icons.search_outlined, Icons.search_rounded),
      (Icons.library_music_outlined, Icons.library_music_rounded),
      (Icons.settings_outlined, Icons.settings_rounded),
    ];

    return Obx(() {
      final currentTab = homeScreenController.tabIndex.toInt();
      // Map 4 bottom bar items (0..3) to underlying screen indices (1..4)
      final selected = (currentTab >= 1 && currentTab <= 4) ? currentTab - 1 : 0;
      return Container(
        decoration: BoxDecoration(
          color: barBg,
          border: Border(
            top: BorderSide(
              color: cs.outline.withOpacity(0.08),
              width: 0.5,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Expanded(
                    child: _NavDot(
                      icon: destinations[i].$1,
                      selectedIcon: destinations[i].$2,
                      isSelected: selected == i,
                      pillBg: pillBg,
                      pillFg: pillFg,
                      iconUnselected: iconUnselected,
                      onTap: () =>
                          homeScreenController.onBottonBarTabSelected(i + 1),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _NavDot extends StatelessWidget {
  const _NavDot({
    required this.icon,
    required this.selectedIcon,
    required this.isSelected,
    required this.pillBg,
    required this.pillFg,
    required this.iconUnselected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final bool isSelected;
  final Color pillBg;
  final Color pillFg;
  final Color iconUnselected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isSelected ? pillBg : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: Icon(
                  isSelected ? selectedIcon : icon,
                  key: ValueKey(isSelected),
                  size: 21,
                  color: isSelected ? pillFg : iconUnselected,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
