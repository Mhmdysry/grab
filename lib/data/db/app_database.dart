import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Job states, stored by name.
/// [paused]: stopped by the user, resumes where it left off.
/// [waiting]: lost the connection; starts again by itself once the phone is online.
enum JobStatus { queued, running, done, failed, canceled, paused, waiting }

/// One download: what was asked for, and how it went.
@DataClassName('DownloadJob')
class DownloadJobs extends Table {
  TextColumn get id => text()();
  TextColumn get url => text()();
  TextColumn get title => text()();
  TextColumn get itemId => text().nullable()();
  TextColumn get thumbnail => text().nullable()();
  TextColumn get site => text().nullable()();

  /// DownloadMode name.
  TextColumn get mode => text()();
  IntColumn get maxHeight => integer().nullable()();
  TextColumn get container => text().withDefault(const Constant('mp4'))();
  TextColumn get audioFormat => text().withDefault(const Constant('mp3'))();

  /// Comma-separated yt-dlp language codes; empty = no subtitles.
  TextColumn get subLangs => text().withDefault(const Constant(''))();
  BoolColumn get subAuto => boolean().withDefault(const Constant(false))();
  BoolColumn get subEmbed => boolean().withDefault(const Constant(false))();

  IntColumn get estimatedBytes => integer().nullable()();

  /// Only save this part of the media, in seconds.
  RealColumn get trimStart => real().nullable()();
  RealColumn get trimEnd => real().nullable()();

  /// Automatic retries after connection problems.
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get status => textEnum<JobStatus>()();
  RealColumn get progress => real().withDefault(const Constant(0))();
  IntColumn get eta => integer().nullable()();

  /// Newline-separated output files.
  TextColumn get paths => text().withDefault(const Constant(''))();
  TextColumn get error => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [DownloadJobs])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'grab'));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA busy_timeout = 5000');
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Modes were redefined: "videoAndAudio" used to mean the video with its sound,
        // and the "videoOnly" (muted) mode was removed. Both are now plain `video`.
        await customStatement(
          "UPDATE download_jobs SET mode = 'video' WHERE mode IN ('videoAndAudio', 'videoOnly')",
        );
      }
      if (from < 3) {
        await m.addColumn(downloadJobs, downloadJobs.trimStart);
        await m.addColumn(downloadJobs, downloadJobs.trimEnd);
        await m.addColumn(downloadJobs, downloadJobs.attempts);
      }
    },
  );
}
