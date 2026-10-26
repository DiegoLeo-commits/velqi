import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:velqi/utils/helper.dart';
import 'package:velqi/utils/lang_mapping.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/common_dialog_widget.dart';
import '../../widgets/cust_switch.dart';
import '../../widgets/discord_mark.dart';
import '../../widgets/export_file_dialog.dart';
import '../../widgets/backup_dialog.dart';
import '../../widgets/restore_dialog.dart';
import '../../widgets/snackbar.dart';
import '/services/discord_rpc_service.dart';
import '/services/music_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/utils/theme_controller.dart';
import 'settings_screen_controller.dart';

// ── Shared helpers ──────────────────────────────────────────────────────────

Widget _settingsDropdown(ThemeData theme, Widget child) {
  final cs = theme.colorScheme;
  final isLight = theme.brightness == Brightness.light;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
          color: cs.outline.withAlpha(isLight ? 40 : 60), width: 1),
    ),
    child: child,
  );
}

Widget _settingsOutlinedButton(BuildContext context, String label,
    {VoidCallback? onPressed}) {
  final cs = Theme.of(context).colorScheme;
  final isLight = Theme.of(context).brightness == Brightness.light;
  return OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      side: BorderSide(
          color: cs.outline.withAlpha(isLight ? 70 : 100), width: 1.2),
      foregroundColor: cs.onSurface,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    child: Text(label,
        style:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
  );
}

/// Wraps a ListTile in a bordered container matching the app's design system.
Widget _borderedTile({
  required BuildContext context,
  required Widget title,
  Widget? subtitle,
  Widget? trailing,
  VoidCallback? onTap,
  bool isThreeLine = false,
}) {
  final cs = Theme.of(context).colorScheme;
  final isLight = Theme.of(context).brightness == Brightness.light;
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(
          color: cs.outline.withAlpha(isLight ? 18 : 25), width: 1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.only(left: 10, right: 12),
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      onTap: onTap,
      isThreeLine: isThreeLine,
      visualDensity: const VisualDensity(vertical: -2),
    ),
  );
}

// ── Category system ─────────────────────────────────────────────────────────
//
// Settings is organised as categories (Netflix-style horizontal cards on the
// root page) that drill down into their own sub-page. Every option lives in
// exactly one category; platform-specific options are filtered at build time
// so Android-only tiles never appear on desktop and vice versa.

class _CategorySpec {
  const _CategorySpec({
    required this.id,
    required this.title,
    required this.options,
    this.icon,
    this.usesDiscordMark = false,
  });

  final SettingsCategoryId id;
  final String Function() title;
  final List<Widget> Function(BuildContext context, SettingsScreenController c)
      options;
  final IconData? icon;
  final bool usesDiscordMark;
}

List<_CategorySpec> _categorySpecs(bool isDesktop) => [
      _CategorySpec(
        id: SettingsCategoryId.playback,
        title: () => "music&Playback".tr,
        icon: Icons.graphic_eq_rounded,
        options: _playbackOptions,
      ),
      _CategorySpec(
        id: SettingsCategoryId.appearance,
        title: () => "personalisation".tr,
        icon: Icons.palette_outlined,
        options: _appearanceOptions,
      ),
      _CategorySpec(
        id: SettingsCategoryId.content,
        title: () => "content".tr,
        icon: Icons.dashboard_outlined,
        options: _contentOptions,
      ),
      _CategorySpec(
        id: SettingsCategoryId.downloads,
        title: () => "download".tr,
        icon: Icons.download_outlined,
        options: _downloadsOptions,
      ),
      _CategorySpec(
        id: SettingsCategoryId.advanced,
        title: () => "advanced".tr,
        icon: Icons.tune,
        options: _advancedOptions,
      ),
      _CategorySpec(
        id: SettingsCategoryId.backup,
        title: () => "${"backup".tr} & ${"restore".tr}",
        icon: Icons.settings_backup_restore,
        options: _backupOptions,
      ),
      if (isDesktop)
        _CategorySpec(
          id: SettingsCategoryId.integrations,
          title: () => "integrations".tr,
          usesDiscordMark: true,
          options: _integrationsOptions,
        ),
    ];

