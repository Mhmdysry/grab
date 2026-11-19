import 'dart:async';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../engine/engine_channel.dart';
import '../engine/media_info.dart';

/// What the queue needs from the engine. [EngineChannel] implements it; tests use a fake.
abstract interface class DownloadEngine {
  Stream<EngineEvent> get events;
  Future<void> download({
    required String id,
    required String url,
    required List<String> args,
    String suffix,
    String? match,
    String title,
    String template,
  });
  Future<bool> cancel(String id);
}

/// A download the user asked for, before it is queued.
class DownloadRequest {
  const DownloadRequest({
    required this.info,
    required this.mode,
    this.maxHeight,
    this.estimatedBytes,
    this.subtitles = SubtitleChoice.none,
    this.container = 'mp4',
    this.audioFormat = 'mp3',
    this.trimStart,
    this.trimEnd,
  });

  final MediaInfo info;
  final DownloadMode mode;
  final int? maxHeight;
  final int? estimatedBytes;
  final SubtitleChoice subtitles;
  final String container;
  final String audioFormat;

  /// Save only this part, in seconds. Null = from the start / to the end.
  final double? trimStart;
  final double? trimEnd;
}

/// Owns the download queue: saves jobs first, runs up to [maxParallel] at a time,
/// and records progress and results from engine events.
class DownloadRepository {
  DownloadRepository(
    this._db,
    this._engine, {
    this.maxParallel = 2,
    DateTime Function()? clock,
    Stream<bool>? online,
    this.retryDelay = const Duration(seconds: 20),
    Future<Set<String>> Function()? activeIds,
  }) : _now = clock ?? DateTime.now,
       _activeIds = activeIds {
    _sub = _engine.events.listen(_onEvent);
    _onlineSub = online?.listen(_onConnectivity);
  }

  /// How many times a download is retried by itself after connection problems.
  static const maxAutoRetries = 5;

  /// Wait before retrying when the phone looks online but the download dropped.
  final Duration retryDelay;

  final AppDatabase _db;
  final DownloadEngine _engine;
  final DateTime Function() _now;
  final Future<Set<String>> Function()? _activeIds;
  int maxParallel;

  /// The user's file-name template, e.g. "{title} - {site}" (see [ytDlpTemplate]).
  String fileTemplate = defaultFileTemplate;
  late final StreamSubscription<EngineEvent> _sub;
  StreamSubscription<bool>? _onlineSub;
  var _online = true;
  Timer? _retryTimer;

  /// Live download speed per running job ("2.3 MB/s"); not stored.
  final _speeds = <String, String>{};
  final _speedsOut = StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get speeds => _speedsOut.stream;

  void _setSpeed(String id, String? raw) {
    final label = raw == null ? null : speedLabel(raw);
    if (label == null) {
      if (_speeds.remove(id) == null) return;
    } else {
      if (_speeds[id] == label) return;
      _speeds[id] = label;
    }
    _speedsOut.add(Map.unmodifiable(_speeds));
  }

  /// "2.30MiB/s" -> "2.3 MB/s", "512.00KiB/s" -> "512 KB/s".
  static String? speedLabel(String raw) {
    final m = RegExp(r'([\d.]+)\s*([KMG]?)i?B/s').firstMatch(raw);
    if (m == null) return null;
    final v = double.tryParse(m[1]!) ?? 0;
    final unit = '${m[2]}B/s';
    return '${v >= 100 || m[2]!.isEmpty ? v.round() : v.toStringAsFixed(1)} $unit';
  }

  /// Running jobs the user asked to pause; their "canceled" event means paused.
  final _pausing = <String>{};
  final _lastWrite = <String, double>{};
  var _idCounter = 0;

