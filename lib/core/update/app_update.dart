import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Where releases are published.
const repoUrl = 'https://github.com/Mhmdysry/grab';
const _latestApi = 'https://api.github.com/repos/Mhmdysry/grab/releases/latest';

const _channel = MethodChannel('grab/app');

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
  final client = HttpClient();
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
    await for (final chunk in res) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress((got / total).clamp(0, 1));
    }
    await sink.close();
    return file;
  } finally {
    client.close();
  }
}

/// Hands the APK to Android's installer, which updates Grab in place
/// (same app, newer version: downloads, settings and history are kept).
/// Returns false when the user first has to allow Grab to install apps.
Future<bool> installUpdate(File file) async {
  if (Platform.isMacOS) {
    // Opens the disk image; drag Grab to Applications to replace the old one.
    await Process.run('open', [file.path]);
    return true;
  }
  if (Platform.isWindows) {
    await Process.run('explorer', [file.path]);
    return true;
  }
  return await _channel.invokeMethod<String>('installApk', {
        'path': file.path,
      }) ==
      'started';
}

Future<void> openUrl(String url) async {
  if (Platform.isMacOS) {
    await Process.run('open', [url]);
  } else if (Platform.isWindows) {
    await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
  } else {
    await _channel.invokeMethod('openUrl', {'url': url});
  }
}