// ── Option builders (one per category) ──────────────────────────────────────

List<Widget> _playbackOptions(
    BuildContext context, SettingsScreenController c) {
  final isDesktop = GetPlatform.isDesktop;
  return [
    _borderedTile(
      context: context,
      title: Text("streamingQuality".tr),
      subtitle: Text("streamingQualityDes".tr,
          style: Theme.of(context).textTheme.bodyMedium),
      trailing: Obx(
        () => _settingsDropdown(
          Theme.of(context),
          DropdownButton(
            dropdownColor: Theme.of(context).cardColor,
            underline: const SizedBox.shrink(),
            value: c.streamingQuality.value,
            items: [
              DropdownMenuItem(value: AudioQuality.Low, child: Text("low".tr)),
              DropdownMenuItem(
                value: AudioQuality.High,
                child: Text("high".tr),
              ),
            ],
            onChanged: c.setStreamingQuality,
          ),
        ),
      ),
    ),
    // Mobile only: on-demand song caching (desktop streams live instead).
    if (!isDesktop)
      _borderedTile(
        context: context,
        title: Text("cacheSongs".tr),
        subtitle: Text("cacheSongsDes".tr,
            style: Theme.of(context).textTheme.bodyMedium),
        trailing: Obx(
          () => CustSwitch(
              value: c.cacheSongs.value,
              onChanged: c.toggleCachingSongsValue),
        ),
      ),
    // Desktop only: keep playing with the window closed to tray.
    if (isDesktop)
      _borderedTile(
        context: context,
        title: Text("backgroundPlay".tr),
        subtitle: Text("backgroundPlayDes".tr,
            style: Theme.of(context).textTheme.bodyMedium),
        trailing: Obx(
          () => CustSwitch(
              value: c.backgroundPlayEnabled.value,
              onChanged: c.toggleBackgroundPlay),
        ),
      ),
    _borderedTile(
      context: context,
      title: Text("keepScreenOnWhilePlaying".tr),
      subtitle: Text("keepScreenOnWhilePlayingDes".tr,
          style: Theme.of(context).textTheme.bodyMedium),
      trailing: Obx(
        () => CustSwitch(
            value: c.keepScreenAwake.value,
            onChanged: c.toggleKeepScreenAwake),
      ),
    ),
    _borderedTile(
      context: context,
      title: Text("restoreLastPlaybackSession".tr),
      subtitle: Text("restoreLastPlaybackSessionDes".tr,
          style: Theme.of(context).textTheme.bodyMedium),
      trailing: Obx(
        () => CustSwitch(
            value: c.restorePlaybackSession.value,
            onChanged: c.toggleRestorePlaybackSession),
      ),
    ),
    _borderedTile(
      context: context,
      title: Text("autoOpenPlayer".tr),
      subtitle: Text("autoOpenPlayerDes".tr,
          style: Theme.of(context).textTheme.bodyMedium),
      trailing: Obx(
        () => CustSwitch(
            value: c.autoOpenPlayer.value,
            onChanged: c.toggleAutoOpenPlayer),
      ),
    ),
    // Mobile only: system equalizer is exposed by the Android player.
    if (!isDesktop)
      _borderedTile(
        context: context,
        title: Text("equalizer".tr),
        subtitle: Text("equalizerDes".tr,
            style: Theme.of(context).textTheme.bodyMedium),
        onTap: () async {
          try {
            await Get.find<PlayerController>().openEqualizer();
          } catch (e) {
            printERROR(e);
          }
        },
      ),
  ];
}

