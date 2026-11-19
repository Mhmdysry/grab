import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/db/app_database.dart';

enum LibraryKind { video, audio, subtitles }

/// One saved file, shown as a tile in the Library.
class LibraryItem {
  const LibraryItem({
    required this.jobId,
    required this.path,
    required this.title,
    required this.kind,
    this.thumbnail,
    this.site,
    this.finishedAt,
  });

  final String jobId;
  final String path;
  final String title;
  final LibraryKind kind;
  final String? thumbnail;
  final String? site;
  final DateTime? finishedAt;

  String get fileName => p.basename(path);
  String get ext => p.extension(path).replaceFirst('.', '').toUpperCase();
}

const _videoExt = {'.mp4', '.mkv', '.webm', '.mov', '.m4v', '.avi'};
const _audioExt = {'.mp3', '.m4a', '.opus', '.flac', '.ogg', '.wav', '.aac'};
const _subExt = {'.srt', '.vtt', '.ass'};

bool isLibraryMediaPath(String path) {
  final e = p.extension(path).toLowerCase();
  return _videoExt.contains(e) || _audioExt.contains(e) || _subExt.contains(e);
}

LibraryKind kindOf(String path) {
  final e = p.extension(path).toLowerCase();
  if (_audioExt.contains(e)) return LibraryKind.audio;
  if (_subExt.contains(e)) return LibraryKind.subtitles;
  return LibraryKind.video;
}

/// Files from finished jobs that still exist, newest first, one tile per file.
/// The same file saved by several jobs appears once.
List<LibraryItem> buildLibrary(
  Iterable<DownloadJob> jobs, {
  required bool Function(String path) exists,
}) {
  final done = jobs.where((j) => j.status == JobStatus.done).toList()
    ..sort(
      (a, b) =>
          (b.finishedAt ?? b.createdAt).compareTo(a.finishedAt ?? a.createdAt),
    );
  final seen = <String>{};
  final out = <LibraryItem>[];
  for (final j in done) {
    for (final path in j.paths.split('\n')) {
      if (path.isEmpty || !seen.add(path) || !exists(path)) continue;
      out.add(
        LibraryItem(
          jobId: j.id,
          path: path,
          title: j.title,
          kind: kindOf(path),
          thumbnail: j.thumbnail,
          site: j.site,
          finishedAt: j.finishedAt,
        ),
      );
    }
  }
  return out;
}

/// Merges [dbItems] with any media files present on disk in [dirPath] that are
/// not already tracked in [dbItems] (for example, files whose history rows were
/// cleared earlier). Results are returned newest first.
List<LibraryItem> mergeDiskFiles(
  List<LibraryItem> dbItems,
  String? dirPath,
) {
  if (dirPath == null || dirPath.trim().isEmpty) return dbItems;
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return dbItems;

  final seen = <String>{for (final item in dbItems) item.path};
  final out = <LibraryItem>[...dbItems];

  try {
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path;
      final name = p.basename(path);
      if (name.startsWith('.') ||
          name.endsWith('.part') ||
          name.endsWith('.ytdl')) {
        continue;
      }
      if (!isLibraryMediaPath(path) || !seen.add(path)) continue;

      final base = p.basenameWithoutExtension(path);
      String title = base;
      String? site;
      final dashIdx = base.lastIndexOf(' - ');
      if (dashIdx > 0 && dashIdx + 3 < base.length) {
        title = base.substring(0, dashIdx).trim();
        site = base.substring(dashIdx + 3).trim().toLowerCase();
      }
      DateTime? mtime;
      try {
        mtime = entity.lastModifiedSync();
      } catch (_) {}

      out.add(
        LibraryItem(
          jobId: 'disk:$path',
          path: path,
          title: title,
          kind: kindOf(path),
          site: site,
          finishedAt: mtime,
        ),
      );
    }
  } catch (_) {
    return dbItems;
  }

  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  out.sort(
    (a, b) => (b.finishedAt ?? epoch).compareTo(a.finishedAt ?? epoch),
  );
  return out;
}

/// Library filter: null kind = everything except loose subtitle files.
List<LibraryItem> filterLibrary(
  List<LibraryItem> items, {
  LibraryKind? kind,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  return items.where((i) {
    if (kind == null
        ? i.kind == LibraryKind.subtitles &&
              items.any(
                (o) => o.jobId == i.jobId && o.kind != LibraryKind.subtitles,
              )
        : i.kind != kind) {
      return false;
    }
    return q.isEmpty ||
        i.title.toLowerCase().contains(q) ||
        i.fileName.toLowerCase().contains(q);
  }).toList();
}

/// "614 KB", "48 MB", "1.2 GB", or null if the file is gone.
String? fileSizeLabel(String path) {
  try {
    final b = File(path).lengthSync();
    if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(1)} GB';
    if (b >= 1 << 20) return '${(b / (1 << 20)).round()} MB';
    return '${(b / 1024).ceil()} KB';
  } catch (_) {
    return null;
  }
}

/// How the Library is ordered.
enum LibrarySort {
  newest('Newest'),
  oldest('Oldest'),
  largest('Largest'),
  site('Site A–Z');

  const LibrarySort(this.label);
  final String label;
}

/// Orders [items]. [sizeOf] gives a file's size in bytes (0 when unknown).
List<LibraryItem> sortLibrary(
  List<LibraryItem> items,
  LibrarySort sort, {
  required int Function(String path) sizeOf,
}) {
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  int byDate(LibraryItem a, LibraryItem b) =>
      (b.finishedAt ?? epoch).compareTo(a.finishedAt ?? epoch);
  final out = [...items];
  switch (sort) {
    case LibrarySort.newest:
      out.sort(byDate);
    case LibrarySort.oldest:
      out.sort((a, b) => byDate(b, a));
    case LibrarySort.largest:
      final sizes = {for (final i in items) i.path: sizeOf(i.path)};
      out.sort((a, b) => sizes[b.path]!.compareTo(sizes[a.path]!));
    case LibrarySort.site:
      out.sort((a, b) {
        final c = siteName(
          a.site,
        ).toLowerCase().compareTo(siteName(b.site).toLowerCase());
        return c != 0 ? c : byDate(a, b);
      });
  }
  return out;
}

/// Friendly platform name from yt-dlp's extractor key ("TikTok", "YouTube", ...).
String siteName(String? site) {
  if (site == null || site.isEmpty) return 'Other';
  final s = site.toLowerCase();
  for (final (key, name) in const [
    ('youtube', 'YouTube'),
    ('tiktok', 'TikTok'),
    ('instagram', 'Instagram'),
    ('pinterest', 'Pinterest'),
    ('twitter', 'X'),
    ('facebook', 'Facebook'),
    ('reddit', 'Reddit'),
    ('vimeo', 'Vimeo'),
    ('soundcloud', 'SoundCloud'),
    ('twitch', 'Twitch'),
  ]) {
    if (s.contains(key)) return name;
  }
  // "GenericIE" style keys: drop a trailing "IE" or "Tab" and keep the rest.
  return site.replaceFirst(RegExp(r'(IE|Tab|User|Playlist)$'), '');
}

/// Splits sorted [items] by platform, keeping each group's order; biggest group first.
List<(String, List<LibraryItem>)> groupBySite(List<LibraryItem> items) {
  final groups = <String, List<LibraryItem>>{};
  for (final i in items) {
    (groups[siteName(i.site)] ??= []).add(i);
  }
  final out = [for (final e in groups.entries) (e.key, e.value)];
  out.sort((a, b) {
    final c = b.$2.length.compareTo(a.$2.length);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return out;
}
