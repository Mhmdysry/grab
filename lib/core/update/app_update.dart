import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../log/app_log.dart';

/// Where releases are published.
const repoUrl = 'https://github.com/Mhmdysry/grab';
const _latestApi = 'https://api.github.com/repos/Mhmdysry/grab/releases/latest';

const _channel = MethodChannel('grab/app');

/// Result of launching or committing an APK update install.
class InstallAttemptResult {
  const InstallAttemptResult({
    required this.status,
    this.message,
  });

  /// `'started'`, `'needsPermission'`, `'invalidApk'`, `'conflict'`, `'incompatible'`, or `'error'`.
  final String status;
  final String? message;

  bool get started => status == 'started' || status == 'prompted' || status == 'success';
  bool get needsPermission => status == 'needsPermission';
}

final StreamController<InstallAttemptResult> _installStatusController =
    StreamController<InstallAttemptResult>.broadcast();
bool _listenerRegistered = false;

/// Stream of native Android [PackageInstaller] session commit results.
Stream<InstallAttemptResult> get installStatusStream {
  if (!_listenerRegistered) {
    _listenerRegistered = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'installStatus' && call.arguments is Map) {
        final map = call.arguments as Map;
        final status = '${map['status'] ?? 'failure'}';
        final code = map['code'];
        final rawMsg = '${map['message'] ?? ''}'.trim();
        AppLog.info(
          'AppUpdate',
          'PackageInstaller status=$status (code=$code) message="$rawMsg"',
        );
        _installStatusController.add(
          InstallAttemptResult(
            status: status,
            message: _friendlyInstallError(status, rawMsg),
          ),
        );
      }
    });
  }
  return _installStatusController.stream;
}

String _friendlyInstallError(String status, String raw) {
  switch (status) {
    case 'conflict':
      return 'Signature mismatch with the currently installed build. '
          'If you installed a build older than v1.0.14, uninstall Grab once and install the new APK (all future updates from v1.0.14+ will update in place).';
    case 'incompatible':
      return 'This APK is not compatible with your phone CPU architecture ($raw).';
    case 'invalid':
      return 'The downloaded APK file appears corrupted or incomplete ($raw). Tap Try again.';
    case 'storage':
      return 'Not enough free storage space to install the update.';
    case 'blocked':
      return 'Installation was blocked by device policy or Play Protect ($raw).';
    case 'aborted':
      return 'Installation was canceled.';
    default:
      return raw.isEmpty ? 'Installation failed ($status).' : raw;
  }
}

/// One downloadable file of a release.
class ReleaseAsset {
  const ReleaseAsset(this.name, this.url, this.size);

  final String name;
  final String url;
  final int size;
}

/// The newest published GitHub release.
class Release {
  const Release({
    required this.tag,
    required this.name,
    required this.notes,
    required this.pageUrl,
    required this.assets,
    this.publishedAt,
  });

  /// "v1.2.0"
  final String tag;
  final String name;
  final String notes;
  final String pageUrl;
  final List<ReleaseAsset> assets;
  final DateTime? publishedAt;

  String get version => tag.replaceFirst(RegExp(r'^[vV]'), '');

  factory Release.fromJson(Map<String, dynamic> j) => Release(
    tag: '${j['tag_name'] ?? ''}',
    name: '${j['name'] ?? j['tag_name'] ?? ''}',
    notes: '${j['body'] ?? ''}'.trim(),
    pageUrl: '${j['html_url'] ?? '$repoUrl/releases'}',
    publishedAt: DateTime.tryParse('${j['published_at']}'),
    assets: [
      for (final a in (j['assets'] as List? ?? const []).whereType<Map>())
        ReleaseAsset(
          '${a['name']}',
          '${a['browser_download_url']}',
          (a['size'] as num?)?.toInt() ?? 0,
        ),
    ],
  );

  /// The download for this device: the right APK on Android, the macOS or
  /// Windows package on a computer.
  ReleaseAsset? assetFor(List<String> abis) {
    if (Platform.isLinux) {
      return assets
              .where((a) => a.name.toLowerCase().endsWith('.appimage'))
              .firstOrNull ??
          assets
              .where((a) => a.name.toLowerCase().contains('linux'))
              .firstOrNull;
    }
    if (Platform.isMacOS || Platform.isWindows) {
      final key = Platform.isMacOS ? 'macos' : 'windows';
      return assets
          .where((a) => a.name.toLowerCase().contains(key))
          .firstOrNull;
    }
    return apkFor(abis);
  }

  /// The APK built for this phone: its ABI first, then a universal build.
  ReleaseAsset? apkFor(List<String> all) {
    final abis = all;
    final assets = this.assets
        .where((a) => a.name.toLowerCase().endsWith('.apk'))
        .toList();
    for (final abi in abis) {
      final hit = assets.where((a) => a.name.contains(abi)).firstOrNull;
      if (hit != null) return hit;
    }
    return assets
            .where((a) => !RegExp(r'arm64|armeabi|x86').hasMatch(a.name))
            .firstOrNull ??
        (assets.length == 1 ? assets.first : null);
  }
}