List<Widget> _appearanceOptions(
    BuildContext context, SettingsScreenController c) {
  return [
    // Dark-only theme switch removed: Velqi always renders the dark theme
    // (see ThemeController.changeThemeModeType).
    _borderedTile(
      context: context,
      title: Text("language".tr),
      subtitle: Text("languageDes".tr,
          style: Theme.of(context).textTheme.bodyMedium),
      trailing: Obx(
        () => _settingsDropdown(
          Theme.of(context),
          DropdownButton(
            menuMaxHeight: Get.height - 250,
            dropdownColor: Theme.of(context).cardColor,
            underline: const SizedBox.shrink(),
            style: Theme.of(context).textTheme.titleSmall,
            value: c.currentAppLanguageCode.value,
            items: langMap.entries
                .map((lang) => DropdownMenuItem(
                      value: lang.key,
                      child: Text(lang.value),
                    ))
                .whereType<DropdownMenuItem<String>>()
                .toList(),
            selectedItemBuilder: (context) => langMap.entries
                .map<Widget>((item) {
              return Container(
                alignment: Alignment.centerRight,
                constraints: const BoxConstraints(minWidth: 50),
                child: Text(item.value),
              );
            }).toList(),
            onChanged: c.setAppLanguage,
          ),
        ),
      ),
    ),
    _borderedTile(
      context: context,
      title: Text("disableTransitionAnimation".tr),
      subtitle: Text("disableTransitionAnimationDes".tr,
          style: Theme.of(context).textTheme.bodyMedium),
      trailing: Obx(
        () => CustSwitch(
            value: c.isTransitionAnimationDisabled.isTrue,
            onChanged: c.disableTransitionAnimation),
      ),
    ),
    _borderedTile(
      context: context,
      title: Text("enableSlidableAction".tr),
      subtitle: Text("enableSlidableActionDes".tr,
          style: Theme.of(context).textTheme.bodyMedium),
      trailing: Obx(
        () => CustSwitch(
            value: c.slidableActionEnabled.isTrue,
            onChanged: c.toggleSlidableAction),
      ),
    ),
  ];
}

List<Widget> _contentOptions(
    BuildContext context, SettingsScreenController c) {
  return [
    _borderedTile(
      context: context,
      title: Text("homeContentCount".tr),
      subtitle: Text("homeContentCountDes".tr,
          style: Theme.of(context).textTheme.bodyMedium),
      trailing: Obx(
        () => _settingsDropdown(
          Theme.of(context),
          DropdownButton(
            dropdownColor: Theme.of(context).cardColor,
            underline: const SizedBox.shrink(),
            value: c.noOfHomeScreenContent.value,
            items: ([3, 5, 7, 9, 11])
                .map((e) =>
                    DropdownMenuItem(value: e, child: Text("$e")))
                .toList(),
            onChanged: c.setContentNumber,
          ),
        ),
      ),
    ),
    _borderedTile(
      context: context,
      title: Text("cacheHomeScreenData".tr),
      subtitle: Text("cacheHomeScreenDataDes".tr,
          style: Theme.of(context).textTheme.bodyMedium),
      trailing: Obx(
        () => CustSwitch(
            value: c.cacheHomeScreenData.value,
            onChanged: c.toggleCacheHomeScreenData),
      ),
    ),
    _borderedTile(
      context: context,
      title: Text("clearImgCache".tr),
      subtitle: Text("clearImgCacheDes".tr,
          style: Theme.of(context).textTheme.bodyMedium),
      isThreeLine: true,
      onTap: () {
        c.clearImagesCache().then((_) => ScaffoldMessenger.of(Get.context!)
            .showSnackBar(snackbar(Get.context!, "clearImgCacheAlert".tr,
                size: SanckBarSize.BIG)));
      },
    ),
  ];
}

