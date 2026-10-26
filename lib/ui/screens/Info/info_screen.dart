import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '/ui/screens/Settings/settings_screen_controller.dart';
import '/services/permission_service.dart';

/// Credit row with a circular avatar (image asset or initial letter).
Widget _creditAvatarRow({
  required BuildContext context,
  String? asset,
  String? initial,
  required String name,
  required String role,
}) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primary, cs.primary.withOpacity(0.55)],
            ),
            border: Border.all(color: cs.outline.withOpacity(0.2), width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: asset != null
              ? Image.asset(
                  asset,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, __, ___) =>
                      _initialAvatar(context, initial ?? name[0]),
                )
              : _initialAvatar(context, initial ?? name[0]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                role,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.55),
                      fontSize: 12,
                    ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Fallback avatar: the person's initial on a gradient background.
Widget _initialAvatar(BuildContext context, String letter) {
  final cs = Theme.of(context).colorScheme;
  return Center(
    child: Text(
      letter.toUpperCase(),
      style: TextStyle(
        color: cs.onPrimary,
        fontSize: 19,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

/// Thin divider used between credit rows.
Widget _creditDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(height: 1, color: cs.outline.withOpacity(0.1));
}

/// Bordered card matching the app's design system.
Widget _borderedCard({
  required BuildContext context,
  required Widget child,
  EdgeInsetsGeometry padding =
      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
}) {
  final cs = Theme.of(context).colorScheme;
  final isLight = Theme.of(context).brightness == Brightness.light;
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
    padding: padding,
    decoration: BoxDecoration(
      border: Border.all(
          color: cs.outline.withAlpha(isLight ? 18 : 25), width: 1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}

/// Section header: small icon + title, like the settings tiles.
Widget _sectionTitle(BuildContext context, IconData icon, String title) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(left: 6, top: 14, bottom: 4),
    child: Row(
      children: [
        Icon(icon, size: 17, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    ),
  );
}

/// Small version pill used in the changelog (e.g. "v1.3.0").
Widget _versionPill(BuildContext context, String version) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: cs.primary.withOpacity(0.14),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: cs.primary.withOpacity(0.35), width: 0.8),
    ),
    child: Text(
      version,
      style: TextStyle(
        color: cs.primary,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    ),
  );
}

/// One changelog entry: version pill + bullet list of changes.
Widget _changelogEntry(BuildContext context, String version,
    List<String> changes) {
  final cs = Theme.of(context).colorScheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _versionPill(context, version),
      const SizedBox(height: 8),
      ...changes.map(
        (change) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary.withOpacity(0.7),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  change,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 13, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Live status of the Android media-control notification permission.
class _NotificationCard extends StatefulWidget {
  const _NotificationCard();

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard> {
  bool? _granted;
  bool _permanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final granted = await PermissionService.isNotificationGranted();
    final permanent =
        await PermissionService.isNotificationPermanentlyDenied();
    if (!mounted) return;
    setState(() {
      _granted = granted;
      _permanentlyDenied = permanent;
    });
    // Recreate the channel with HIGH importance (idempotent) — fixes the
    // Android 13 "channel created while blocked stays blocked" case, also
    // right after the user returns from system settings. No UI dependency,
    // so it runs after setState.
    if (granted) {
      await PermissionService.ensureNotificationChannelConfigured();
    }
  }

  Future<void> _request() async {
    await PermissionService.getNotificationPermission();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ok = _granted ?? false;
    return _borderedCard(
      context: context,
      child: _granted == null
          ? const SizedBox(
              height: 28,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      ok
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_off_rounded,
                      size: 19,
                      color: ok
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFFFA726),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ok
                            ? 'infoNotifEnabled'.tr
                            : 'infoNotifBlocked'.tr,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  ok
                      ? 'infoNotifOkBody'.tr
                      : _permanentlyDenied
                          ? 'infoNotifDeniedBody'.tr
                          : 'infoNotifAskBody'.tr,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.6),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                ),
                if (!ok) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _permanentlyDenied
                          ? PermissionService.openNotificationSettings
                          : _request,
                      child: Text(
                        _permanentlyDenied
                            ? 'infoNotifOpenSettings'.tr
                            : 'infoNotifAllow'.tr,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// "Info de Velqi" — first page of the navigation. Shows the app logo,
/// version, credits, recent changes, license and tech stack.
class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsScreenController>();
    final cs = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final topPadding = context.isLandscape ? 50.0 : 90.0;

    return Padding(
      padding: isBottomNavActive
          ? const EdgeInsets.only(left: 20, top: 90, right: 15)
          : EdgeInsets.only(top: topPadding, left: 8, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "infoTitle".tr,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 200),
              children: [
                // ── Hero: logo + name + version ────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Column(
                    children: [
                      Container(
                        width: 128,
                        height: 128,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              cs.primary,
                              cs.primary.withOpacity(0.55),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: cs.primary.withOpacity(0.35),
                              blurRadius: 26,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(14),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/velqi_guitar.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Velqi",
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "${'infoVersionLabel'.tr} ${settingsController.currentVersion}",
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "infoTagline".tr,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.6),
                            ),
                      ),
                    ],
                  ),
                ),

                // ── Créditos ───────────────────────────────────────────────
                _sectionTitle(
                    context, Icons.emoji_events_rounded, "infoCreditsTitle".tr),
                _borderedCard(
                  context: context,
                  child: Column(
                    children: [
                      _creditAvatarRow(
                        context: context,
                        asset: 'assets/avatars/lupyther.gif',
                        name: 'Lupyther',
                        role: 'infoRoleOwner'.tr,
                      ),
                      _creditDivider(context),
                      _creditAvatarRow(
                        context: context,
                        initial: 'A',
                        name: 'addhip',
                        role: 'infoRoleSupporter'.tr,
                      ),
                      _creditDivider(context),
                      _creditAvatarRow(
                        context: context,
                        asset: 'assets/avatars/runix.png',
                        name: 'Runix_The_Creator',
                        role: 'infoRoleDesigner'.tr,
                      ),
                    ],
                  ),
                ),

                // ── Novedades / últimos cambios ────────────────────────────
                _sectionTitle(
                    context, Icons.new_releases_rounded, "infoChangelogTitle".tr),
                _borderedCard(
                  context: context,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _changelogEntry(context, "v1.3.1", [
                        "changelog131_1".tr,
                        "changelog131_2".tr,
                        "changelog131_3".tr,
                        "changelog131_4".tr,
                        "changelog131_5".tr,
                        "changelog131_6".tr,
                        "changelog131_7".tr,
                        "changelog131_8".tr,
                      ]),
                      const SizedBox(height: 16),
                      _changelogEntry(context, "v1.3.0", [
                        "changelog130_1".tr,
                        "changelog130_2".tr,
                        "changelog130_3".tr,
                        "changelog130_4".tr,
                        "changelog130_5".tr,
                        "changelog130_6".tr,
                        "changelog130_7".tr,
                        "changelog130_8".tr,
                        "changelog130_9".tr,
                        "changelog130_10".tr,
                        "changelog130_11".tr,
                        "changelog130_12".tr,
                        "changelog130_13".tr,
                      ]),
                      const SizedBox(height: 16),
                      _changelogEntry(context, "v1.2.2", [
                        "changelog122_1".tr,
                        "changelog122_2".tr,
                        "changelog122_3".tr,
                      ]),
                      const SizedBox(height: 16),
                      _changelogEntry(context, "v1.2.1", [
                        "changelog121_1".tr,
                        "changelog121_2".tr,
                        "changelog121_3".tr,
                        "changelog121_4".tr,
                      ]),
                    ],
                  ),
                ),

                // ── Notificaciones ──────────────────────────────────────────
                _sectionTitle(context, Icons.notifications_rounded,
                    "infoNotificationsTitle".tr),
                const _NotificationCard(),

                // ── Licencia ───────────────────────────────────────────────
                _sectionTitle(context, Icons.gavel_rounded, "infoLicenseLabel".tr),
                _borderedCard(
                  context: context,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.description_outlined,
                              size: 18, color: cs.onSurface.withOpacity(0.6)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "infoLicenseBody".tr,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(height: 1.4, fontSize: 13.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Web oficial ───────────────────────────────────────────
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        launchUrl(
                          Uri.parse('https://velqi.netlify.app/'),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: cs.outline.withAlpha(isLight ? 70 : 100),
                          width: 1.2,
                        ),
                        foregroundColor: cs.onSurface,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 11),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.public_rounded, size: 18),
                      label: const Text(
                        'Web oficial · velqi.netlify.app',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    "infoReport".tr,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.5),
                          fontSize: 12,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
