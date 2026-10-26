import 'dart:io';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import '/native_bindings/andrid_utils.dart' show SDKInt;

class PermissionService {
  static Future<bool> getExtStoragePermission() async {
    if (GetPlatform.isDesktop) {
      return Future.value(true);
    }
    if ((SDKInt.Companion.getSDKInt()) < 30) {
      var status = await Permission.storage.status;
      if (status.isDenied) {
        await [
          Permission.storage,
          Permission.accessMediaLocation,
          Permission.mediaLibrary,
        ].request();
      }

      if (await Permission.storage.isPermanentlyDenied) {
        await openAppSettings();
      }

      return (await Permission.storage.status).isGranted;
    } else {
      // Android 11+ (SDK 30+): MANAGE_EXTERNAL_STORAGE
      // This permission CANNOT be requested via normal dialog on Android 11+.
      // The permission_handler .request() silently returns denied.
      // We must open the system settings page directly.
      if (await Permission.manageExternalStorage.isGranted) {
        return true;
      }

      // Try requesting via permission_handler first (may work on some devices)
      final status = await Permission.manageExternalStorage.request();
      if (status.isGranted) return true;

      // If denied/permanently denied, open the "All files access" settings page
      if (Platform.isAndroid) {
        const channel = MethodChannel('com.velqi.app/storage_settings');
        try {
          await channel.invokeMethod('openStorageSettings');
        } catch (_) {
          // Fallback: open generic app settings
          await openAppSettings();
        }
        // IMPORTANT: Don't check permission immediately after opening settings!
        // The user hasn't had a chance to grant it yet.
        // Return false and let the caller guide the user.
      }
      return false;
    }
  }

  /// Requests the POST_NOTIFICATIONS permission (required on Android 13+ so
  /// the media-control notification can be shown while playing).
  ///
  /// NOTE: the SDK check is deliberately NOT used here. On Android < 13
  /// permission_handler reports notifications as already granted (no dialog),
  /// so requesting unconditionally is safe and removes any dependency on the
  /// JNI SDKInt binding for this critical path.
  ///
  /// Unlike the storage flow, this NEVER opens app settings automatically:
  /// showing that dialog during app startup would be confusing. Callers decide
  /// when/how to guide the user (see [openNotificationSettings]).
  ///
  /// Once granted, the media-control notification channel is (re)created with
  /// HIGH importance so the notification is actually visible (audio_service's
  /// default IMPORTANCE_LOW channel has no status-bar icon and Android 13
  /// keeps channels blocked if they were created while the permission was
  /// denied).
  static Future<bool> getNotificationPermission() async {
    if (GetPlatform.isDesktop) {
      return Future.value(true);
    }
    var status = await Permission.notification.status;
    if (status.isDenied) {
      status = await Permission.notification.request();
    }
    if (status.isGranted) {
      await ensureNotificationChannelConfigured();
    }
    return status.isGranted;
  }

  /// Requests RECORD_AUDIO — used ONLY by the REAL audio visualizer
  /// (Android [Visualizer] peering into the output mix to drive the wave
  /// ring / beat). Pure visualization use, no audio is recorded or stored.
  /// Silently returns false if denied — the UI falls back to the
  /// music-clock animation, the app keeps working normally.
  static Future<bool> getMicrophonePermission() async {
    if (GetPlatform.isDesktop) return true;
    var status = await Permission.microphone.status;
    if (status.isDenied) {
      status = await Permission.microphone.request();
    }
    return status.isGranted;
  }

  /// Forces the media-control notification channel to exist with HIGH
  /// importance and un-blocked. MUST run after POST_NOTIFICATIONS is granted
  /// on Android 13+ (a channel created while denied stays blocked forever).
  /// No-op on desktop and on Android < 8 (channels don't exist there).
  static Future<void> ensureNotificationChannelConfigured() async {
    if (GetPlatform.isDesktop || !Platform.isAndroid) return;
    const channel = MethodChannel('com.velqi.app/notification_channel');
    try {
      await channel.invokeMethod('configureChannel');
    } catch (_) {
      // Old build or handler not registered yet — audio_service's default
      // (LOW) channel will still be used; next launch re-attempts.
    }
  }

  /// Reads the current notification permission WITHOUT showing a dialog
  /// (used by UI indicators, e.g. the Info screen status card).
  static Future<bool> isNotificationGranted() async {
    if (GetPlatform.isDesktop) {
      return true;
    }
    return (await Permission.notification.status).isGranted;
  }

  /// Whether the notification permission is permanently denied (Android 13+).
  /// Used to show a one-time prompt with a button that opens app settings.
  static Future<bool> isNotificationPermanentlyDenied() async {
    if (GetPlatform.isDesktop) {
      return false;
    }
    return (await Permission.notification.status).isPermanentlyDenied;
  }

  /// Opens the app settings page so the user can manually re-enable
  /// notifications (used when the permission was permanently denied).
  static Future<void> openNotificationSettings() async {
    await openAppSettings();
  }
}
