import 'dart:io';

import 'package:flutter/services.dart';

import '../repositories/download_repository.dart';
import 'desktop_engine.dart';
import 'media_info.dart';

/// A progress or status event for one download job.
class EngineEvent {
  const EngineEvent({
    required this.id,
    required this.status,
    this.progress,
    this.eta,
    this.line,
    this.paths = const [],
    this.error,
    this.speed,
  });

  final String id;

  /// starting | running | done | canceled | error
  final String status;
  final double? progress;
  final int? eta;
  final String? line;

  /// Files written by a finished job: the media file and any .srt subtitles.
  final List<String> paths;
  final String? error;

  /// Download speed as yt-dlp prints it, e.g. "2.30MiB/s".
  final String? speed;

  bool get isFinal =>
      status == 'done' || status == 'error' || status == 'canceled';

  factory EngineEvent.fromMap(Map<Object?, Object?> m) => EngineEvent(
    id: m['id'] as String,
    status: m['status'] as String,
    progress: (m['progress'] as num?)?.toDouble(),
    eta: (m['eta'] as num?)?.toInt(),
    line: m['line'] as String?,
    paths: ((m['paths'] as List?) ?? const []).cast<String>(),
    error: m['error'] as String?,
    speed: m['speed'] as String?,
  );
}

/// Everything the app asks of the download engine. Android runs it in Kotlin
/// ([EngineChannel]); Windows and macOS run yt-dlp and FFmpeg directly
/// ([DesktopEngine]).
abstract class Engine implements DownloadEngine {
  /// The engine for this platform.
  static final Engine instance = Platform.isAndroid
      ? EngineChannel()
      : DesktopEngine();

  /// Prepares the engine on first run. Returns the yt-dlp version.
  Future<String?> init();

  /// Updates yt-dlp. Returns "updated", "already_up_to_date" or null.
  Future<String?> update();
  Future<String?> outputDir();
  Future<String?> setOutputDir(String base, String folder);
  Future<MediaInfo> fetch(String url);
  Future<String?> previewFile(String url);
  Future<void> extractAudio({
    required String id,
    required String input,
    required String format,
    String? title,
  });

  /// Job ids currently running inside the native engine.
  Future<List<String>> activeIds() async => const [];
}

/// Dart side of the Kotlin EnginePlugin (yt-dlp via youtubedl-android).
class EngineChannel implements Engine {
  static const _methods = MethodChannel('grab/engine');
  static const _events = EventChannel('grab/engine/progress');

  @override
  late final Stream<EngineEvent> events = _events.receiveBroadcastStream().map(
    (e) => EngineEvent.fromMap(e as Map<Object?, Object?>),
  );

  /// Unpacks Python and yt-dlp on first run. Returns the yt-dlp version.
  @override
  Future<String?> init() => _methods.invokeMethod<String>('init');

  @override
  Future<String?> update() => _methods.invokeMethod<String>('update');

  @override
  Future<String?> outputDir() => _methods.invokeMethod<String>('outputDir');

  @override
  Future<MediaInfo> fetch(String url) async {
    final raw = await _methods.invokeMethod<String>('fetch', {'url': url});
    const marker = '\n\u0000GRAB-COOKIES\u0000\n';
    final at = raw!.indexOf(marker);
    if (at < 0) return MediaInfo.fromJsonString(url, raw);
    return MediaInfo.fromJsonString(
      url,
      raw.substring(0, at),
      cookieJar: raw.substring(at + marker.length),
    );
  }

  /// [suffix] is added to the file name so different modes don't overwrite each other.
  /// [match] is text every output file name contains (the item id), used to find subtitle files.
  @override
  Future<void> download({
    required String id,
    required String url,
    required List<String> args,
    String suffix = '',
    String? match,
    String title = 'Download',
    String template = '',
  }) => _methods.invokeMethod('download', {
    'id': id,
    'url': url,
    'args': args,
    'suffix': suffix,
    'match': match,
    'title': title,
    'template': template,
  });

  /// Downloads a small preview copy of [url] into the cache; returns its path.
  @override
  Future<String?> previewFile(String url) =>
      _methods.invokeMethod<String>('previewFile', {'url': url});

  /// Base folder ("download", "movies" or "music") and folder name for new files.
  @override
  Future<String?> setOutputDir(String base, String folder) => _methods
      .invokeMethod<String>('setOutputDir', {'base': base, 'folder': folder});

  /// Extracts the audio of a saved file with FFmpeg; progress arrives on [events] under [id].
  @override
  Future<void> extractAudio({
    required String id,
    required String input,
    required String format,
    String? title,
  }) => _methods.invokeMethod('extractAudio', {
    'id': id,
    'input': input,
    'format': format,
    'title': title,
  });

  @override
  Future<bool> cancel(String id) async =>
      await _methods.invokeMethod<bool>('cancel', {'id': id}) ?? false;

  @override
  Future<List<String>> activeIds() async {
    try {
      return await _methods.invokeListMethod<String>('activeIds') ?? const [];
    } catch (_) {
      return const [];
    }
  }
}
