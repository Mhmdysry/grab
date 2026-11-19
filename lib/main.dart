import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/grab_app.dart';
import 'app/providers.dart';
import 'core/audio/audio_playback.dart';
import 'core/utils/audio_art.dart';
import 'features/share/share_overlay_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AudioPlayback.init();
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
  final prefs = await SharedPreferences.getInstance();
  AudioArt.instance = AudioArt(prefs);
  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const ShareOverlayApp(),
    ),
  );
}
