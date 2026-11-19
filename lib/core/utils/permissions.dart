import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/pop_theme.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/pop_widgets.dart';
import 'haptics.dart';

/// Asks for what downloads need, with a short explanation first, the iOS way:
/// - Notifications (Android 13+): progress and "Saved" alerts. Optional; downloads work without it.
/// - Storage (Android 9 and older only): needed to save into Download/Grab.
///
/// Returns false only when saving is impossible (storage refused on old Android).
Future<bool> ensureDownloadPermissions(
  BuildContext context,
  SharedPreferences prefs,
) async {
  // Computers need no permission prompts to save into Downloads.
  if (!Platform.isAndroid) return true;
  final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;

  if (sdk <= 28) {
    final storage = await Permission.storage.status;
    if (!storage.isGranted) {
      if (!context.mounted) return false;
      final go = await _explain(
        context,
        icon: Icons.folder_rounded,
        title: 'Allow Grab to save files',
        body:
            'Grab saves your downloads to a folder on this phone (Download/Grab unless you pick another in Settings).',
        permanentlyDenied: storage.isPermanentlyDenied,
      );
      if (!go) return false;
      final r = storage.isPermanentlyDenied
          ? await _settings()
          : await Permission.storage.request();
      if (!r.isGranted) return false;
    }
  }

  if (sdk >= 33 && !(prefs.getBool('askedNotifications') ?? false)) {
    final n = await Permission.notification.status;
    if (!n.isGranted) {
      await prefs.setBool('askedNotifications', true);
      if (!context.mounted) return true;
      final go = await _explain(
        context,
        icon: Icons.notifications_active_rounded,
        title: 'Know when it\'s done',
        body:
            'Allow notifications to see download progress and a "Saved" alert, even when Grab is closed.',
        permanentlyDenied: n.isPermanentlyDenied,
      );
      if (go) {
        n.isPermanentlyDenied
            ? await _settings()
            : await Permission.notification.request();
      }
    }
  }
  return true;
}

/// Current notification permission, for Settings.
Future<PermissionStatus> notificationStatus() async => Platform.isAndroid
    ? Permission.notification.status
    : PermissionStatus.granted;

/// Ask again, or send the user to system settings if Android won't ask anymore.
Future<PermissionStatus> requestNotifications() async {
  if (!Platform.isAndroid) return PermissionStatus.granted;
  final s = await Permission.notification.status;
  if (s.isPermanentlyDenied) return _settings(Permission.notification);
  return Permission.notification.request();
}

Future<PermissionStatus> _settings([Permission p = Permission.storage]) async {
  await openAppSettings();
  return p.status;
}

Future<bool> _explain(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String body,
  required bool permanentlyDenied,
}) async {
  Haptics.soft();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExpressiveShapeContainer(
              polygon: ExpressivePolygon.cookie9,
              size: 72,
              color: context.cs.primaryContainer,
              child: Icon(
                icon,
                size: 36,
                color: context.cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              permanentlyDenied
                  ? '$body\n\nTurn it on in Settings › Permissions.'
                  : body,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.pop.muted, height: 1.3),
            ),
            const SizedBox(height: 20),
            PopButton(
              label: permanentlyDenied ? 'Open settings' : 'Continue',
              onPressed: () => Navigator.pop(context, true),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}
