import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';

import '../../app/providers.dart';
import '../../core/theme/pop_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/links.dart';
import '../../core/utils/permissions.dart';
import '../../core/widgets/app_scale.dart';
import '../../core/widgets/expressive_shapes.dart';
import '../../core/widgets/pop_widgets.dart';
import '../../core/widgets/toasts.dart';
import '../../data/db/app_database.dart';
import '../../data/engine/media_info.dart';
import '../../data/repositories/download_repository.dart';
import '../../data/settings/app_settings.dart';
import '../home/clip_preview.dart';
import '../home/fetch_controller.dart';

/// Visual phases of the floating share download card.
enum ShareCardPhase { loading, ready, error, queued, progress }

/// Dedicated translucent Flutter app hosted inside Android's `ShareActivity`.
class ShareOverlayApp extends ConsumerWidget {
  const ShareOverlayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final dynamicSeed = ref.watch(dynamicColorProvider).value;
    Haptics.enabled = settings.hapticsEnabled;

    return MediaQuery.fromView(
      view: View.of(context),
      child: AppScale(
        fontScale: settings.fontScale,
        child: ToastificationWrapper(
          child: MaterialApp(
            title: 'Grab Share',
            debugShowCheckedModeBanner: false,
            color: Colors.transparent,
            theme: buildExpressiveTheme(
              settings,
              brightness: Brightness.light,
              dynamicSeed: dynamicSeed,
            ),
            darkTheme: buildExpressiveTheme(
              settings,
              brightness: Brightness.dark,
              dynamicSeed: dynamicSeed,
            ),
            themeMode: settings.themeMode,
            builder: (context, child) {
              final theme = Theme.of(context);
              syncToastScheme(theme.colorScheme);
              syncBubbleConfig(
                enabled: settings.floatingBubbleEnabled,
                scheme: theme.colorScheme,
              );
              final isDark = theme.brightness == Brightness.dark;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: isDark
                    ? SystemUiOverlayStyle.light.copyWith(
                        statusBarColor: Colors.transparent,
                        systemNavigationBarColor: Colors.transparent,
                      )
                    : SystemUiOverlayStyle.dark.copyWith(
                        statusBarColor: Colors.transparent,
                        systemNavigationBarColor: Colors.transparent,
                      ),
                child: child!,
              );
            },
            home: const _ShareOverlayHost(),
          ),
        ),
      ),
    );
  }
}

class _ShareOverlayHost extends ConsumerStatefulWidget {
  const _ShareOverlayHost();

  @override
  ConsumerState<_ShareOverlayHost> createState() => _ShareOverlayHostState();
}

