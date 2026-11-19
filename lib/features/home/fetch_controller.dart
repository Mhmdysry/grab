import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/engine/media_info.dart';
import '../../data/repositories/download_repository.dart';

/// Everything the Home + Choose format flow needs.
class FetchState {
  const FetchState({
    this.info = const AsyncData(null),
    this.mode = DownloadMode.video,
    this.optionIndex = 0,
    this.subLangs = const {},
    this.embedSubs = false,
    this.trim,
  });

  final AsyncValue<MediaInfo?> info;
  final DownloadMode mode;
  final int optionIndex;
  final Set<String> subLangs;
  final bool embedSubs;

  /// Part to keep, in seconds; null = the whole thing.
  final ({double start, double end})? trim;

  /// Share of the full length kept, for size estimates.
  double get keptFraction {
    final d = info.value?.duration;
    if (trim == null || d == null || d <= 0) return 1;
    return ((trim!.end - trim!.start) / d).clamp(0, 1);
  }

  List<QualityOption> get options => info.value?.optionsFor(mode) ?? const [];
  QualityOption? get selected => options.isEmpty
      ? null
      : options[optionIndex.clamp(0, options.length - 1)];

  /// Download is possible when there is something to fetch for this mode.
  bool get canDownload =>
      info.value != null &&
      (mode != DownloadMode.subtitlesOnly || subLangs.isNotEmpty);

  FetchState copyWith({
    AsyncValue<MediaInfo?>? info,
    DownloadMode? mode,
    int? optionIndex,
    Set<String>? subLangs,
    bool? embedSubs,
    ({double start, double end})? Function()? trim,
  }) => FetchState(
    info: info ?? this.info,
    mode: mode ?? this.mode,
    optionIndex: optionIndex ?? this.optionIndex,
    subLangs: subLangs ?? this.subLangs,
    embedSubs: embedSubs ?? this.embedSubs,
    trim: trim != null ? trim() : this.trim,
  );
}

class FetchController extends Notifier<FetchState> {
  @override
  FetchState build() =>
      FetchState(mode: ref.read(settingsProvider).defaultMode);

  Future<void> fetch(String url) async {
    url = url.trim();
    if (url.isEmpty) return;
    final settings = ref.read(settingsProvider);
    state = FetchState(info: const AsyncLoading(), mode: settings.defaultMode);
    final result = await AsyncValue.guard(
      () => ref.read(engineProvider).fetch(url),
    );
    if (result is AsyncData && result.value != null) {
      ref.read(downloadRepositoryProvider).markOnline();
    }
    state = state.copyWith(
      info: result is AsyncError
          ? AsyncError(friendlyError(result.error!), result.stackTrace!)
          : result,
    );
    state = state.copyWith(
      optionIndex: settings.preferredOptionIndex(state.options),
    );
  }

  void setMode(DownloadMode m) {
    state = state.copyWith(mode: m);
    state = state.copyWith(
      optionIndex: ref
          .read(settingsProvider)
          .preferredOptionIndex(state.options),
    );
  }

  void setOption(int i) => state = state.copyWith(optionIndex: i);
  void setEmbed(bool v) => state = state.copyWith(embedSubs: v);

  /// Turns trimming on (whole length to start with) or off.
  void setTrimOn(bool on) {
    final d = state.info.value?.duration;
    state = state.copyWith(
      trim: () => on && d != null ? (start: 0.0, end: d) : null,
    );
  }

  void setTrim(double start, double end) =>
      state = state.copyWith(trim: () => (start: start, end: end));

  void toggleLang(String lang) {
    final next = {...state.subLangs};
    next.contains(lang) ? next.remove(lang) : next.add(lang);
    state = state.copyWith(subLangs: next);
  }

  /// Queues the download and returns the job id.
  Future<String?> download() async {
    final info = state.info.value;
    if (info == null || !state.canDownload) return null;
    final langs = state.subLangs.toList();
    final auto = info.subtitles.any((t) => t.auto && langs.contains(t.lang));
    final settings = ref.read(settingsProvider);
    final t = state.trim;
    final d = info.duration;
    // Unchanged ends mean "from the start" / "to the end".
    final start = t == null || t.start <= 0 ? null : t.start;
    final end = t == null || (d != null && t.end >= d) ? null : t.end;
    final repo = ref.read(downloadRepositoryProvider)..markOnline();
    return repo.enqueue(
      DownloadRequest(
        info: info,
        mode: state.mode,
        maxHeight: state.selected?.height,
        estimatedBytes: state.selected?.bytes == null
            ? null
            : (state.selected!.bytes! * state.keptFraction).round(),
        trimStart: state.mode == DownloadMode.subtitlesOnly ? null : start,
        trimEnd: state.mode == DownloadMode.subtitlesOnly ? null : end,
        subtitles: SubtitleChoice(
          langs: langs,
          includeAuto: auto,
          embed: state.embedSubs,
        ),
        container: settings.container,
        audioFormat: settings.audioFormat,
      ),
    );
  }

  static Object friendlyError(Object e) {
    if (e is PlatformException) {
      final msg = e.message ?? '';
      final line = msg
          .split('\n')
          .lastWhere((l) => l.contains('ERROR'), orElse: () => msg);
      return line.replaceFirst(RegExp(r'^.*ERROR:\s*'), '').trim();
    }
    return e;
  }
}

final fetchControllerProvider = NotifierProvider<FetchController, FetchState>(
  FetchController.new,
);
