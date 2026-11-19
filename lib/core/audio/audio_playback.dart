import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../../features/library/library_items.dart';
import '../log/app_log.dart';
import '../utils/desktop_open.dart';
import '../utils/platform.dart';

/// The one audio player in the app. It keeps playing with the screen off or the
/// app in the background, with controls in the notification and on the lock screen.
abstract final class AudioPlayback {
  static final AudioPlayer? _player = Platform.isLinux ? null : AudioPlayer();
  static AudioPlayer get player => _player!;

  static Stream<bool> get playingStream =>
      _player?.playingStream ?? Stream<bool>.value(false);
  static bool get isPlaying => _player?.playing ?? false;
  static Stream<Duration> get positionStream =>
      _player?.positionStream ?? Stream<Duration>.value(Duration.zero);
  static Duration get position => _player?.position ?? Duration.zero;
  static Duration? get duration => _player?.duration;

  /// What is loaded (playing or paused); null when stopped.
  static final current = ValueNotifier<LibraryItem?>(null);

  static bool _inited = false;

  /// Call once in main(), before runApp.
  static Future<void> init() async {
    if (_inited) return;
    _inited = true;
    // Lock-screen and notification controls are a phone thing.
    if (isPhone) {
      try {
        await _initBackground();
        AppLog.info('AudioPlayback', 'JustAudioBackground initialized');
      } catch (e, st) {
        AppLog.error(
          'AudioPlayback',
          'JustAudioBackground.init failed; falling back to local player',
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  static Future<void> _initBackground() => JustAudioBackground.init(
    androidNotificationChannelId: 'app.grab.grab.playback',
    androidNotificationChannelName: 'Playback',
    androidNotificationOngoing: true,
    androidNotificationIcon: 'drawable/ic_stat_grab',
  );

  static Uri? _validArtUri(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https') {
      return uri.host.isNotEmpty ? uri : null;
    }
    if (scheme == 'file') {
      return uri.path.isNotEmpty ? uri : null;
    }
    return null;
  }

  /// Loads [item] (unless it is already loaded) and plays it.
  static Future<void> play(LibraryItem item) async {
    if (Platform.isLinux) {
      await openPathExternally(item.path);
      return;
    }
    final p = _player;
    if (p == null) return;
    try {
      await init();
      AppLog.info(
        'AudioPlayback',
        'play requested: title="${item.title}" path="${item.path}"',
      );
      if (current.value?.path != item.path) {
        final file = File(item.path);
        if (!file.existsSync()) {
          AppLog.warn(
            'AudioPlayback',
            'Audio file does not exist on disk: ${item.path}',
          );
          return;
        }
        await p.setAudioSource(
          AudioSource.file(
            item.path,
            tag: MediaItem(
              id: item.path,
              title: item.title,
              album: item.site ?? 'Grab',
              artUri: _validArtUri(item.thumbnail),
            ),
          ),
        );
        current.value = item;
      }
      await p.play();
    } catch (e, st) {
      AppLog.error(
        'AudioPlayback',
        'Failed to play audio "${item.path}"',
        error: e,
        stackTrace: st,
      );
    }
  }

  static Future<void> toggle() async {
    final p = _player;
    if (p == null) return;
    try {
      if (p.playing) {
        await p.pause();
      } else {
        await p.play();
      }
    } catch (e, st) {
      AppLog.error('AudioPlayback', 'toggle failed', error: e, stackTrace: st);
    }
  }

  /// Call before deleting a file, so the player never holds a missing file.
  static Future<void> forget(String path) async {
    if (current.value?.path == path) await stop();
  }

  static Future<void> stop() async {
    final p = _player;
    if (p == null) {
      current.value = null;
      return;
    }
    try {
      await p.stop();
      current.value = null;
    } catch (e, st) {
      AppLog.error('AudioPlayback', 'stop failed', error: e, stackTrace: st);
    }
  }
}
