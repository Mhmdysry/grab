import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grab/data/db/app_database.dart';
import 'package:grab/data/engine/engine_channel.dart';
import 'package:grab/data/engine/media_info.dart';
import 'package:grab/data/repositories/download_repository.dart';

class FakeEngine implements DownloadEngine {
  final _events = StreamController<EngineEvent>.broadcast();
  final started = <String, List<String>>{};
  final matches = <String, String?>{};
  final canceled = <String>[];

  @override
  Stream<EngineEvent> get events => _events.stream;

  void emit(EngineEvent e) => _events.add(e);

  @override
  Future<void> download({
    required String id,
    required String url,
    required List<String> args,
    String suffix = '',
    String? match,
    String title = 'Download',
    String template = '',
  }) async {
    started[id] = args;
    matches[id] = match;
  }

  @override
  Future<bool> cancel(String id) async {
    canceled.add(id);
    return true;
  }
}

void main() {
  late AppDatabase db;
  late FakeEngine engine;
  late DownloadRepository repo;
  var tick = 0;

  const info = MediaInfo(url: 'https://example.com/v', title: 'Clip', id: 'v1');

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    engine = FakeEngine();
    tick = 0;
    repo = DownloadRepository(
      db,
      engine,
      maxParallel: 2,
      clock: () => DateTime(2026, 1, 1).add(Duration(seconds: tick++)),
    );
  });

  tearDown(() async {
    await repo.dispose();
    await db.close();
  });

  Future<List<DownloadJob>> jobs() => db.select(db.downloadJobs).get();
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test('runs at most two jobs and starts the next when one finishes', () async {
    final a = await repo.enqueue(
      const DownloadRequest(info: info, mode: DownloadMode.video),
    );
    final b = await repo.enqueue(
      const DownloadRequest(info: info, mode: DownloadMode.audioOnly),
    );
    final c = await repo.enqueue(
      const DownloadRequest(info: info, mode: DownloadMode.videoAndAudio),
    );
    expect(engine.started.keys, [a, b]);
    expect(
      (await jobs()).firstWhere((j) => j.id == c).status,
      JobStatus.queued,
    );

    engine.emit(
      EngineEvent(
        id: a,
        status: 'done',
        paths: const ['/x/Clip [v1].mp4', '/x/Clip [v1].en.srt'],
      ),
    );
    await settle();

    final all = await jobs();
    final done = all.firstWhere((j) => j.id == a);
    expect(done.status, JobStatus.done);
    expect(done.paths.split('\n'), hasLength(2));
    expect(engine.started.keys, contains(c));
  });

  test('passes subtitle choices and the item id to the engine', () async {
    final id = await repo.enqueue(
      const DownloadRequest(
        info: info,
        mode: DownloadMode.subtitlesOnly,
        subtitles: SubtitleChoice(langs: ['en', 'fr']),
      ),
    );
    expect(
      engine.started[id],
      containsAllInOrder([
        '--skip-download',
        '--write-subs',
        '--sub-langs',
        'en,fr',
      ]),
    );
    expect(engine.matches[id], '[v1]');
  });

  test('records errors and can retry', () async {
    final id = await repo.enqueue(
      const DownloadRequest(info: info, mode: DownloadMode.video),
    );
    engine.emit(EngineEvent(id: id, status: 'error', error: 'HTTP 403'));
    await settle();
    var job = (await jobs()).single;
    expect(job.status, JobStatus.failed);
    expect(job.error, 'HTTP 403');

    engine.started.clear();
    await repo.retry(id);
    job = (await jobs()).single;
    expect(job.status, JobStatus.running);
    expect(engine.started.keys, [id]);
  });

  test(
    'cancels queued jobs locally and running jobs through the engine',
    () async {
      final a = await repo.enqueue(
        const DownloadRequest(info: info, mode: DownloadMode.video),
      );
      await repo.enqueue(
        const DownloadRequest(info: info, mode: DownloadMode.video),
      );
      final c = await repo.enqueue(
        const DownloadRequest(info: info, mode: DownloadMode.video),
      );

      await repo.cancel(c);
      expect(
        (await jobs()).firstWhere((j) => j.id == c).status,
        JobStatus.canceled,
      );
      await repo.cancel(a);
      expect(engine.canceled, [a]);
    },
  );

  test('resume puts jobs that were running back in the queue', () async {
    repo.maxParallel = 0;
    final id = await repo.enqueue(
      const DownloadRequest(info: info, mode: DownloadMode.video),
    );
    await (db.update(
      db.downloadJobs,
    )).write(const DownloadJobsCompanion(status: Value(JobStatus.running)));
    repo.maxParallel = 2;
    await repo.resume();
    expect(engine.started.keys, [id]);
  });

  test('throttles progress writes to whole percents', () async {
    final id = await repo.enqueue(
      const DownloadRequest(info: info, mode: DownloadMode.video),
    );
    engine.emit(EngineEvent(id: id, status: 'running', progress: 10.2));
    engine.emit(EngineEvent(id: id, status: 'running', progress: 10.6));
    await settle();
    expect((await jobs()).single.progress, 10.2);
  });

  test('kick starts a silent placeholder job once updated to queued and sync updates speed', () async {
    const jobId = 'silent-1';
    await db.into(db.downloadJobs).insert(
      DownloadJobsCompanion.insert(
        id: jobId,
        url: info.url,
        title: 'Fetching TikTok link…',
        mode: DownloadMode.video.name,
        status: JobStatus.running,
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await (db.update(db.downloadJobs)..where((t) => t.id.equals(jobId))).write(
      const DownloadJobsCompanion(
        title: Value('Clip'),
        itemId: Value('v1'),
        status: Value(JobStatus.queued),
      ),
    );
    repo.markOnline();
    await repo.kick();
    expect(engine.started.keys, contains(jobId));
    expect((await jobs()).single.status, JobStatus.running);

    final speedsFuture = repo.speeds.first;
    engine.emit(EngineEvent(id: jobId, status: 'sync', speed: '3.50MiB/s'));
    final speeds = await speedsFuture;
    expect(speeds[jobId], '3.5 MB/s');
  });
}
