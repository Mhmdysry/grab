import 'package:flutter_test/flutter_test.dart';
import 'package:grab/core/update/app_update.dart';

void main() {
  test('version comparison', () {
    expect(isNewerVersion('v1.1.0', '1.0.0'), isTrue);
    expect(isNewerVersion('1.10.0', '1.9.2'), isTrue);
    expect(isNewerVersion('v1.0.0', '1.0.0'), isFalse);
    expect(isNewerVersion('0.9.9', '1.0.0'), isFalse);
    expect(isNewerVersion('2', '1.9.9'), isTrue);
  });

  test('picks the APK for this phone', () {
    final r = Release.fromJson({
      'tag_name': 'v1.1.0',
      'assets': [
        {
          'name': 'grab-v1.1.0-armeabi-v7a.apk',
          'browser_download_url': 'a',
          'size': 1,
        },
        {
          'name': 'grab-v1.1.0-arm64-v8a.apk',
          'browser_download_url': 'b',
          'size': 1,
        },
        {'name': 'grab-v1.1.0.apk', 'browser_download_url': 'u', 'size': 1},
        {'name': 'notes.txt', 'browser_download_url': 'n', 'size': 1},
      ],
    });
    expect(r.version, '1.1.0');
    expect(r.assets, hasLength(4)); // every file; apkFor picks among the APKs
    expect(r.apkFor(['arm64-v8a', 'armeabi-v7a'])!.url, 'b');
    expect(r.apkFor(['x86_64'])!.url, 'u');
  });

  test('fork release URL and auto-incremented CI build versions match', () {
    expect(repoUrl, 'https://github.com/Mhmdysry/grab');
    expect(isNewerVersion('v1.0.13', '1.0.12'), isTrue);
    final r = Release.fromJson({
      'tag_name': 'v1.0.13',
      'assets': [
        {
          'name': 'grab-expressive-v1.0.13-arm64-v8a.apk',
          'browser_download_url': 'https://github.com/Mhmdysry/grab/releases/download/v1.0.13/grab-expressive-v1.0.13-arm64-v8a.apk',
          'size': 1024,
        },
        {
          'name': 'grab-expressive-v1.0.13-armeabi-v7a.apk',
          'browser_download_url': 'https://github.com/Mhmdysry/grab/releases/download/v1.0.13/grab-expressive-v1.0.13-armeabi-v7a.apk',
          'size': 1024,
        },
      ],
    });
    expect(
      r.apkFor(['arm64-v8a', 'armeabi-v7a'])?.name,
      'grab-expressive-v1.0.13-arm64-v8a.apk',
    );
  });
}
