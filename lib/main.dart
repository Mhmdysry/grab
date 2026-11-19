import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/grab_app.dart';
import 'app/providers.dart';
import 'core/audio/audio_playback.dart';
import 'core/log/app_log.dart';
import 'core/utils/audio_art.dart';
import 'features/share/share_overlay_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLog.init(entrypoint: 'main');
  try {
    await AudioPlayback.init();
  } catch (e, st) {
    AppLog.error('audio', 'AudioPlayback.init failed', error: e, stackTrace: st);
  }
  final prefs = await SharedPreferences.getInstance();
  AudioArt.instance = AudioArt(prefs);
  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const GrabApp(),
    ),
  );
}

@pragma('vm:entry-point')
Future<void> shareMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLog.init(entrypoint: 'shareMain');
  final prefs = await SharedPreferences.getInstance();
  AudioArt.instance = AudioArt(prefs);
  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const ShareOverlayApp(),
    ),
  );
}