/// True when [latest] ("1.10.0") is newer than [current] ("1.9.2").
bool isNewerVersion(String latest, String current) {
  List<int> parts(String v) => v
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split(RegExp(r'[.+-]'))
      .take(3)
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final a = parts(latest), b = parts(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// Fetches the latest release. Returns null when none is published yet.
Future<Release?> fetchLatestRelease() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final req = await client.getUrl(Uri.parse(_latestApi));
    req.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.userAgentHeader, 'Grab-Android');
    final res = await req.close();
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw HttpException('GitHub answered ${res.statusCode}');
    }
    final body = await res.transform(utf8.decoder).join();
    return Release.fromJson(jsonDecode(body) as Map<String, dynamic>);
  } finally {
    client.close();
  }
}

/// ABIs this phone runs, best first.
Future<List<String>> phoneAbis() async => Platform.isAndroid
    ? (await _channel.invokeListMethod<String>('abis')) ?? const []
    : const [];

/// Downloads [asset] into the app's cache. [onProgress] gets 0..1.
Future<File> downloadUpdate(
  ReleaseAsset asset, {
  required void Function(double) onProgress,
}) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  final file = File('${dir.path}/${asset.name}');
  AppLog.info(
    'AppUpdate',
    'Downloading update asset "${asset.name}" (${asset.size} bytes) from ${asset.url}',
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final req = await client.getUrl(Uri.parse(asset.url));
    req.headers.set(HttpHeaders.userAgentHeader, 'Grab-Android');
    final res = await req.close();
    if (res.statusCode != 200) {
      throw HttpException('Download failed (${res.statusCode})');
    }
    final total = res.contentLength > 0 ? res.contentLength : asset.size;
    final sink = file.openWrite();
    var got = 0;
    try {
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress((got / total).clamp(0, 1));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    final actualSize = file.existsSync() ? file.lengthSync() : 0;
    AppLog.info(
      'AppUpdate',
      'Downloaded "${asset.name}": received $actualSize bytes (expected $total)',
    );
    if (actualSize <= 0 || (total > 0 && actualSize != total)) {
      try {
        file.deleteSync();
      } catch (_) {}
      throw HttpException(
        'Incomplete APK download ($actualSize of $total bytes)',
      );
    }
    return file;
  } catch (e, st) {
    AppLog.error(
      'AppUpdate',
      'downloadUpdate failed for ${asset.name}',
      error: e,
      stackTrace: st,
    );
    rethrow;
  } finally {
    client.close();
  }
}

/// Hands the APK to Android's installer, which updates Grab in place
/// (same app, newer version: downloads, settings and history are kept).
Future<InstallAttemptResult> installUpdateWithDetails(
  File file, {
  bool directViewFallback = false,
}) async {
  if (Platform.isLinux) {
    await Process.start('xdg-open', [file.parent.path], mode: ProcessStartMode.detached);
    return const InstallAttemptResult(status: 'started');
  }
  if (Platform.isMacOS) {
    await Process.run('open', [file.path]);
    return const InstallAttemptResult(status: 'started');
  }
  if (Platform.isWindows) {
    await Process.run('explorer', [file.path]);
    return const InstallAttemptResult(status: 'started');
  }
  final method = directViewFallback ? 'installApkDirect' : 'installApk';
  AppLog.info('AppUpdate', 'Invoking $method for ${file.path}');
  final raw = await _channel.invokeMethod<String>(method, {
    'path': file.path,
  }) ?? 'error:Unknown installer response';
  AppLog.info('AppUpdate', '$method returned: $raw');
  if (raw == 'started' || raw == 'needsPermission') {
    return InstallAttemptResult(status: raw);
  }
  if (raw.startsWith('invalidApk:')) {
    return InstallAttemptResult(
      status: 'invalidApk',
      message: raw.substring('invalidApk:'.length),
    );
  }
  if (raw.startsWith('error:')) {
    return InstallAttemptResult(
      status: 'error',
      message: raw.substring('error:'.length),
    );
  }
  return InstallAttemptResult(status: 'error', message: raw);
}

/// Backwards-compatible bool wrapper around [installUpdateWithDetails].
Future<bool> installUpdate(File file) async {
  final res = await installUpdateWithDetails(file);
  return res.started;
}

Future<void> openUrl(String url) async {
  if (Platform.isLinux) {
    await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
  } else if (Platform.isMacOS) {
    await Process.run('open', [url]);
  } else if (Platform.isWindows) {
    await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
  } else {
    await _channel.invokeMethod('openUrl', {'url': url});
  }
}
