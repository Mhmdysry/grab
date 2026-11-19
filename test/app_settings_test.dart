import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grab/data/engine/media_info.dart';
import 'package:grab/data/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults when nothing is saved', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings.load(await SharedPreferences.getInstance());
    expect(s.themeMode, ThemeMode.system);
    expect(s.defaultMode, DownloadMode.video);
    expect(s.maxHeight, isNull);
    expect(s.maxParallel, 2);
    expect(s.accentPalette, M3Palette.amber);
    expect(s.useDynamicColor, isFalse);
    expect(s.schemeStyle, M3SchemeStyle.expressive);
    expect(s.amoledDark, isFalse);
    expect(s.contrast, M3Contrast.standard);
    expect(s.motionPreset, M3MotionPreset.expressive);
    expect(s.shapeStyle, M3ShapeStyle.expressive);
    expect(s.navStyle, M3NavStyle.floatingPill);
    expect(s.density, M3Density.cozy);
    expect(s.libraryColumns, 2);
    expect(s.fontScale, 1.0);
    expect(s.hapticsEnabled, isTrue);
    expect(s.confettiEnabled, isTrue);
    expect(s.artworkTinting, isTrue);
    expect(s.shareKeepOpen, isFalse);
    expect(s.instantGrab, isFalse);
  });

  test('round-trips through storage', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    await const AppSettings(
      themeMode: ThemeMode.dark,
      defaultMode: DownloadMode.audioOnly,
      maxHeight: 720,
      container: 'mkv',
      audioFormat: 'opus',
      maxParallel: 3,
      accentPalette: M3Palette.violet,
      useDynamicColor: true,
      schemeStyle: M3SchemeStyle.vibrant,
      amoledDark: true,
      contrast: M3Contrast.high,
      motionPreset: M3MotionPreset.snappy,
      shapeStyle: M3ShapeStyle.crisp,
      navStyle: M3NavStyle.minimalDock,
      density: M3Density.compact,
      libraryColumns: 3,
      fontScale: 1.2,
      hapticsEnabled: false,
      confettiEnabled: false,
      artworkTinting: false,
      shareKeepOpen: true,
      instantGrab: true,
    ).save(p);
    final s = AppSettings.load(p);
    expect(s.themeMode, ThemeMode.dark);
    expect(s.defaultMode, DownloadMode.audioOnly);
    expect(s.maxHeight, 720);
    expect(s.container, 'mkv');
    expect(s.audioFormat, 'opus');
    expect(s.maxParallel, 3);
    expect(s.accentPalette, M3Palette.violet);
    expect(s.useDynamicColor, isTrue);
    expect(s.schemeStyle, M3SchemeStyle.vibrant);
    expect(s.amoledDark, isTrue);
    expect(s.contrast, M3Contrast.high);
    expect(s.motionPreset, M3MotionPreset.snappy);
    expect(s.shapeStyle, M3ShapeStyle.crisp);
    expect(s.navStyle, M3NavStyle.minimalDock);
    expect(s.density, M3Density.compact);
    expect(s.libraryColumns, 3);
    expect(s.fontScale, 1.2);
    expect(s.hapticsEnabled, isFalse);
    expect(s.confettiEnabled, isFalse);
    expect(s.artworkTinting, isFalse);
    expect(s.shareKeepOpen, isTrue);
    expect(s.instantGrab, isTrue);
  });

  test('ignores bad stored values', () async {
    SharedPreferences.setMockInitialValues({
      'mode': 'subtitlesOnly',
      'container': 'avi',
      'maxHeight': 999,
      'maxParallel': 40,
      'accentPalette': 'neon_invalid',
      'schemeStyle': 'unknown',
      'contrast': 'ultra',
      'motionPreset': 'turbo',
      'shapeStyle': 'triangle',
      'navStyle': 'drawer',
      'density': 'mega',
      'libraryColumns': 9,
      'fontScale': 3.5,
    });
    final s = AppSettings.load(await SharedPreferences.getInstance());
    expect(s.defaultMode, DownloadMode.video);
    expect(s.container, 'mp4');
    expect(s.maxHeight, isNull);
    expect(s.maxParallel, 3);
    expect(s.accentPalette, M3Palette.amber);
    expect(s.schemeStyle, M3SchemeStyle.expressive);
    expect(s.contrast, M3Contrast.standard);
    expect(s.motionPreset, M3MotionPreset.expressive);
    expect(s.shapeStyle, M3ShapeStyle.expressive);
    expect(s.navStyle, M3NavStyle.floatingPill);
    expect(s.density, M3Density.cozy);
    expect(s.libraryColumns, 2);
    expect(s.fontScale, 1.0);
  });

  test('resetAppearance resets only visual fields', () {
    const custom = AppSettings(
      container: 'mkv',
      maxParallel: 3,
      accentPalette: M3Palette.emerald,
      amoledDark: true,
      navStyle: M3NavStyle.dockedBar,
      motionPreset: M3MotionPreset.off,
      libraryColumns: 3,
      fontScale: 1.2,
      hapticsEnabled: false,
      artworkTinting: false,
      shareKeepOpen: true,
      instantGrab: true,
    );
    final reset = custom.resetAppearance();
    expect(reset.container, 'mkv');
    expect(reset.maxParallel, 3);
    expect(reset.accentPalette, M3Palette.amber);
    expect(reset.amoledDark, isFalse);
    expect(reset.navStyle, M3NavStyle.floatingPill);
    expect(reset.motionPreset, M3MotionPreset.expressive);
    expect(reset.libraryColumns, 2);
    expect(reset.fontScale, 1.0);
    expect(reset.hapticsEnabled, isTrue);
    expect(reset.artworkTinting, isTrue);
    expect(reset.shareKeepOpen, isTrue);
    expect(reset.instantGrab, isTrue);
  });

  test('picks the closest quality without going over', () {
    const opts = [
      QualityOption(label: '1080p', height: 1080),
      QualityOption(label: '720p', height: 720),
      QualityOption(label: '360p', height: 360),
    ];
    expect(const AppSettings().preferredOptionIndex(opts), 0);
    expect(const AppSettings(maxHeight: 720).preferredOptionIndex(opts), 1);
    expect(const AppSettings(maxHeight: 480).preferredOptionIndex(opts), 2);
    expect(const AppSettings(maxHeight: 240).preferredOptionIndex(opts), 2);
  });
}
