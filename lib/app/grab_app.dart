import 'dart:async';
import 'dart:io';

import 'package:confetti/confetti.dart';
import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:toastification/toastification.dart';

import '../core/theme/pop_theme.dart';
import '../core/utils/links.dart';
import '../core/audio/audio_playback.dart';
import '../core/widgets/app_scale.dart';
import '../core/widgets/dock_inset.dart';
import '../core/widgets/clipboard_offer.dart';
import '../core/widgets/expressive_app_bar.dart';
import '../features/library/audio_player_screen.dart';
import '../core/widgets/pop_widgets.dart';
import '../core/widgets/toasts.dart';
import '../data/db/app_database.dart';
import '../data/settings/app_settings.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/welcome/welcome_screen.dart';
import 'providers.dart';
import '../core/utils/haptics.dart';

class GrabApp extends ConsumerWidget {
  const GrabApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final dynamicSeed = ref.watch(dynamicColorProvider).value;
    Haptics.enabled = settings.hapticsEnabled;

    // AppScale sits above everything (toasts included) so the whole app scales together.
    return MediaQuery.fromView(
      view: View.of(context),
      child: AppScale(
        fontScale: settings.fontScale,
        child: ToastificationWrapper(
          child: MaterialApp(
            title: 'Grab',
            debugShowCheckedModeBanner: false,
            scrollBehavior: const ExpressiveScrollBehavior(),
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
            themeAnimationDuration: settings.motionPreset == M3MotionPreset.off
                ? Duration.zero
                : const Duration(milliseconds: 260),
            themeAnimationCurve: Curves.easeOutCubic,
            builder: (context, child) {
              final theme = Theme.of(context);
              syncToastScheme(theme.colorScheme);
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
            home: const _FirstRun(),
          ),
        ),
      ),
    );
  }
}

/// Shows the welcome pages once, then the app.
class _FirstRun extends ConsumerStatefulWidget {
  const _FirstRun();

  @override
  ConsumerState<_FirstRun> createState() => _FirstRunState();
}

class _FirstRunState extends ConsumerState<_FirstRun> {
  late var _seen = WelcomeScreen.seen(ref.read(sharedPrefsProvider));

  @override
  Widget build(BuildContext context) {
    final m3 = context.m3;
    return AnimatedSwitcher(
      duration: m3.motion.resolve(context, m3.motion.defaultEffectsDuration),
      child: _seen
          ? const _Shell()
          : WelcomeScreen(
              onDone: () {
                ref
                    .read(sharedPrefsProvider)
                    .setBool(WelcomeScreen.seenKey, true);
                setState(() => _seen = true);
              },
            ),
    );
  }
}

/// Tabs, plus app-wide moments: share-into-app, clipboard offer, and the "done" celebration.
class _Shell extends ConsumerStatefulWidget {
  const _Shell();