  /// All jobs, newest first.
  Stream<List<DownloadJob>> watchAll() => (_db.select(
    _db.downloadJobs,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();

  /// Call once at app start: jobs that were running when the app died go back in the queue.
  Future<void> resume() async {
    final live = _activeIds != null ? await _activeIds() : const <String>{};
    final running = await (_db.select(
      _db.downloadJobs,
    )..where((t) => t.status.equalsValue(JobStatus.running))).get();
    for (final j in running) {
      if (!live.contains(j.id)) {
        await _set(
          j.id,
          const DownloadJobsCompanion(
            status: Value(JobStatus.queued),
            progress: Value(0),
          ),
        );
      }
    }
    await _pump();
  }

  Future<String> enqueue(DownloadRequest r) async {
    final id = '${_now().microsecondsSinceEpoch}-${_idCounter++}';
    await _db
        .into(_db.downloadJobs)
        .insert(
          DownloadJobsCompanion.insert(
            id: id,
            url: r.info.url,
            title: r.info.title,
            itemId: Value(r.info.id),
            thumbnail: Value(r.info.thumbnail),
            site: Value(r.info.site),
            mode: r.mode.name,
            maxHeight: Value(r.maxHeight),
            container: Value(r.container),
            audioFormat: Value(r.audioFormat),
            subLangs: Value(r.subtitles.langs.join(',')),
            subAuto: Value(r.subtitles.includeAuto),
            subEmbed: Value(r.subtitles.embed),
            estimatedBytes: Value(r.estimatedBytes),
            trimStart: Value(r.trimStart),
            trimEnd: Value(r.trimEnd),
            status: JobStatus.queued,
            createdAt: _now(),
          ),
        );
    await _pump();
    return id;
  }

  Future<void> cancel(String id) async {
    final job = await _get(id);
    if (job == null) return;
    if (job.status == JobStatus.queued ||
        job.status == JobStatus.paused ||
        job.status == JobStatus.waiting) {
      _setSpeed(id, null);
      await _set(
        id,
        DownloadJobsCompanion(
          status: const Value(JobStatus.canceled),
          progress: const Value(0),
          finishedAt: Value(_now()),
        ),
      );
    } else if (job.status == JobStatus.running) {
      await _engine.cancel(id);
    }
  }

  Future<void> retry(String id) async {
    await _set(
      id,
      const DownloadJobsCompanion(
        status: Value(JobStatus.queued),
        progress: Value(0),
        error: Value(null),
        attempts: Value(0),
      ),
    );
    await _pump();
  }

  /// Stops a download but keeps what was saved so far; [unpause] continues it.
  Future<void> pause(String id) async {
    final job = await _get(id);
    if (job == null) return;
    switch (job.status) {
      case JobStatus.queued || JobStatus.waiting:
        await _set(
          id,
          const DownloadJobsCompanion(status: Value(JobStatus.paused)),
        );
      case JobStatus.running:
        _pausing.add(id);
        await _set(
          id,
          const DownloadJobsCompanion(status: Value(JobStatus.paused)),
        );
        if (!await _engine.cancel(id)) {
          // Not started on the engine side yet: just keep it paused.
          _pausing.remove(id);
          await _pump();
        }
      default:
    }
  }

  /// Continues a paused download from where it stopped (yt-dlp keeps the .part file).
  Future<void> unpause(String id) async {
    final job = await _get(id);
    if (job?.status != JobStatus.paused) return;
    await _set(
      id,
      const DownloadJobsCompanion(
        status: Value(JobStatus.queued),
        error: Value(null),
      ),
    );
    await _pump();
  }

  /// yt-dlp messages that mean the connection, not the link, is the problem.
  static final _networkError = RegExp(
    r'Unable to download|timed out|time out|Connection (reset|refused|aborted)|'
    r'Network is unreachable|No route to host|Temporary failure in name resolution|'
    r'getaddrinfo|Name or service not known|No address associated|'
    r'Remote end closed|IncompleteRead|Software caused connection abort|'
    r'HTTP Error 5\d\d|SSL|EOF occurred',
    caseSensitive: false,
  );

  static bool isNetworkError(String? message) =>
      message != null && _networkError.hasMatch(message);

  void _onConnectivity(bool online) {
    final was = _online;
    _online = online;
    if (online && !was) _requeueWaiting();
  }

  Future<void> _requeueWaiting() async {
    _retryTimer?.cancel();
    if (!_online) return;
    await (_db.update(_db.downloadJobs)
          ..where((t) => t.status.equalsValue(JobStatus.waiting)))
        .write(const DownloadJobsCompanion(status: Value(JobStatus.queued)));
    await _pump();
  }

  /// Removes failed and canceled jobs from history. Returns how many.
  Future<int> clearFailed() =>
      (_db.delete(_db.downloadJobs)..where(
            (t) =>
                t.status.equalsValue(JobStatus.failed) |
                t.status.equalsValue(JobStatus.canceled),
          ))
          .go();

  /// Removes the job from history. Files on disk are kept.
  Future<void> remove(String id) async {
    await cancel(id);
    await (_db.delete(_db.downloadJobs)..where((t) => t.id.equals(id))).go();
  }

  Future<void> dispose() async {
    _retryTimer?.cancel();
    await _speedsOut.close();
    await _onlineSub?.cancel();
    await _sub.cancel();
  }

  // ---- queue ----

  var _pumping = false;

  Future<void> _pump() async {
    if (_pumping || !_online) return;
    _pumping = true;
    try {
      while (true) {
        final running = await (_db.select(
          _db.downloadJobs,
        )..where((t) => t.status.equalsValue(JobStatus.running))).get();
        if (running.length >= maxParallel) return;
        final next =
            await (_db.select(_db.downloadJobs)
                  ..where((t) => t.status.equalsValue(JobStatus.queued))
                  ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
                  ..limit(1))
                .getSingleOrNull();
        if (next == null) return;
        await _set(
          next.id,
          const DownloadJobsCompanion(status: Value(JobStatus.running)),
        );
        await _start(next);
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _start(DownloadJob job) async {
    final mode = DownloadMode.values.byName(job.mode);
    final subs = SubtitleChoice(
      langs: job.subLangs.isEmpty ? const [] : job.subLangs.split(','),
      includeAuto: job.subAuto,
      embed: job.subEmbed,
    );
    try {
      await _engine.download(
        id: job.id,
        url: job.url,
        args: buildDownloadArgs(
          mode: mode,
          maxHeight: job.maxHeight,
          container: job.container,
          audioFormat: job.audioFormat,
          subtitles: subs,
          trimStart: job.trimStart,
          trimEnd: job.trimEnd,
        ),
        suffix: trimSuffix(job.trimStart, job.trimEnd),
        match: job.itemId == null ? null : '[${job.itemId}]',
        title: job.title,
        template: ytDlpTemplate(fileTemplate),
      );
    } catch (e) {
      await _finish(job.id, JobStatus.failed, error: '$e');
    }
  }

  /// Ids of non-download engine work (audio extraction); the queue ignores them.
  static bool isSideTask(String id) => id.startsWith('x-');

  /// Adds files made later (e.g. extracted audio) to a finished download.
  Future<void> addPaths(String id, List<String> more) async {
    final job = await _get(id);
    if (job == null || more.isEmpty) return;
    final all = {...job.paths.split('\n').where((p) => p.isNotEmpty), ...more};
    await _set(id, DownloadJobsCompanion(paths: Value(all.join('\n'))));
  }

  Future<void> _onEvent(EngineEvent e) async {
    if (isSideTask(e.id)) return;
    switch (e.status) {
      case 'running':
        _setSpeed(e.id, e.speed);
        final p = e.progress ?? 0;
        // Write at most once per whole percent to keep the database quiet.
        if ((p - (_lastWrite[e.id] ?? -1)).abs() < 1) return;
        _lastWrite[e.id] = p;
        await _set(
          e.id,
          DownloadJobsCompanion(progress: Value(p), eta: Value(e.eta)),
        );
      case 'done':
        await _finish(e.id, JobStatus.done, paths: e.paths);
      case 'error':
        final job = await _get(e.id);
        if (job != null &&
            isNetworkError(e.error) &&
            job.attempts < maxAutoRetries) {
          await _wait(job, e.error);
        } else {
          await _finish(e.id, JobStatus.failed, error: e.error);
        }
      case 'canceled':
        _setSpeed(e.id, null);
        final current = await _get(e.id);
        if (_pausing.remove(e.id) || current?.status == JobStatus.paused) {
          _lastWrite.remove(e.id);
          await _set(
            e.id,
            const DownloadJobsCompanion(status: Value(JobStatus.paused)),
          );
          await _pump();
        } else {
          await _finish(e.id, JobStatus.canceled);
        }
    }
  }

  /// Connection dropped: park the job, keep its progress, and try again once
  /// online (or after [retryDelay] if the phone never noticed it was offline).
  Future<void> _wait(DownloadJob job, String? error) async {
    _lastWrite.remove(job.id);
    _setSpeed(job.id, null);
    await _set(
      job.id,
      DownloadJobsCompanion(
        status: const Value(JobStatus.waiting),
        attempts: Value(job.attempts + 1),
        error: Value(error),
      ),
    );
    _retryTimer?.cancel();
    _retryTimer = Timer(retryDelay * (job.attempts + 1), _requeueWaiting);
    await _pump();
  }

  Future<void> _finish(
    String id,
    JobStatus status, {
    List<String> paths = const [],
    String? error,
  }) async {
    _lastWrite.remove(id);
    _setSpeed(id, null);
    await _set(
      id,
      DownloadJobsCompanion(
        status: Value(status),
        progress: Value(status == JobStatus.done ? 100 : 0),
        paths: Value(paths.join('\n')),
        error: Value(error),
        finishedAt: Value(_now()),
      ),
    );
    await _pump();
  }

  Future<DownloadJob?> _get(String id) => (_db.select(
    _db.downloadJobs,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> _set(String id, DownloadJobsCompanion c) =>
      (_db.update(_db.downloadJobs)..where((t) => t.id.equals(id))).write(c);
}