List<Widget> _downloadsOptions(
    BuildContext context, SettingsScreenController c) {
  return [
    _borderedTile(
      context: context,
      title: Text("autoDownFavSong".tr),
      subtitle: Text("autoDownFavSongDes".tr,
          style: Theme.of(context).textTheme.bodyMedium),
      trailing: Obx(
        () => CustSwitch(
            value: c.autoDownloadFavoriteSongEnabled.value,
            onChanged: c.toggleAutoDownloadFavoriteSong),
      ),
    ),
    _borderedTile(
      context: context,
      title: Text("downloadingFormat".tr),
      subtitle: Text("downloadingFormatDes".tr,
          style: Theme.of(context).textTheme.bodyMedium),
      trailing: Obx(
        () => _settingsDropdown(
          Theme.of(context),
          DropdownButton(
            dropdownColor: Theme.of(context).cardColor,
            underline: const SizedBox.shrink(),
            value: c.downloadingFormat.value,
            items: const [
              DropdownMenuItem(value: "opus", child: Text("Opus/Ogg")),
              DropdownMenuItem(
                value: "m4a",
                child: Text("M4a"),
              ),
            ],
            onChanged: c.changeDownloadingFormat,
          ),
        ),
      ),
    ),
    _borderedTile(
      context: context,
      title: Text("downloadLocation".tr),
      subtitle: Obx(() => Text(
          c.isCurrentPathsupportDownDir
              ? "In App storage directory"
              : c.downloadLocationPath.value,
          style: Theme.of(context).textTheme.bodyMedium)),
      trailing: _settingsOutlinedButton(
        context,
        "reset".tr,
        onPressed: () {
          c.resetDownloadLocation();
        },
      ),
      onTap: () async {
        c.setDownloadLocation();
      },
    ),
    // Export belongs with downloads — it was buried in "Advanced" before.
    _borderedTile(
      context: context,
      title: Text("exportDowloadedFiles".tr),
      subtitle: Text("exportDowloadedFilesDes".tr,
          style: Theme.of(context).textTheme.bodyMedium),
      isThreeLine: true,
      onTap: () => showDialog(
        context: context,
        builder: (context) => const ExportFileDialog(),
      ).whenComplete(() => Get.delete<ExportFileDialogController>()),
    ),
    _borderedTile(
      context: context,
      title: Text("exportedFileLocation".tr),
      subtitle: Obx(() => Text(c.exportLocationPath.value,
          style: Theme.of(context).textTheme.bodyMedium)),
      onTap: () async {
        c.setExportedLocation();
      },
    ),
  ];
}

