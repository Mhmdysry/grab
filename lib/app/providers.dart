import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/db/app_database.dart';
import '../data/engine/engine_channel.dart';
import '../data/repositories/download_repository.dart';
import '../data/settings/app_settings.dart';

/// App-wide singletons. Screens read these; nothing else creates them.

final engineProvider = Provider<Engine>((ref) => Engine.instance);

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Loaded in main() before the app starts, then overridden into the scope.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override in main'),
);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.load(ref.watch(sharedPrefsProvider));

  Future<void> update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await state.save(ref.read(sharedPrefsProvider));
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

final downloadRepositoryProvider = Provider<DownloadRepository>((ref) {
  final engine = ref.watch(engineProvider);
  final repo = DownloadRepository(
    ref.watch(databaseProvider),
    engine,
    maxParallel: ref.read(settingsProvider).maxParallel,
    online: Connectivity().onConnectivityChanged.map(
      (r) => r.any((c) => c != ConnectivityResult.none),
    ),
    activeIds: () async => (await engine.activeIds()).toSet(),
  );
  ref.listen(settingsProvider.select((s) => s.maxParallel), (_, n) {
    repo.maxParallel = n;
    repo.resume();
  });
  repo.fileTemplate = ref.read(settingsProvider).fileTemplate;
  ref.listen(
    settingsProvider.select((s) => s.fileTemplate),
    (_, t) => repo.fileTemplate = t,
  );
  // Keep the engine's save folder in step with Settings (it remembers it natively too).
  final s = ref.read(settingsProvider);
  ref.read(engineProvider).setOutputDir(s.saveBase, s.saveFolder).ignore();
  repo.resume();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Every job, newest first, kept live from the database.
final jobsProvider = StreamProvider<List<DownloadJob>>(
  (ref) => ref.watch(downloadRepositoryProvider).watchAll(),
);

/// Live speed per running download id, e.g. "2.3 MB/s".
final speedsProvider = StreamProvider<Map<String, String>>(
  (ref) => ref.watch(downloadRepositoryProvider).speeds,
);

/// Number of queued + running jobs, for the tab badge.
final activeCountProvider = Provider<int>((ref) {
  final jobs = ref.watch(jobsProvider).value ?? const [];
  return jobs
      .where(
        (j) =>
            j.status == JobStatus.queued ||
            j.status == JobStatus.running ||
            j.status == JobStatus.waiting,
      )
      .length;
});

/// Starts the engine (unpacks Python on first run) and returns the yt-dlp version.
/// The bundled yt-dlp ages quickly as sites change, so once a day (and on first
/// launch) it quietly fetches the latest stable yt-dlp first.
final engineVersionProvider = FutureProvider<String?>((ref) async {
  final engine = ref.watch(engineProvider);
  final prefs = ref.read(sharedPrefsProvider);
  String? clean(String? v) =>
      v?.replaceFirst(RegExp(r'^yt-dlp\s*', caseSensitive: false), '').trim();

  final v = await engine.init();
  const key = 'ytdlpCheckedAt';
  final last = DateTime.fromMillisecondsSinceEpoch(prefs.getInt(key) ?? 0);
  if (DateTime.now().difference(last) < const Duration(hours: 20)) {
    return clean(v);
  }
  try {
    final r = await engine.update();
    await prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
    if (r == 'updated') return clean(await engine.init());
  } catch (_) {
    // Offline or GitHub unreachable: keep the current engine, try next launch.
  }
  return clean(v);
});

/// A link to fetch on Home, set from anywhere ("Download again"). The shell consumes it.
class PendingLink extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? link) => state = link;
}

final pendingLinkProvider = NotifierProvider<PendingLink, String?>(
  PendingLink.new,
);

/// Extracts Android 12+ wallpaper Dynamic Color accent (system_accent1_500).
/// Returns null on older Android versions, iOS, desktop, or tests.
final dynamicColorProvider = FutureProvider<Color?>((ref) async {
  if (!Platform.isAndroid) return null;
  try {
    const channel = MethodChannel('grab/app');
    final argb = await channel.invokeMethod<int>('dynamicColor');
    return argb != null ? Color(argb & 0xFFFFFFFF) : null;
  } catch (_) {
    return null;
  }
});