class _ShareOverlayHostState extends ConsumerState<_ShareOverlayHost>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _channel = MethodChannel('grab/share');
  static const _dismissedBubbleKey = 'dismissedBubblePrompt';

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );

  ShareCardPhase _phase = ShareCardPhase.loading;
  String? _sharedUrl;
  String? _customError;
  var _expanded = false;
  var _busyEnqueue = false;
  var _showBubblePrompt = false;
  String? _queuedJobId;
  int _queuedCount = 1;
  final Set<int> _playlistPicked = {};
  Timer? _autoCloseTimer;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText') {
        await _handleIncoming(call.arguments as String?);
      }
    });
    _channel
        .invokeMethod<String>('takeSharedText')
        .then(_handleIncoming, onError: (_) {});
    _refreshBubblePrompt();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoCloseTimer?.cancel();
    _entrance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshBubblePrompt();
    }
  }

  Future<void> _refreshBubblePrompt() async {
    final prefs = ref.read(sharedPrefsProvider);
    final dismissed = prefs.getBool(_dismissedBubbleKey) ?? false;
    final enabled = ref.read(settingsProvider).floatingBubbleEnabled;
    if (dismissed || !enabled) {
      if (mounted && _showBubblePrompt) {
        setState(() => _showBubblePrompt = false);
      }
      return;
    }
    final granted = await overlayPermissionGranted();
    if (!mounted) return;
    setState(() => _showBubblePrompt = !granted);
  }

  Future<void> _enableBubble() async {
    Haptics.selection();
    final granted = await requestOverlayPermission(context);
    if (!mounted) return;
    if (granted) {
      setState(() => _showBubblePrompt = false);
      await syncBubbleConfig(
        enabled: true,
        scheme: Theme.of(context).colorScheme,
      );
    }
  }

  Future<void> _dismissBubblePrompt() async {
    Haptics.selection();
    await ref.read(sharedPrefsProvider).setBool(_dismissedBubbleKey, true);
    if (mounted) setState(() => _showBubblePrompt = false);
  }

  Future<void> _handleIncoming(String? raw) async {
    _autoCloseTimer?.cancel();
    await ref.read(sharedPrefsProvider).reload();
    ref.invalidate(settingsProvider);
    if (!mounted) return;
    _refreshBubblePrompt();

    final link = extractLink(raw) ?? raw?.trim();
    setState(() {
      _dragOffset = 0;
      _expanded = false;
      _busyEnqueue = false;
      _queuedJobId = null;
      _queuedCount = 1;
      _playlistPicked.clear();
      _customError = null;
      _sharedUrl = link;
      _phase = (link == null || link.isEmpty)
          ? ShareCardPhase.error
          : ShareCardPhase.loading;
      if (link == null || link.isEmpty) {
        _customError = 'No link found in what was shared.';
      }
    });

    final reduced = Pop.reduceMotion(context);
    if (reduced) {
      _entrance.value = 1.0;
    } else {
      _entrance.forward(from: 0.0);
    }

    if (link != null && link.isNotEmpty) {
      await ref.read(fetchControllerProvider.notifier).fetch(link);
    }
  }

  Future<void> _dismiss() async {
    _autoCloseTimer?.cancel();
    if (!mounted) return;
    final reduced = Pop.reduceMotion(context);
    if (!reduced && _entrance.value > 0) {
      await _entrance.reverse();
    }
    try {
      await _channel.invokeMethod('closeOverlay');
    } catch (_) {}
  }

  Future<void> _openInGrab() async {
    _autoCloseTimer?.cancel();
    try {
      if (_queuedJobId != null) {
        await _channel.invokeMethod('openMainApp', {'tab': 'downloads'});
      } else {
        await _channel.invokeMethod('openMainApp', {'url': _sharedUrl});
      }
    } catch (_) {}
  }

  Future<void> _download() async {
    if (_busyEnqueue) return;
    final fetch = ref.read(fetchControllerProvider);
    final info = fetch.info.value;
    if (info == null) return;

    setState(() => _busyEnqueue = true);
    final ok = await ensureDownloadPermissions(
      context,
      ref.read(sharedPrefsProvider),
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _busyEnqueue = false);
      popToast(
        'Grab needs storage access to save files',
        error: true,
        context: context,
      );
      return;
    }

    String? jobId;
    var count = 1;
    if (info.isPlaylist && info.entries.isNotEmpty) {
      final picked = _playlistPicked.toList()..sort();
      if (picked.isEmpty) {
        setState(() => _busyEnqueue = false);
        return;
      }
      final settings = ref.read(settingsProvider);
      final repo = ref.read(downloadRepositoryProvider);
      final mode = fetch.mode == DownloadMode.subtitlesOnly
          ? DownloadMode.video
          : fetch.mode;
      count = picked.length;
      for (final i in picked) {
        final e = info.entries[i];
        final id = await repo.enqueue(
          DownloadRequest(
            info: MediaInfo(
              url: e.url,
              title: e.title,
              id: e.id,
              thumbnail: e.thumbnail,
              duration: e.duration,
              site: info.site,
            ),
            mode: mode,
            maxHeight: mode == DownloadMode.audioOnly
                ? null
                : fetch.selected?.height,
            container: settings.container,
            audioFormat: settings.audioFormat,
          ),
        );
        jobId ??= id;
      }
    } else {
      jobId = await ref.read(fetchControllerProvider.notifier).download();
    }

    if (!mounted) return;
    setState(() => _busyEnqueue = false);
    if (jobId == null) return;

    Haptics.success();
    final keepOpen = ref.read(settingsProvider).shareKeepOpen;
    setState(() {
      _queuedJobId = jobId;
      _queuedCount = count;
      _phase = ShareCardPhase.queued;
    });

    _autoCloseTimer?.cancel();
    if (keepOpen) {
      _autoCloseTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _phase = ShareCardPhase.progress);
      });
    } else {
      _autoCloseTimer = Timer(const Duration(milliseconds: 900), _dismiss);
    }
  }

  void _watchProgress() {
    _autoCloseTimer?.cancel();
    if (mounted) setState(() => _phase = ShareCardPhase.progress);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(fetchControllerProvider.select((s) => s.info), (prev, next) {
      if (!mounted) return;
      if (next is AsyncData && next.value != null) {
        Haptics.light();
        final info = next.value!;
        setState(() {
          _phase = ShareCardPhase.ready;
          _playlistPicked
            ..clear()
            ..addAll([for (var i = 0; i < info.entries.length; i++) i]);
        });
      } else if (next is AsyncError) {
        setState(() => _phase = ShareCardPhase.error);
      } else if (next is AsyncLoading && _phase != ShareCardPhase.queued) {
        setState(() => _phase = ShareCardPhase.loading);
      }
    });

    final fetchState = ref.watch(fetchControllerProvider);
    final fetchCtrl = ref.read(fetchControllerProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final m3 = context.m3;
    final jobs = ref.watch(jobsProvider).value ?? const <DownloadJob>[];
    final activeJob = _queuedJobId == null
        ? null
        : jobs.where((j) => j.id == _queuedJobId).firstOrNull;
    final activeSpeed = _queuedJobId == null
        ? null
        : ref.watch(speedsProvider).value?[_queuedJobId];

    final slideAnim = CurvedAnimation(
      parent: _entrance,
      curve: m3.motion.defaultSpatialCurve,
      reverseCurve: Curves.easeInCubic,
    );
    final fadeAnim = CurvedAnimation(
      parent: _entrance,
      curve: m3.motion.effectsCurve,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                child: FadeTransition(
                  opacity: fadeAnim,
                  child: const ColoredBox(color: Colors.black45),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 1.05),
                      end: Offset.zero,
                    ).animate(slideAnim),
                    child: Transform.translate(
                      offset: Offset(0, _dragOffset),
                      child: GestureDetector(
                        onVerticalDragUpdate: (d) {
                          if (d.delta.dy > 0 || _dragOffset > 0) {
                            setState(() {
                              _dragOffset = (_dragOffset + d.delta.dy).clamp(
                                0.0,
                                400.0,
                              );
                            });
                          }
                        },
                        onVerticalDragEnd: (d) {
                          if (_dragOffset > 96 ||
                              (d.primaryVelocity ?? 0) > 420) {
                            _dismiss();
                          } else {
                            setState(() => _dragOffset = 0);
                          }
                        },
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: ShareOverlayCard(
                            phase: _phase,
                            fetchState: fetchState,
                            settings: settings,
                            url: _sharedUrl,
                            errorMessage: _customError,
                            expanded: _expanded,
                            busy: _busyEnqueue,
                            onToggleExpand: () {
                              Haptics.selection();
                              setState(() => _expanded = !_expanded);
                            },
                            onModeChanged: fetchCtrl.setMode,
                            onOptionChanged: fetchCtrl.setOption,
                            onTrimToggle: fetchCtrl.setTrimOn,
                            onTrimChanged: fetchCtrl.setTrim,
                            onToggleLang: fetchCtrl.toggleLang,
                            onEmbedSubsChanged: fetchCtrl.setEmbed,
                            playlistPicked: _playlistPicked,
                            onTogglePlaylistItem: (i) {
                              Haptics.selection();
                              setState(() {
                                _playlistPicked.contains(i)
                                    ? _playlistPicked.remove(i)
                                    : _playlistPicked.add(i);
                              });
                            },
                            onTogglePlaylistAll: () {
                              Haptics.selection();
                              final count =
                                  fetchState.info.value?.entries.length ?? 0;
                              setState(() {
                                if (_playlistPicked.length == count) {
                                  _playlistPicked.clear();
                                } else {
                                  _playlistPicked.addAll([
                                    for (var i = 0; i < count; i++) i,
                                  ]);
                                }
                              });
                            },
                            onDownload: _download,
                            onRetry: _sharedUrl == null
                                ? null
                                : () {
                                    setState(
                                      () => _phase = ShareCardPhase.loading,
                                    );
                                    fetchCtrl.fetch(_sharedUrl!);
                                  },
                            onWatchProgress: _watchProgress,
                            onOpenInGrab: _openInGrab,
                            onDismiss: _dismiss,
                            queuedCount: _queuedCount,
                            activeJob: activeJob,
                            activeSpeed: activeSpeed,
                            onPauseResumeJob: activeJob == null
                                ? null
                                : () {
                                    final repo = ref.read(
                                      downloadRepositoryProvider,
                                    );
                                    if (activeJob.status == JobStatus.paused) {
                                      repo.unpause(activeJob.id);
                                    } else {
                                      repo.pause(activeJob.id);
                                    }
                                  },
                            onCancelJob: activeJob == null
                                ? null
                                : () => ref
                                      .read(downloadRepositoryProvider)
                                      .cancel(activeJob.id),
                            showBubblePrompt: _showBubblePrompt,
                            onEnableBubble: _enableBubble,
                            onDismissBubblePrompt: _dismissBubblePrompt,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating Material 3 Expressive share card supporting compact & expanded
/// download options, queued celebration, and optional live progress tracking.
class ShareOverlayCard extends StatelessWidget {
  const ShareOverlayCard({
    super.key,
    required this.phase,
    required this.fetchState,
    required this.settings,
    this.url,
    this.errorMessage,
    this.expanded = false,
    this.busy = false,
    this.onToggleExpand,
    this.onModeChanged,
    this.onOptionChanged,
    this.onTrimToggle,
    this.onTrimChanged,
    this.onToggleLang,
    this.onEmbedSubsChanged,
    this.playlistPicked = const {},
    this.onTogglePlaylistItem,
    this.onTogglePlaylistAll,
    this.onDownload,
    this.onRetry,
    this.onWatchProgress,
    this.onOpenInGrab,
    this.onDismiss,
    this.queuedCount = 1,
    this.activeJob,
    this.activeSpeed,
    this.onPauseResumeJob,
    this.onCancelJob,
    this.showBubblePrompt = false,
    this.onEnableBubble,
    this.onDismissBubblePrompt,
  });

  final ShareCardPhase phase;
  final FetchState fetchState;
  final AppSettings settings;
  final String? url;
  final String? errorMessage;
  final bool expanded;
  final bool busy;
  final VoidCallback? onToggleExpand;
  final ValueChanged<DownloadMode>? onModeChanged;
  final ValueChanged<int>? onOptionChanged;
  final ValueChanged<bool>? onTrimToggle;
  final void Function(double start, double end)? onTrimChanged;
  final ValueChanged<String>? onToggleLang;
  final ValueChanged<bool>? onEmbedSubsChanged;
  final Set<int> playlistPicked;
  final ValueChanged<int>? onTogglePlaylistItem;
  final VoidCallback? onTogglePlaylistAll;
  final VoidCallback? onDownload;
  final VoidCallback? onRetry;
  final VoidCallback? onWatchProgress;
  final VoidCallback? onOpenInGrab;
  final VoidCallback? onDismiss;
  final int queuedCount;
  final DownloadJob? activeJob;
  final String? activeSpeed;
  final VoidCallback? onPauseResumeJob;
  final VoidCallback? onCancelJob;
  final bool showBubblePrompt;
  final VoidCallback? onEnableBubble;
  final VoidCallback? onDismissBubblePrompt;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxH = MediaQuery.sizeOf(context).height * 0.78;
    final radius = m3.cardRadiusValue + 4;

    return Material(
      color: cs.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.16),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: m3.motion.resolve(
                    context,
                    m3.motion.defaultEffectsDuration,
                  ),
                  switchInCurve: m3.motion.effectsCurve,
                  child: switch (phase) {
                    ShareCardPhase.loading => _buildLoading(context),
                    ShareCardPhase.error => _buildError(context),
                    ShareCardPhase.ready => _buildReady(context),
                    ShareCardPhase.queued => _buildQueued(context),
                    ShareCardPhase.progress => _buildProgress(context),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    final cs = context.cs;
    final platform = platformOf(url);
    return Column(
      key: const ValueKey('loading'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const ExpressiveLoadingIndicator(size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Reading link…',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (platform != null) ...[
                        const SizedBox(width: 8),
                        PopTag(
                          platform,
                          color: cs.primaryContainer,
                          foreground: cs.onPrimaryContainer,
                        ),
                      ],
                    ],
                  ),
                  if (url != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      url!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: onOpenInGrab,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open in Grab'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final msg =
        errorMessage ??
        (fetchState.info.hasError
            ? '${fetchState.info.error}'
            : "Couldn't read that link.");
    return Column(
      key: const ValueKey('error'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: m3.cardRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Couldn't read that link",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: cs.onErrorContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                msg,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: cs.onErrorContainer),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            if (onRetry != null)
              Expanded(
                child: PopButton(
                  label: 'Try again',
                  icon: Icons.refresh_rounded,
                  height: 48,
                  onPressed: onRetry,
                ),
              ),
            if (onRetry != null) const SizedBox(width: 8),
            Expanded(
              child: PopButton(
                label: 'Open in Grab',
                icon: Icons.open_in_new_rounded,
                style: PopButtonStyle.tonal,
                height: 48,
                onPressed: onOpenInGrab,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReady(BuildContext context) {
    final info = fetchState.info.value;
    if (info == null) return _buildLoading(context);

    final cs = context.cs;
    final m3 = context.m3;
    final isPlaylist = info.isPlaylist && info.entries.isNotEmpty;

    final compactModes = <DownloadMode>[
      DownloadMode.video,
      if (fetchState.mode == DownloadMode.videoAndAudio)
        DownloadMode.videoAndAudio,
      DownloadMode.audioOnly,
    ];
    final allModes = <DownloadMode>[
      DownloadMode.video,
      DownloadMode.videoAndAudio,
      DownloadMode.audioOnly,
      if (!isPlaylist && info.subtitles.isNotEmpty) DownloadMode.subtitlesOnly,
    ];
    final modes = expanded ? allModes : compactModes;
    const modeLabels = {
      DownloadMode.video: 'Video',
      DownloadMode.videoAndAudio: 'Video + audio',
      DownloadMode.audioOnly: 'Audio',
      DownloadMode.subtitlesOnly: 'Subs',
    };
    final activeMode = modes.contains(fetchState.mode)
        ? fetchState.mode
        : modes.first;

    final options = fetchState.options;
    final selectedIdx = options.isEmpty
        ? 0
        : fetchState.optionIndex.clamp(0, options.length - 1);
    final compactOptions = options.length <= 4
        ? options
        : options.sublist(0, 4);

    final canPressDownload = isPlaylist
        ? playlistPicked.isNotEmpty
        : fetchState.canDownload;
    final downloadLabel = isPlaylist
        ? (playlistPicked.isEmpty
              ? 'Pick items'
              : playlistPicked.length == 1
              ? 'Download 1 item'
              : 'Download ${playlistPicked.length} items')
        : switch (fetchState.mode) {
            DownloadMode.subtitlesOnly =>
              fetchState.subLangs.isEmpty
                  ? 'Pick a language'
                  : 'Download subtitles',
            _ => [
              fetchState.trim == null ? 'Download' : 'Download clip',
              ?formatBytes(
                fetchState.selected?.bytes == null
                    ? null
                    : (fetchState.selected!.bytes! * fetchState.keptFraction)
                          .round(),
              ),
            ].join(' · '),
          };

    return Column(
      key: const ValueKey('ready'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PopThumb(
              seed: info.url,
              url: info.thumbnail,
              audio: activeMode == DownloadMode.audioOnly,
              size: 64,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      info.site,
                      if (isPlaylist)
                        '${info.entries.length} items'
                      else if (info.duration != null)
                        clockLabel(info.duration!),
                    ].whereType<String>().join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: expanded ? 'Fewer options' : 'More options',
              onPressed: onToggleExpand,
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.tune_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        PopSegmented<DownloadMode>(
          values: modes,
          labels: [for (final m in modes) modeLabels[m]!],
          selected: activeMode,
          onChanged: (m) => onModeChanged?.call(m),
        ),
        if (activeMode != DownloadMode.subtitlesOnly &&
            activeMode != DownloadMode.audioOnly &&
            options.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final (i, opt) in (expanded ? options : compactOptions)
                  .indexed)
                ChoiceChip(
                  label: Text(
                    opt.bytes == null
                        ? opt.label
                        : '${opt.label} · ${formatBytes(opt.bytes)}',
                  ),
                  selected: i == selectedIdx,
                  onSelected: (_) {
                    Haptics.selection();
                    onOptionChanged?.call(i);
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onToggleExpand,
            icon: Icon(
              expanded
                  ? Icons.unfold_less_rounded
                  : Icons.unfold_more_rounded,
              size: 18,
            ),
            label: Text(
              expanded
                  ? 'Less options'
                  : (isPlaylist
                        ? 'More options · Pick items'
                        : 'More options · Trim & Subtitles'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (m3.motion.reduced(context))
          (!expanded
              ? const SizedBox.shrink()
              : isPlaylist
              ? _buildPlaylistExpanded(context, info)
              : _buildSingleExpanded(context, info, activeMode))
        else
          AnimatedSize(
            duration: m3.motion.defaultSpatialDuration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !expanded
                ? const SizedBox(width: double.infinity)
                : isPlaylist
                ? _buildPlaylistExpanded(context, info)
                : _buildSingleExpanded(context, info, activeMode),
          ),
        if (showBubblePrompt) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            decoration: BoxDecoration(
              color: cs.secondaryContainer.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.bubble_chart_rounded,
                  size: 18,
                  color: cs.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Float progress bubble over apps',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSecondaryContainer,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onEnableBubble,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: const Text(
                    'Turn on',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDismissBubblePrompt,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: PopButton(
                label: downloadLabel,
                icon: Icons.download_rounded,
                height: 52,
                busy: busy,
                onPressed: canPressDownload ? onDownload : null,
              ),
            ),
            const SizedBox(width: 8),
            PopIconButton(
              icon: Icons.open_in_new_rounded,
              tooltip: 'Open in Grab',
              size: 52,
              onPressed: onOpenInGrab,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSingleExpanded(
    BuildContext context,
    MediaInfo info,
    DownloadMode activeMode,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        if (activeMode != DownloadMode.subtitlesOnly &&
            info.duration != null &&
            info.duration! >= 2) ...[
          ClipPreview(
            info: info,
            trim: fetchState.trim,
            onTrim: (s, e) => onTrimChanged?.call(s, e),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.content_cut_rounded),
            title: const Text(
              'Save only a part',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              fetchState.trim == null
                  ? 'Pick the part on the video above'
                  : 'Keeping ${clockLabel(fetchState.trim!.start)} to ${clockLabel(fetchState.trim!.end)}',
            ),
            value: fetchState.trim != null,
            onChanged: (on) {
              Haptics.selection();
              onTrimToggle?.call(on);
            },
          ),
        ],
        if (activeMode != DownloadMode.audioOnly) ...[
          if (info.subtitles.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'No subtitles for this link.',
                style: TextStyle(color: context.cs.onSurfaceVariant),
              ),
            )
          else ...[
            const PopSection('Subtitles'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in info.subtitles)
                  FilterChip(
                    label: Text(t.auto ? '${t.name} · auto' : t.name),
                    selected: fetchState.subLangs.contains(t.lang),
                    onSelected: (_) {
                      Haptics.selection();
                      onToggleLang?.call(t.lang);
                    },
                  ),
              ],
            ),
            if (activeMode != DownloadMode.subtitlesOnly &&
                fetchState.subLangs.isNotEmpty)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Put subtitles inside the video',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Off: saved next to it as .srt files'),
                value: fetchState.embedSubs,
                onChanged: onEmbedSubsChanged,
              ),
          ],
        ],
      ],
    );
  }

  Widget _buildPlaylistExpanded(BuildContext context, MediaInfo info) {
    final cs = context.cs;
    final all = playlistPicked.length == info.entries.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: PopSection(
                '${playlistPicked.length} of ${info.entries.length} selected',
              ),
            ),
            TextButton(
              onPressed: onTogglePlaylistAll,
              child: Text(all ? 'Select none' : 'Select all'),
            ),
          ],
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: info.entries.length,
            itemBuilder: (context, i) {
              final e = info.entries[i];
              final picked = playlistPicked.contains(i);
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: picked,
                activeColor: cs.primary,
                onChanged: (_) => onTogglePlaylistItem?.call(i),
                title: Text(
                  e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQueued(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final info = fetchState.info.value;
    final still = m3.motion.reduced(context);

    final badge = ExpressiveShapeContainer(
      polygon: ExpressivePolygon.cookie9,
      size: 74,
      color: cs.primary,
      child: Icon(Icons.check_rounded, size: 38, color: cs.onPrimary),
    );

    return Column(
      key: const ValueKey('queued'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        if (still)
          badge
        else
          badge.animate().scale(
            begin: const Offset(0.6, 0.6),
            end: const Offset(1, 1),
            duration: 320.ms,
            curve: Curves.elasticOut,
          ),
        const SizedBox(height: 14),
        Text(
          queuedCount > 1 ? 'Queued $queuedCount items!' : 'Queued!',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          info?.title ?? 'Downloading in the background…',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: onWatchProgress,
              child: const Text('Watch progress'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onOpenInGrab,
              child: const Text('Open in Grab'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgress(BuildContext context) {
    final cs = context.cs;
    final job = activeJob;
    final info = fetchState.info.value;
    final title = job?.title ?? info?.title ?? 'Downloading…';
    final status = job?.status ?? JobStatus.queued;
    final isDone = status == JobStatus.done;
    final isFailed = status == JobStatus.failed || status == JobStatus.canceled;
    final isRunning = status == JobStatus.running;
    final isPaused = status == JobStatus.paused;
    final pct = (job?.progress ?? 0).clamp(0, 100);

    final label = switch (status) {
      JobStatus.done => 'Saved!',
      JobStatus.failed => job?.error ?? 'Download failed',
      JobStatus.canceled => 'Canceled',
      JobStatus.paused => 'Paused at ${pct.toStringAsFixed(0)}%',
      JobStatus.waiting => 'Waiting for connection…',
      JobStatus.queued => 'Waiting in queue…',
      JobStatus.running => [
        pct <= 0 ? 'Starting…' : '${pct.toStringAsFixed(0)}%',
        ?activeSpeed,
        if (job?.eta != null && job!.eta! > 0) '${job.eta}s left',
      ].join(' · '),
    };

    return Column(
      key: const ValueKey('progress'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ExpressiveShapeContainer(
              polygon: isDone
                  ? ExpressivePolygon.cookie9
                  : ExpressivePolygon.squircle,
              size: 46,
              color: isFailed ? cs.errorContainer : cs.primaryContainer,
              child: Icon(
                isDone
                    ? Icons.check_rounded
                    : isFailed
                    ? Icons.error_outline_rounded
                    : Icons.download_rounded,
                color: isFailed ? cs.onErrorContainer : cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isFailed ? cs.error : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (!isDone && !isFailed && onPauseResumeJob != null)
              PopIconButton(
                icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                tooltip: isPaused ? 'Resume' : 'Pause',
                size: 40,
                onPressed: onPauseResumeJob,
              ),
            if (!isDone && !isFailed && onCancelJob != null) ...[
              const SizedBox(width: 6),
              PopIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Cancel',
                size: 40,
                onPressed: onCancelJob,
              ),
            ],
          ],
        ),
        if (!isDone && !isFailed) ...[
          const SizedBox(height: 12),
          ExpressiveWavyProgressBar(
            value: status == JobStatus.queued && pct == 0 ? null : pct / 100,
            wavy: isRunning,
            active: isRunning || status == JobStatus.queued,
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: PopButton(
                label: 'Open in Grab',
                icon: Icons.open_in_new_rounded,
                style: PopButtonStyle.tonal,
                height: 46,
                onPressed: onOpenInGrab,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PopButton(
                label: 'Done',
                icon: Icons.check_rounded,
                height: 46,
                onPressed: onDismiss,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