List<Widget> _advancedOptions(
    BuildContext context, SettingsScreenController c) {
  return [
    // Android only: loudness normalization hook lives in the native player.
    if (GetPlatform.isAndroid)
      _borderedTile(
        context: context,
        title: Text("loudnessNormalization".tr),
        subtitle: Text("loudnessNormalizationDes".tr,
            style: Theme.of(context).textTheme.bodyMedium),
        trailing: Obx(
          () => CustSwitch(
              value: c.loudnessNormalizationEnabled.value,
              onChanged: c.toggleLoudnessNormalization),
        ),
      ),
    // Mobile only.
    if (!GetPlatform.isDesktop)
      _borderedTile(
        context: context,
        title: Text("skipSilence".tr),
        subtitle: Text("skipSilenceDes".tr,
            style: Theme.of(context).textTheme.bodyMedium),
        trailing: Obx(
          () => CustSwitch(
              value: c.skipSilenceEnabled.value,
              onChanged: c.toggleSkipSilence),
        ),
      ),
    _borderedTile(
      context: context,
      title: Text("fastModeTitle".tr),
      subtitle: Text(
        "fastModeDes".tr,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      isThreeLine: true,
      trailing: Obx(
        () => CustSwitch(
          value: c.fastMode.value,
          onChanged: c.toggleFastMode,
        ),
      ),
    ),
    // Mobile only.
    if (!GetPlatform.isDesktop)
      _borderedTile(
        context: context,
        title: Text("stopMusicOnTaskClear".tr),
        subtitle: Text("stopMusicOnTaskClearDes".tr,
            style: Theme.of(context).textTheme.bodyMedium),
        trailing: Obx(
          () => CustSwitch(
              value: c.stopPlyabackOnSwipeAway.value,
              onChanged: c.toggleStopPlyabackOnSwipeAway),
        ),
      ),
    // Android only.
    if (GetPlatform.isAndroid)
      Obx(
        () => _borderedTile(
          context: context,
          title: Text("ignoreBatOpt".tr),
          onTap: c.isIgnoringBatteryOptimizations.isFalse
              ? c.enableIgnoringBatteryOptimizations
              : null,
          subtitle: RichText(
            text: TextSpan(
              text:
                  "${"status".tr}: ${c.isIgnoringBatteryOptimizations.isTrue ? "enabled".tr : "disabled".tr}\n",
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium!
                  .copyWith(fontWeight: FontWeight.bold),
              children: <TextSpan>[
                TextSpan(
                    text: "ignoreBatOptDes".tr,
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    // Mobile only: cookies become the authenticated InnerTube session.
    if (!GetPlatform.isDesktop)
      Obx(() {
        final isUser = c.cookiesSource.value == "user";
        final active = c.cookiesActive.value;
        return _borderedTile(
          context: context,
          title: Text("cookiesTitle".tr),
          subtitle: Text(
            c.accountName.value.isNotEmpty
                ? c.accountName.value
                : (active
                    ? (isUser
                        ? "cookiesActiveUser".tr
                        : "cookiesActiveSystem".tr)
                    : "cookiesNone".tr),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          trailing: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: active
                  ? Colors.green.withAlpha(40)
                  : Colors.grey.withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              active
                  ? (isUser
                      ? "cookiesBadgeCustom".tr
                      : "cookiesBadgeSystem".tr)
                  : "cookiesBadgeInactive".tr,
              style: TextStyle(
                color: active ? Colors.green : Colors.grey,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          onTap: () => showDialog(
            context: context,
            builder: (_) => const _CookiesDialog(),
          ),
        );
      }),
    // Destructive reset — last option of the category.
    _borderedTile(
      context: context,
      title: Text("resetToDefault".tr),
      subtitle: Text("resetToDefaultDes".tr,
          style: Theme.of(context).textTheme.bodyMedium),
      onTap: () {
        c.resetAppSettingsToDefault().then((_) {
          ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
              Get.context!, "resetToDefaultMsg".tr,
              size: SanckBarSize.BIG,
              duration: const Duration(seconds: 2)));
        });
      },
    ),
  ];
}

List<Widget> _backupOptions(
    BuildContext context, SettingsScreenController c) {
  return [
    _borderedTile(
      context: context,
      title: Text("backupAppData".tr),
      subtitle: Text("backupSettingsAndPlaylistsDes".tr,
          style: Theme.of(context).textTheme.bodyMedium),
      isThreeLine: true,
      onTap: () => showDialog(
        context: context,
        builder: (context) => const BackupDialog(),
      ).whenComplete(() => Get.delete<BackupDialogController>()),
    ),
    _borderedTile(
      context: context,
      title: Text("restoreAppData".tr),
      subtitle: Text("restoreSettingsAndPlaylistsDes".tr,
          style: Theme.of(context).textTheme.bodyMedium),
      isThreeLine: true,
      onTap: () => showDialog(
        context: context,
        builder: (context) => const RestoreDialog(),
      ).whenComplete(() => Get.delete<RestoreDialogController>()),
    ),
  ];
}

List<Widget> _integrationsOptions(
    BuildContext context, SettingsScreenController c) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
  return [
    // Live Discord Rich Presence status card ("Listening to Velqi").
    Obx(() {
      final discord = Get.find<DiscordRpcService>();
      final linked = discord.isLinked.value;
      return Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            decoration: BoxDecoration(
              border:
                  Border.all(color: cs.outline.withAlpha(25), width: 1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.only(left: 12, right: 12, top: 6, bottom: 6),
              isThreeLine: true,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.onSurface.withAlpha(14),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: DiscordMark(
                  size: 22,
                  color: linked
                      ? const Color(0xFF5865F2)
                      : cs.onSurface.withAlpha(120),
                ),
              ),
              title: Text("discordRichPresence".tr),
              subtitle: Text("discordRichPresenceDes".tr,
                  style: tt.bodyMedium),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: linked
                      ? Colors.green.withAlpha(40)
                      : Colors.grey.withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  linked ? "discordLinked".tr : "discordNotLinked".tr,
                  style: TextStyle(
                    color: linked ? Colors.green : Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          if (!linked)
            Padding(
              padding: const EdgeInsets.only(left: 14, top: 4),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: cs.onSurface.withAlpha(120)),
                  const SizedBox(width: 6),
                  Text(
                    "discordOpenToConnect".tr,
                    style: tt.bodySmall
                        ?.copyWith(color: cs.onSurface.withAlpha(130)),
                  ),
                ],
              ),
            ),
        ],
      );
    }),
  ];
}

// ── Root Settings screen: category overview ─────────────────────────────────

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsScreenController>();
    final topPadding = context.isLandscape ? 50.0 : 90.0;
    return Padding(
      padding: isBottomNavActive
          ? const EdgeInsets.only(left: 20, top: 90, right: 15)
          : EdgeInsets.only(top: topPadding, left: 5, right: 5),
      child: Obx(() {
        final active = settingsController.activeCategory.value;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                      begin: const Offset(0.06, 0), end: Offset.zero)
                  .animate(animation),
              child: child,
            ),
          ),
          child: active == null
              ? _SettingsHome(
                  key: const ValueKey("settings-home"),
                  isBottomNavActive: isBottomNavActive,
                )
              : SettingsCategoryPage(
                  key: ValueKey(active), category: active),
        );
      }),
    );
  }
}

