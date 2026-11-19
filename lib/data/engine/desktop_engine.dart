import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine_channel.dart';
import 'media_info.dart';

/// The download engine on Windows and macOS: runs the yt-dlp and FFmpeg
/// programs directly. On first launch it fetches the official yt-dlp release
/// and an FFmpeg build into the app's own folder (an FFmpeg already installed
/// on the computer is used instead when there is one).
class DesktopEngine implements Engine {
  final _events = StreamController<EngineEvent>.broadcast();
  final _running = <String, Process>{};
  Future<void>? _ready;
  late Directory _bin;
  String? _ffmpegDir;

  @override
  Stream<EngineEvent> get events => _events.stream;

  @override
  Future<List<String>> activeIds() async => _running.keys.toList();

  static bool get _win => Platform.isWindows;
  static bool get _linux => Platform.isLinux;
  String get _ytdlp => p.join(_bin.path, _win ? 'yt-dlp.exe' : 'yt-dlp');

  // ---- setup ----

  Future<void> _ensureReady() => _ready ??= _setup();

  Future<void> _setup() async {
    _bin = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'bin'),
    );
    await _bin.create(recursive: true);
    if (!File(_ytdlp).existsSync()) {
      final String asset;
      if (_win) {
        asset = 'yt-dlp.exe';
      } else if (_linux) {
        final arch = (await Process.run('uname', [
          '-m',
        ])).stdout.toString().trim();
        asset = (arch == 'aarch64' || arch == 'arm64')
            ? 'yt-dlp_linux_aarch64'
            : 'yt-dlp_linux';
      } else {
        asset = 'yt-dlp_macos';
      }
      await _download(
        'https://github.com/yt-dlp/yt-dlp/releases/latest/download/$asset',
        File(_ytdlp),
      );
      if (!_win) await Process.run('chmod', ['+x', _ytdlp]);
    }
    _ffmpegDir = await _findFfmpeg();
  }

  /// FFmpeg already on the computer, or one we fetched before, or fetch one now.
  Future<String?> _findFfmpeg() async {
    final exe = _win ? 'ffmpeg.exe' : 'ffmpeg';
    final ours = Directory(p.join(_bin.path, 'ffmpeg'));
    if (File(p.join(ours.path, exe)).existsSync()) return ours.path;
    for (final dir in [
      ...(Platform.environment['PATH'] ?? '').split(_win ? ';' : ':'),
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/usr/bin',
    ]) {
      if (dir.isNotEmpty &&
          File(p.join(dir, exe)).existsSync() &&
          File(p.join(dir, _win ? 'ffprobe.exe' : 'ffprobe')).existsSync()) {
        return dir;
      }
    }
    await ours.create(recursive: true);
    if (_win) {
      final zip = File(p.join(_bin.path, 'ffmpeg.zip'));
      await _download(
        'https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip',
        zip,
      );
      await _unzipBinaries(zip, ours, {'ffmpeg.exe', 'ffprobe.exe'});
    } else if (_linux) {
      final arch = (await Process.run('uname', [
        '-m',
      ])).stdout.toString().trim();
      final target = (arch == 'aarch64' || arch == 'arm64')
          ? 'linuxarm64'
          : 'linux64';
      final archive = File(p.join(_bin.path, 'ffmpeg.tar.xz'));
      await _download(
        'https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-$target-gpl.tar.xz',
        archive,
      );
      await Process.run('tar', [
        '-xJf',
        archive.path,
        '--wildcards',
        '--strip-components=2',
        '-C',
        ours.path,
        '*/bin/ffmpeg',
        '*/bin/ffprobe',
      ]);
      if (archive.existsSync()) await archive.delete();
      for (final tool in ['ffmpeg', 'ffprobe']) {
        final f = File(p.join(ours.path, tool));
        if (f.existsSync()) await Process.run('chmod', ['+x', f.path]);
      }
    } else {
      // Static macOS builds for this Mac's chip.
      final arch = (await Process.run('uname', [
        '-m',
      ])).stdout.toString().trim();
      final chip = arch == 'arm64' ? 'arm64' : 'amd64';
      for (final tool in ['ffmpeg', 'ffprobe']) {
        final zip = File(p.join(_bin.path, '$tool.zip'));
        await _download(
          'https://ffmpeg.martin-riedl.de/redirect/latest/macos/$chip/release/$tool.zip',
          zip,
        );
        await _unzipBinaries(zip, ours, {tool});
        await Process.run('chmod', ['+x', p.join(ours.path, tool)]);
      }
    }
    return File(p.join(ours.path, exe)).existsSync() ? ours.path : null;
  }

  Future<void> _download(String url, File to) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'Grab-Desktop');
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('Download failed (${res.statusCode}): $url');
      }
      final tmp = File('${to.path}.part');
      await res.pipe(tmp.openWrite());
      await tmp.rename(to.path);
    } finally {
      client.close();
    }
  }

  Future<void> _unzipBinaries(File zip, Directory to, Set<String> names) async {
    final archive = ZipDecoder().decodeStream(InputFileStream(zip.path));
    for (final f in archive.files) {
      final name = p.basename(f.name);
      if (f.isFile && names.contains(name)) {
        final out = OutputFileStream(p.join(to.path, name));
        f.writeContent(out);
        await out.close();
      }
    }
    await zip.delete();
  }

  /// Runs yt-dlp and returns its output, throwing its last error line on failure.
  Future<String> _run(List<String> args) async {
    await _ensureReady();
    final r = await Process.run(
      _ytdlp,
      args,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (r.exitCode != 0) {
      final err = '${r.stderr}'
          .trim()
          .split('\n')
          .lastWhere(
            (l) => l.contains('ERROR'),
            orElse: () => '${r.stderr}'.trim().split('\n').last,
          );
      throw Exception(err.replaceFirst(RegExp(r'^.*ERROR:\s*'), ''));
    }
    return '${r.stdout}';
  }

  List<String> get _ffmpegArgs =>
      _ffmpegDir == null ? const [] : ['--ffmpeg-location', _ffmpegDir!];

  // ---- Engine ----

  @override
  Future<String?> init() async =>
      (await _run(['--version'])).trim().split('\n').first;

  @override
  Future<String?> update() async {
    final out = await _run(['-U']);
    return out.contains('is up to date') ? 'already_up_to_date' : 'updated';
  }

  // Save folder: Downloads, Movies/Videos or Music, plus a folder name.
  static const _baseKey = 'desktop.saveBase', _folderKey = 'desktop.saveFolder';

  @override
  Future<String?> outputDir() async => (await _outDir()).path;

  Future<Directory> _outDir() async {
    final prefs = await SharedPreferences.getInstance();
    final home =
        Platform.environment[_win ? 'USERPROFILE' : 'HOME'] ??
        (await getApplicationDocumentsDirectory()).path;
    final base = switch (prefs.getString(_baseKey)) {
      'movies' => p.join(home, _win ? 'Videos' : 'Movies'),
      'music' => p.join(home, 'Music'),
      _ => (await getDownloadsDirectory())?.path ?? p.join(home, 'Downloads'),
    };
    final dir = Directory(p.join(base, prefs.getString(_folderKey) ?? 'Grab'));
    await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<String?> setOutputDir(String base, String folder) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseKey, base);
    await prefs.setString(
      _folderKey,
      folder.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim().isEmpty
          ? 'Grab'
          : folder.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim(),
    );
    return outputDir();
  }

  @override
  Future<MediaInfo> fetch(String url) async {
    await _ensureReady();
    final jar = File(
      p.join((await getTemporaryDirectory()).path, 'grab-cookies.txt'),
    );
    await jar.parent.create(recursive: true);
    await jar.writeAsString('# Netscape HTTP Cookie File\n');
    final json = await _run([
      '--cookies',
      jar.path,
      '--dump-single-json',
      '--no-warnings',
      '--flat-playlist',
      '--playlist-items',
      '1:300',
      url,
    ]);
    return MediaInfo.fromJsonString(
      url,
      json,
      cookieJar: jar.existsSync() ? await jar.readAsString() : null,
    );
  }

  @override
  Future<String?> previewFile(String url) async {
    final dir = Directory(
      p.join((await getTemporaryDirectory()).path, 'grab-preview'),
    );
    if (dir.existsSync()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final out = await _run([
      '-f',
      'w[vcodec!=none][acodec!=none][ext=mp4]/w[vcodec!=none][acodec!=none]/w',
      '-o',
      p.join(dir.path, 'preview.%(ext)s'),
      '--no-playlist',
      '--no-part',
      ..._ffmpegArgs,
      '--print',
      'after_move:filepath',
      '--no-simulate',
      url,
    ]);
    final path = out
        .trim()
        .split('\n')
        .lastWhere(
          (l) => l.trim().isNotEmpty && File(l.trim()).existsSync(),
          orElse: () => '',
        );
    return path.isEmpty ? null : path.trim();
  }

  /// "[download]  42.0% of ~120.50MiB at 2.30MiB/s ETA 00:41"
  static final _progress = RegExp(r'\[download\]\s+([\d.]+)%');
  static final _eta = RegExp(r'ETA\s+(\d+):(\d+)(?::(\d+))?');
  static final _speed = RegExp(r'at\s+([\d.]+\s*[KMG]?i?B/s)');

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
    // Like the Android engine: start it and return; progress comes as events.
    unawaited(
      _runDownload(
        id: id,
        url: url,
        args: args,
        suffix: suffix,
        match: match,
        template: template,
      ),
    );
  }

  Future<void> _runDownload({
    required String id,
    required String url,
    required List<String> args,
    required String suffix,
    required String? match,
    required String template,
  }) async {
    try {
      await _ensureReady();
    } catch (e) {
      _events.add(EngineEvent(id: id, status: 'error', error: '$e'));
      return;
    }
    final dir = await _outDir();
    final name = template.isEmpty ? '%(title).80B [%(id)s]' : template;
    final started = DateTime.now().subtract(const Duration(seconds: 2));
    _events.add(EngineEvent(id: id, status: 'starting'));
    final proc = await Process.start(_ytdlp, [
      '-o',
      p.join(dir.path, '$name$suffix.%(ext)s'),
      '--no-mtime',
      '--no-playlist',
      '--print',
      'after_move:filepath',
      '--no-simulate',
      '--progress',
      '--newline',
      '--concurrent-fragments',
      '4',
      '--http-chunk-size',
      '10M',
      ..._ffmpegArgs,
      ...args,
      url,
    ]);
    _running[id] = proc;
    final out = StringBuffer();
    final err = StringBuffer();
    final outDone = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final m = _progress.firstMatch(line);
          if (m == null) {
            out.writeln(line);
            return;
          }
          final e = _eta.firstMatch(line);
          _events.add(
            EngineEvent(
              id: id,
              status: 'running',
              progress: double.tryParse(m[1]!),
              eta: e == null
                  ? null
                  : (e[3] == null
                        ? int.parse(e[1]!) * 60 + int.parse(e[2]!)
                        : int.parse(e[1]!) * 3600 +
                              int.parse(e[2]!) * 60 +
                              int.parse(e[3]!)),
              speed: _speed.firstMatch(line)?[1],
              line: line,
            ),
          );
        })
        .asFuture<void>();
    final errDone = proc.stderr
        .transform(utf8.decoder)
        .listen(err.write)
        .asFuture<void>();
    final code = await proc.exitCode;
    await Future.wait([outDone, errDone]);
    final canceled = _running.remove(id) == null;
    if (canceled) {
      _events.add(EngineEvent(id: id, status: 'canceled'));
    } else if (code != 0) {
      final lines = err.toString().trim().split('\n');
      final msg = lines.lastWhere(
        (l) => l.contains('ERROR'),
        orElse: () => lines.isEmpty ? 'yt-dlp exited with $code' : lines.last,
      );
      _events.add(EngineEvent(id: id, status: 'error', error: msg));
    } else {
      _events.add(
        EngineEvent(
          id: id,
          status: 'done',
          progress: 100,
          paths: _collect(dir, out.toString(), match, started),
        ),
      );
    }
  }

  /// The printed media file, plus subtitles and extracted audio sharing its name.
  List<String> _collect(
    Directory dir,
    String out,
    String? match,
    DateTime since,
  ) {
    final printed = out
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && File(l).existsSync())
        .toList();
    final keys = [
      for (final f in printed) '${p.basenameWithoutExtension(f)}.',
      ?match,
    ];
    final fresh = dir
        .listSync()
        .whereType<File>()
        .where(
          (f) =>
              f.lastModifiedSync().isAfter(since) && !f.path.endsWith('.part'),
        )
        .toList();
    var extra = [
      for (final f in fresh)
        if (keys.any((k) => p.basename(f.path).contains(k))) f.path,
    ];
    if (printed.isEmpty && extra.isEmpty) {
      extra = [
        for (final f in fresh)
          if (['.srt', '.vtt', '.ass'].contains(p.extension(f.path))) f.path,
      ];
    }
    return {...printed, ...extra}.toList();
  }

  @override
  Future<void> extractAudio({
    required String id,
    required String input,
    required String format,
    String? title,
  }) async {
    unawaited(_runExtract(id: id, input: input, format: format));
  }

  Future<void> _runExtract({
    required String id,
    required String input,
    required String format,
  }) async {
    await _ensureReady();
    final ffmpeg = _ffmpegDir == null
        ? 'ffmpeg'
        : p.join(_ffmpegDir!, _win ? 'ffmpeg.exe' : 'ffmpeg');
    final src = File(input);
    var out = File(
      p.join(src.parent.path, '${p.basenameWithoutExtension(input)}.$format'),
    );
    for (var n = 2; out.existsSync(); n++) {
      out = File(
        p.join(
          src.parent.path,
          '${p.basenameWithoutExtension(input)} (audio $n).$format',
        ),
      );
    }
    final codec = switch (format) {
      'm4a' => ['-c:a', 'aac', '-b:a', '192k'],
      'opus' => ['-c:a', 'libopus', '-b:a', '160k'],
      'flac' => ['-c:a', 'flac'],
      _ => ['-c:a', 'libmp3lame', '-q:a', '0'],
    };
    _events.add(EngineEvent(id: id, status: 'starting'));
    final proc = await Process.start(ffmpeg, [
      '-hide_banner',
      '-nostdin',
      '-y',
      '-i',
      input,
      '-vn',
      '-map',
      '0:a:0',
      ...codec,
      out.path,
    ]);
    _running[id] = proc;
    double total = 0;
    final dur = RegExp(r'Duration: (\d+):(\d+):([\d.]+)');
    final time = RegExp(r'time=(\d+):(\d+):([\d.]+)');
    double secs(RegExpMatch m) =>
        int.parse(m[1]!) * 3600 + int.parse(m[2]!) * 60 + double.parse(m[3]!);
    final log = StringBuffer();
    await proc.stderr.transform(utf8.decoder).forEach((chunk) {
      if (log.length < 8000) log.write(chunk);
      final d = dur.firstMatch(chunk);
      if (d != null) total = secs(d);
      for (final t in time.allMatches(chunk)) {
        if (total > 0) {
          _events.add(
            EngineEvent(
              id: id,
              status: 'running',
              progress: (secs(t) / total * 100).clamp(0, 100).toDouble(),
            ),
          );
        }
      }
    });
    final code = await proc.exitCode;
    final canceled = _running.remove(id) == null;
    if (canceled) {
      if (out.existsSync()) await out.delete();
      _events.add(EngineEvent(id: id, status: 'canceled'));
    } else if (code != 0) {
      if (out.existsSync()) await out.delete();
      _events.add(
        EngineEvent(
          id: id,
          status: 'error',
          error: log.toString().contains('matches no streams')
              ? 'This file has no audio track'
              : 'FFmpeg exited with $code',
        ),
      );
    } else {
      _events.add(
        EngineEvent(id: id, status: 'done', progress: 100, paths: [out.path]),
      );
    }
  }

  @override
  Future<bool> cancel(String id) async {
    final proc = _running.remove(id);
    if (proc == null) return false;
    if (_win) {
      // yt-dlp starts FFmpeg as a child; end the whole tree.
      await Process.run('taskkill', ['/PID', '${proc.pid}', '/T', '/F']);
    } else {
      proc.kill();
    }
    return true;
  }
}