  @override
  ConsumerState<_Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<_Shell> with WidgetsBindingObserver {
  final _home = GlobalKey<HomeScreenState>();
  final _confetti = ConfettiController(
    duration: const Duration(milliseconds: 700),
  );
  StreamSubscription<List<SharedMediaFile>>? _shares;
  var _tab = 0;
  String? _lastOffered;
  ({String link, String platform})? _offer;
  Timer? _offerTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A link shared to Grab while it was closed, then any shared while it is open.
    if (Platform.isAndroid) {
      ReceiveSharingIntent.instance.getInitialMedia().then(_onShared);
      _shares = ReceiveSharingIntent.instance.getMediaStream().listen(
        _onShared,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerClipboard());
    // Quick Settings tile: open Grab and fetch whatever link is copied.
    _launch.setMethodCallHandler((call) async {
      if (call.method == 'action') _onLaunchAction(call.arguments as String?);
    });
    _launch
        .invokeMethod<String>('takeAction')
        .then(_onLaunchAction, onError: (_) {});
  }

  static const _launch = MethodChannel('grab/launch');

  void _refreshDb() {
    final db = ref.read(databaseProvider);
    db.notifyUpdates({TableUpdate.onTable(db.downloadJobs)});
  }

  void _onLaunchAction(String? action) {
    if (action == null) return;
    if (action == 'openDownloads') {
      _refreshDb();
      if (mounted) setState(() => _tab = 1);
      return;
    }
    if (action.startsWith('fetch:')) {
      final link = extractLink(action.substring(6)) ?? action.substring(6).trim();
      if (link.isEmpty || !mounted) return;
      _lastOffered = link;
      _dismissOffer();
      setState(() => _tab = 0);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _home.currentState?.fetchLink(link),
      );
      return;
    }
    if (action != 'grabClipboard') return;
    // The clipboard is readable once the window has focus.
    Future.delayed(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final link = extractLink(data?.text);
      if (!mounted) return;
      if (link == null) {
        popToast(
          'No link copied',
          icon: Icons.link_off_rounded,
          detail: 'Copy a video link, then tap the Grab tile again.',
          error: true,
        );
        return;
      }
      _lastOffered = link;
      _dismissOffer();
      setState(() => _tab = 0);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _home.currentState?.fetchLink(link),
      );
    });
  }

  Future<void> _pasteAndGrab() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final link = extractLink(data?.text);
    if (!mounted) return;
    if (link == null) {
      popToast(
        'No link in clipboard',
        icon: Icons.link_off_rounded,
        detail: 'Copy a video link, then tap the orb to grab.',
        error: true,
        context: context,
      );
      return;
    }
    _lastOffered = link;
    _dismissOffer();
    setState(() => _tab = 0);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _home.currentState?.fetchLink(link),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shares?.cancel();
    _offerTimer?.cancel();
    _confetti.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android only lets the app read the clipboard once it has focus, so wait a moment.
    if (state == AppLifecycleState.resumed) {
      _refreshDb();
      Future.delayed(const Duration(milliseconds: 400), _offerClipboard);
    }
  }

  void _onShared(List<SharedMediaFile> items) {
    if (items.isEmpty) return;
    final link = items
        .map((f) => extractLink(f.path) ?? extractLink(f.message))
        .nonNulls
        .firstOrNull;
    ReceiveSharingIntent.instance.reset();
    if (link == null) {
      popToast(
        'No link in what was shared',
        icon: Icons.link_off_rounded,
        error: true,
      );
      return;
    }
    _lastOffered = link;
    setState(() => _tab = 0);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _home.currentState?.fetchLink(link),
    );
  }

  /// If the clipboard holds a link from a known platform, offer to fetch it once.
  Future<void> _offerClipboard() async {
    if (!mounted) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final link = extractLink(data?.text);
    final platform = platformOf(link);
    if (link == null || platform == null || link == _lastOffered || !mounted) {
      return;
    }
    // Already offered, fetched or downloaded (even with different share
    // tracking, even before a restart)? Then stay quiet.
    final key = linkKey(link);
    final jobs = ref.read(jobsProvider).value ?? const <DownloadJob>[];
    if (_seenLinks.contains(key) || jobs.any((j) => linkKey(j.url) == key)) {
      _lastOffered = link;
      return;
    }
    _remember(link);
    _lastOffered = link;
    Haptics.soft();
    setState(() => _offer = (link: link, platform: platform));
    _offerTimer?.cancel();
    _offerTimer = Timer(const Duration(seconds: 25), _dismissOffer);
  }

  static const _seenKey = 'seenLinks';

  List<String> get _seenLinks =>
      ref.read(sharedPrefsProvider).getStringList(_seenKey) ?? const [];

  /// Remembers a link as handled, so the clipboard card never offers it again.
  void _remember(String link) {
    final key = linkKey(link);
    final seen = [..._seenLinks.where((k) => k != key), key];
    ref
        .read(sharedPrefsProvider)
        .setStringList(
          _seenKey,
          seen.length > 300 ? seen.sublist(seen.length - 300) : seen,
        );
  }

  void _dismissOffer() {
    _offerTimer?.cancel();
    if (mounted && _offer != null) setState(() => _offer = null);
  }

  void _grabOffer() {
    final o = _offer;
    if (o == null) return;
    Haptics.medium();
    setState(() => _tab = 0);
    _home.currentState?.fetchLink(o.link);
  }

  /// Celebrate jobs that just finished; warn about ones that just failed.
  void _onJobsChanged(List<DownloadJob>? before, List<DownloadJob> after) {
    if (before == null) return;
    final was = {for (final j in before) j.id: j.status};
    final m3 = context.m3;
    for (final j in after) {
      final prev = was[j.id];
      if (prev == null || prev == j.status) continue;
      if (j.status == JobStatus.done) {
        Haptics.success();
        if (m3.confettiEnabled && !m3.motion.reduced(context)) {
          _confetti.play();
        }
        popToast(
          'Saved',
          icon: Icons.check_circle_rounded,
          detail: j.title,
          context: context,
        );
      } else if (j.status == JobStatus.failed) {
        Haptics.error();
        popToast(
          'Download failed',
          icon: Icons.error_rounded,
          error: true,
          detail: j.title,
          context: context,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pendingLinkProvider, (_, link) {
      if (link == null) return;
      ref.read(pendingLinkProvider.notifier).set(null);
      _lastOffered = link;
      setState(() => _tab = 0);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _home.currentState?.fetchLink(link),
      );
    });
    ref.listen(jobsProvider, (prev, next) {
      final after = next.value;
      if (after != null) _onJobsChanged(prev?.value, after);
    });
    final active = ref.watch(activeCountProvider);
    final jobs = ref.watch(jobsProvider).value ?? const <DownloadJob>[];
    final runningJobs = jobs
        .where((j) => j.status == JobStatus.running)
        .toList();
    final double? aggregateProgress = runningJobs.isEmpty
        ? null
        : (runningJobs.fold<double>(
                    0,
                    (s, j) => s + j.progress.clamp(0, 100),
                  ) /
                  (runningJobs.length * 100))
              .clamp(0.0, 1.0);
    final m3 = context.m3;
    final cs = context.cs;
    final showMiniBar = m3.navStyle != M3NavStyle.floatingPill;
    final overlayBottom = switch (m3.navStyle) {
      M3NavStyle.floatingPill => 92.0,
      M3NavStyle.dockedBar => 84.0,
      M3NavStyle.minimalDock => 84.0,
    };

    return Stack(
      children: [
        Scaffold(
          extendBody: m3.navStyle != M3NavStyle.dockedBar,
          body: ValueListenableBuilder(
            valueListenable: AudioPlayback.current,
            builder: (context, playing, child) => DockInset(
              extra: showMiniBar && playing != null ? 64 : 0,
              child: child!,
            ),
            child: IndexedStack(
              index: _tab,
              children: [
                for (final (i, page) in <Widget>[
                  HomeScreen(
                    key: _home,
                    onQueued: () => setState(() => _tab = 1),
                    onFetch: (link) {
                      _remember(link);
                      _dismissOffer();
                    },
                  ),
                  const DownloadsScreen(),
                  const LibraryScreen(),
                  const SettingsScreen(),
                ].indexed)
                  TickerMode(enabled: i == _tab, child: page),
              ],
            ),
          ),
          bottomNavigationBar: ValueListenableBuilder(
            valueListenable: AudioPlayback.current,
            builder: (context, playing, _) => StreamBuilder<bool>(
              stream: AudioPlayback.player.playingStream,
              initialData: AudioPlayback.player.playing,
              builder: (context, snap) => PopTabBar(
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
                tabs: [
                  const PopTab(
                    Icons.home_outlined,
                    'Home',
                    activeIcon: Icons.home_rounded,
                  ),
                  PopTab(
                    Icons.download_outlined,
                    'Downloads',
                    activeIcon: Icons.download_rounded,
                    badge: active,
                  ),
                  const PopTab(
                    Icons.video_library_outlined,
                    'Library',
                    activeIcon: Icons.video_library_rounded,
                  ),
                  const PopTab(
                    Icons.tune_outlined,
                    'Settings',
                    activeIcon: Icons.tune_rounded,
                  ),
                ],
                orb: PopDockOrb(
                  playingTitle: playing?.title,
                  playingSeed: playing?.jobId,
                  playingThumbUrl: playing?.thumbnail,
                  isPlaying: snap.data ?? false,
                  playingPageBuilder: playing == null
                      ? null
                      : (_) => AudioPlayerScreen(item: playing),
                  onTogglePlay: AudioPlayback.toggle,
                  activeDownloads: active,
                  downloadProgress: aggregateProgress,
                  onOpenDownloads: () => setState(() => _tab = 1),
                  onPasteGrab: _pasteAndGrab,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: MediaQuery.paddingOf(context).bottom + overlayBottom,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSwitcher(
                duration: m3.motion.resolve(
                  context,
                  m3.motion.defaultSpatialDuration,
                ),
                switchInCurve: Curves.linear,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: CurvedAnimation(
                    parent: a,
                    curve: m3.motion.effectsCurve,
                  ),
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.35),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: a,
                        curve: m3.motion.defaultSpatialCurve,
                      ),
                    ),
                    child: child,
                  ),
                ),
                child: _offer == null
                    ? const SizedBox.shrink()
                    : ClipboardOffer(
                        key: ValueKey(_offer!.link),
                        platform: _offer!.platform,
                        link: _offer!.link,
                        onGrab: _grabOffer,
                        onDismiss: _dismissOffer,
                      ),
              ),
              if (showMiniBar) ...[
                const SizedBox(height: 8),
                const MiniPlayer(),
              ],
            ],
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            numberOfParticles: 28,
            maxBlastForce: 28,
            minBlastForce: 10,
            gravity: 0.25,
            emissionFrequency: 0.0,
            colors: [
              cs.primary,
              cs.secondary,
              cs.tertiary,
              cs.primaryContainer,
            ],
          ),
        ),
      ],
    );
  }
}