class _SettingsHome extends StatelessWidget {
  const _SettingsHome({super.key, required this.isBottomNavActive});

  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SettingsScreenController>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDesktop = GetPlatform.isDesktop;
    final specs = _categorySpecs(isDesktop);

    final tileW = isDesktop ? 148.0 : 122.0;
    final tileH = context.isLandscape ? 150.0 : (isDesktop ? 190.0 : 172.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "settings".tr,
            style: tt.titleLarge,
          ),
        ),
        const SizedBox(height: 8),

        // ── New version banner ──────────────────────────────────────
        Obx(
          () => c.isNewVersionAvailable.value
              ? GestureDetector(
                  onTap: () {
                    launchUrl(
                      Uri.parse('https://velqi.netlify.app/#download'),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF7C3AED),
                          Color(0xFF4F46E5),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF7C3AED).withOpacity(0.45),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: const Icon(
                            Icons.system_update_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "newVersionAvailable".tr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "goToDownloadPage".tr,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white70,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // ── Category cards (horizontal, Netflix style) ──────────────
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Text(
                    "categories".tr.toUpperCase(),
                    style: tt.labelMedium?.copyWith(
                      color: cs.onSurface.withOpacity(0.5),
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: tileH,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: specs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) => _CategoryCard(
                      spec: specs[i],
                      controller: c,
                      width: tileW,
                      height: tileH,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Footer: only the version (credits live on the Info tab) ─
        const SizedBox(height: 10),
        Center(
          child: Column(
            children: [
              Text(
                "Velqi",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                c.currentVersion,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withOpacity(0.3),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.spec,
    required this.controller,
    required this.width,
    required this.height,
  });

  final _CategorySpec spec;
  final SettingsScreenController controller;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final count = spec.options(context, controller).length;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => controller.activeCategory.value = spec.id,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isLight ? const Color(0xFFF4F4F7) : const Color(0xFF101013),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isLight
                ? const Color(0x14000000)
                : const Color(0x1FFFFFFF),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: cs.onSurface.withAlpha(isLight ? 14 : 22),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: spec.usesDiscordMark
                  ? DiscordMark(size: 22, color: cs.onSurface)
                  : Icon(spec.icon, size: 24, color: cs.onSurface),
            ),
            const SizedBox(height: 10),
            Text(
              spec.title(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tt.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              "$count ${"items".tr}",
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.45),
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Category sub-page ───────────────────────────────────────────────────────

class SettingsCategoryPage extends StatelessWidget {
  const SettingsCategoryPage({super.key, required this.category});

  final SettingsCategoryId category;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SettingsScreenController>();
    final specs = _categorySpecs(GetPlatform.isDesktop)
        .where((s) => s.id == category)
        .toList();
    if (specs.isEmpty) return const SizedBox.shrink();
    final spec = specs.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => c.activeCategory.value = null,
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              ),
            ),
            Expanded(
              child: Text(
                spec.title(),
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 200),
            children: spec.options(context, c),
          ),
        ),
      ],
    );
  }
}

// ── Theme Selector Dialog ────────────────────────────────────────────────────

class ThemeSelectorDialog extends StatelessWidget {
  const ThemeSelectorDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsScreenController>();
    return CommonDialog(
      child: Container(
        height: 220,
        padding:
            const EdgeInsets.only(top: 30, left: 5, right: 30, bottom: 10),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.only(left: 20.0, bottom: 5),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "themeMode".tr,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          // Velqi is dark-only: dynamic (album-tinted dark) and plain dark.
          radioWidget(
            label: "dynamic".tr,
            controller: settingsController,
            value: ThemeType.dynamic,
          ),
          radioWidget(
              label: "dark".tr,
              controller: settingsController,
              value: ThemeType.dark),
          Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text("cancel".tr),
                ),
                onTap: () => Navigator.of(context).pop(),
              ))
        ]),
      ),
    );
  }
}

