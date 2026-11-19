import 'dart:io';

/// Opens a local file or directory in the operating system's default viewer
/// (used on Linux via `xdg-open` for lightweight media playback).
Future<void> openPathExternally(String path) async {
  if (Platform.isLinux) {
    await Process.start('xdg-open', [path], mode: ProcessStartMode.detached);
  } else if (Platform.isMacOS) {
    await Process.start('open', [path], mode: ProcessStartMode.detached);
  } else if (Platform.isWindows) {
    await Process.start('explorer', [path], mode: ProcessStartMode.detached);
  }
}
