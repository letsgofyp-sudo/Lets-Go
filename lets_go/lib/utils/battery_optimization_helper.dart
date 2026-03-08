import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Helper to guide users to exclude the app from Android battery optimizations
/// so background notifications (FCM) are more reliable.
class BatteryOptimizationHelper {
  /// Attempts to open the OS screen that prompts the user to exclude this app
  /// from battery optimizations. Requires the manifest permission
  /// REQUEST_IGNORE_BATTERY_OPTIMIZATIONS and user approval.
  static Future<void> requestIgnoreOptimizations(BuildContext context) async {
    if (!Platform.isAndroid) {
      _showSnack(context, 'Battery optimization setting is Android-only.');
      return;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final packageName = info.packageName;

      // Direct prompt for this package
      final intent = AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:$packageName',
      );
      await intent.launch();
    } catch (e) {
      // Fallback: open the general battery optimization settings
      try {
        final fallback = const AndroidIntent(
          action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
        );
        await fallback.launch();
        // ignore: use_build_context_synchronously
        _showSnack(context, 'Open battery optimization settings and allow this app.');
      } catch (e2) {
        // ignore: use_build_context_synchronously
        _showSnack(context, 'Unable to open battery optimization settings: $e2');
      }
    }
  }

  static void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }
}