// ── Shared radio widget (used by ThemeSelectorDialog) ──────────────────────

Widget radioWidget({
  required String label,
  required SettingsScreenController controller,
  required value,
}) {
  return Obx(() => ListTile(
        visualDensity: const VisualDensity(vertical: -4),
        onTap: () {
          controller.onThemeChange(value);
        },
        leading: Radio(
            value: value,
            groupValue: controller.themeModetype.value,
            onChanged: controller.onThemeChange),
        title: Text(label),
      ));
}

// ── Cookies Dialog ────────────────────────────────────────────────────────────

class _CookiesDialog extends StatefulWidget {
  const _CookiesDialog();
  @override
  State<_CookiesDialog> createState() => _CookiesDialogState();
}

class _CookiesDialogState extends State<_CookiesDialog> {
  late final TextEditingController _tc;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final saved =
        Hive.box("AppPrefs").get('userCookiesContent') as String? ?? '';
    _tc = TextEditingController(text: saved);
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sc = Get.find<SettingsScreenController>();
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text("cookiesTitle".tr),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Instructions
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withAlpha(120),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "cookiesHowTitle".tr,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "cookiesPcHeading".tr,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "cookiesPcSteps".tr,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "cookiesAndroidHeading".tr,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "cookiesAndroidSteps".tr,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tc,
                maxLines: 7,
                style: const TextStyle(fontSize: 11),
                decoration: InputDecoration(
                  hintText:
                      "# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/ ...",
                  hintStyle:
                      TextStyle(color: cs.onSurface.withAlpha(80), fontSize: 11),
                  border: const OutlineInputBorder(),
                  labelText: "cookiesFieldLabel".tr,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  await sc.clearCookies();
                  _tc.clear();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(snackbar(
                        context, "cookiesClearedMsg".tr,
                        size: SanckBarSize.BIG));
                    Navigator.of(context).pop();
                  }
                },
          child: Text("cookiesClear".tr),
        ),
        ElevatedButton(
          onPressed: _saving
              ? null
              : () async {
                  final content = _tc.text.trim();
                  if (content.isEmpty) return;
                  setState(() => _saving = true);
                  try {
                    final account = await sc.saveCookies(content);
                    if (context.mounted) {
                      final name = account?['name']?.toString();
                      ScaffoldMessenger.of(context).showSnackBar(snackbar(
                          context,
                          name == null || name.isEmpty
                              ? "cookiesAppliedMsg".tr
                              : "${"cookiesAppliedMsg".tr} · $name",
                          size: SanckBarSize.BIG));
                      Navigator.of(context).pop();
                    }
                  } catch (_) {
                    if (context.mounted) {
                      setState(() => _saving = false);
                      ScaffoldMessenger.of(context).showSnackBar(snackbar(
                          context,
                          "cookiesNotAccepted".tr,
                          size: SanckBarSize.BIG));
                    }
                  }
                },
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text("cookiesApply".tr),
        ),
      ],
    );
  }
}
