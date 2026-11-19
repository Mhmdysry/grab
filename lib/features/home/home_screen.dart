import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/pop_theme.dart';
import '../../core/utils/links.dart';
import '../../core/utils/permissions.dart';
import '../../core/widgets/dock_inset.dart';
import '../../core/widgets/expressive_app_bar.dart';
import '../../core/widgets/expressive_shapes.dart';
import '../../core/widgets/pop_widgets.dart';
import '../../core/widgets/toasts.dart';
import '../../data/db/app_database.dart';
import '../../data/engine/media_info.dart';
import '../../data/settings/app_settings.dart';
import '../downloads/downloads_screen.dart';
import 'fetch_controller.dart';
import 'format_sheet.dart';
import 'playlist_sheet.dart';
import '../../core/utils/haptics.dart';

/// Filter tabs for the Unified Downloads Hub on [HomeScreen].
enum HomeDownloadsFilter { all, active, completed }

/// Home: paste or share a link, fetch it, choose a format (or Instant Grab),
/// and manage all active & completed downloads right on Home.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.onQueued, this.onFetch});

  /// Called after a download is queued.
  final VoidCallback? onQueued;

  /// Called whenever a link starts fetching, however it got here.
  final ValueChanged<String>? onFetch;

  @override
  ConsumerState<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends ConsumerState<HomeScreen> {
  final _url = TextEditingController();
  final _downloadsHubKey = GlobalKey();
  HomeDownloadsFilter _filter = HomeDownloadsFilter.all;
  String? _highlightedJobId;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    _url.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _url.dispose();
    super.dispose();
  }

  /// Fills the field with [link] and fetches it. Used by paste, share and the clipboard offer.
  void fetchLink(String link) {
    _url.text = link;
    _fetch();
  }

  /// Smoothly scrolls down to the Unified Downloads Hub and optionally highlights [highlightJobId].
  void scrollToDownloads({String? highlightJobId}) {
    if (!mounted) return;
    if (highlightJobId != null) {
      _highlightTimer?.cancel();
      setState(() {
        _highlightedJobId = highlightJobId;
        if (_filter == HomeDownloadsFilter.completed) {
          _filter = HomeDownloadsFilter.all;
        }
      });
      _highlightTimer = Timer(const Duration(milliseconds: 1800), () {
        if (mounted) setState(() => _highlightedJobId = null);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _downloadsHubKey.currentContext;
      if (ctx == null) return;
      final m3 = context.m3;
      Scrollable.ensureVisible(
        ctx,
        duration: m3.motion.resolve(context, m3.motion.defaultSpatialDuration),
        curve: m3.motion.defaultSpatialCurve,
        alignment: 0.12,
      );
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final link = extractLink(data?.text) ?? data?.text?.trim();
    if (link == null || link.isEmpty) return;
    fetchLink(link);
  }

  /// Format sheet for one item; the picker for a playlist or profile.
  Future<void> _choose(MediaInfo info) async {
    final queued = info.isPlaylist && info.entries.isNotEmpty
        ? await showPlaylistSheet(context, info)
        : await showFormatSheet(context);
    if (queued) {
      final latestId = ref.read(jobsProvider).value?.firstOrNull?.id;
      scrollToDownloads(highlightJobId: latestId);
      widget.onQueued?.call();
    }
  }

  Future<void> _instantDownload(MediaInfo info) async {
    final ok = await ensureDownloadPermissions(
      context,
      ref.read(sharedPrefsProvider),
    );
    if (!mounted) return;
    if (!ok) {
      popToast(
        'Grab needs storage access to save files',
        error: true,
        context: context,
      );
      return;
    }
    final jobId = await ref.read(fetchControllerProvider.notifier).download();
    if (!mounted) return;
    if (jobId != null) {
      Haptics.success();
      popToast(
        'Instant Grab queued!',
        icon: Icons.bolt_rounded,
        detail: info.title,
        context: context,
      );
      scrollToDownloads(highlightJobId: jobId);
      widget.onQueued?.call();
    } else {
      await _choose(info);
    }
  }

  void _cycleDefaultMode(AppSettings s) {
    Haptics.selection();
    final next = switch (s.defaultMode) {
      DownloadMode.video => DownloadMode.audioOnly,
      DownloadMode.audioOnly => DownloadMode.videoAndAudio,
      _ => DownloadMode.video,
    };
    ref
        .read(settingsProvider.notifier)
        .update((x) => x.copyWith(defaultMode: next));
  }

  Future<void> _pickQuickQuality(AppSettings s) async {
    Haptics.selection();
    if (s.defaultMode == DownloadMode.audioOnly) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              const Text(
                'Default audio format',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              for (final f in AppSettings.audioFormats)
                PopOptionTile(
                  label: f.toUpperCase(),
                  selected: f == s.audioFormat,
                  onTap: () => Navigator.of(context).pop(f),
                ),
            ],
          ),
        ),
      );
      if (picked != null) {
        await ref
            .read(settingsProvider.notifier)
            .update((x) => x.copyWith(audioFormat: picked));
      }
      return;
    }
    final picked = await showModalBottomSheet<(int?,)>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            const Text(
              'Default quality',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            for (final h in AppSettings.heights)
              PopOptionTile(
                label: h == null ? 'Best available' : '${h}p or lower',
                selected: h == s.maxHeight,
                onTap: () => Navigator.of(context).pop((h,)),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      await ref
          .read(settingsProvider.notifier)
          .update((x) => x.copyWith(maxHeight: () => picked.$1));
    }
  }

  void _fetch() {
    FocusScope.of(context).unfocus();
    final link = extractLink(_url.text) ?? _url.text.trim();
    if (link.isEmpty) return;
    if (link != _url.text) _url.text = link;
    widget.onFetch?.call(link);
    ref.read(fetchControllerProvider.notifier).fetch(link);
  }

  Future<void> _pauseAllActive(List<DownloadJob> activeJobs) async {
    Haptics.medium();
    final repo = ref.read(downloadRepositoryProvider);
    for (final j in activeJobs) {
      if (j.status == JobStatus.running ||
          j.status == JobStatus.queued ||
          j.status == JobStatus.waiting) {
        await repo.pause(j.id);
      }
    }
  }

  Future<void> _resumeAllPaused(List<DownloadJob> pausedJobs) async {
    Haptics.medium();
    final repo = ref.read(downloadRepositoryProvider);
    for (final j in pausedJobs) {
      await repo.unpause(j.id);
    }
  }

  Future<void> _retryAllFailed(List<DownloadJob> failedJobs) async {
    Haptics.medium();
    final repo = ref.read(downloadRepositoryProvider);
    for (final j in failedJobs) {
      await repo.retry(j.id);
    }
  }

  Future<void> _clearFinished(List<DownloadJob> historyJobs) async {
    Haptics.medium();
    final repo = ref.read(downloadRepositoryProvider);
    for (final j in historyJobs) {
      await repo.remove(j.id);
    }
    if (!mounted) return;
    popToast(
      'Cleared download history',
      icon: Icons.cleaning_services_rounded,
      detail: 'Saved files in Library are untouched.',
      context: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Open the format sheet (or Instant Grab) as soon as a fetch succeeds.
    ref.listen(fetchControllerProvider.select((s) => s.info), (
      prev,
      next,
    ) async {
      if (prev is AsyncLoading && next is AsyncData && next.value != null) {
        Haptics.light();
        final info = next.value!;
        final settings = ref.read(settingsProvider);
        final isPlaylist = info.isPlaylist && info.entries.isNotEmpty;
        if (settings.instantGrab && !isPlaylist) {
          await _instantDownload(info);
        } else {
          await _choose(info);
        }
      }
    });

    final s = ref.watch(fetchControllerProvider);
    final settings = ref.watch(settingsProvider);
    final version = ref.watch(engineVersionProvider);
    final allJobs = ref.watch(jobsProvider).value ?? const <DownloadJob>[];
    final activeJobs = allJobs
        .where((j) => isActiveJobStatus(j.status))
        .toList();
    final historyJobs = allJobs
        .where((j) => !isActiveJobStatus(j.status))
        .toList();
    final completedJobs = historyJobs
        .where((j) => j.status == JobStatus.done)
        .toList();
    final runningOrQueued = activeJobs
        .where(
          (j) =>
              j.status == JobStatus.running ||
              j.status == JobStatus.queued ||
              j.status == JobStatus.waiting,
        )
        .toList();
    final pausedJobs = activeJobs
        .where((j) => j.status == JobStatus.paused)
        .toList();
    final failedJobs = historyJobs
        .where(
          (j) => j.status == JobStatus.failed || j.status == JobStatus.canceled,
        )
        .toList();

    final visibleJobs = switch (_filter) {
      HomeDownloadsFilter.all => [...activeJobs, ...historyJobs],
      HomeDownloadsFilter.active => activeJobs,
      HomeDownloadsFilter.completed => completedJobs,
    };

    final detected = platformOf(extractLink(_url.text) ?? _url.text);
    final still = Pop.reduceMotion(context);
    final cs = context.cs;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(engineVersionProvider);
          final db = ref.read(databaseProvider);
          db.notifyUpdates({TableUpdate.onTable(db.downloadJobs)});
          await ref.read(downloadRepositoryProvider).resume();
        },
        child: CustomScrollView(
          slivers: [
            ExpressiveSliverHeader(
              title: 'Grab',
              leading: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Center(
                  child: ExpressiveShapeContainer(
                    polygon: ExpressivePolygon.cookie12,
                    size: 36,
                    color: cs.primaryContainer,
                    child: Icon(
                      Icons.download_rounded,
                      size: 20,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: PopIconButton(
                    icon: Icons.content_paste_rounded,
                    tooltip: 'Paste link and fetch',
                    onPressed: _paste,
                  ),
                ),
              ],
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                24,
                8,
                24,
                DockInset.listBottom(context),
              ),
              sliver: SliverList.list(
                children: [
                  if (still)
                    const Text(
                      'Paste a link.\nGet the file.',
                      style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        height: 1.02,
                        letterSpacing: -1.1,
                      ),
                    )
                  else
                    const Text(
                          'Paste a link.\nGet the file.',
                          style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            height: 1.02,
                            letterSpacing: -1.1,
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
                  const SizedBox(height: 22),
                  _LinkField(
                    controller: _url,
                    busy: s.info.isLoading,
                    onFetch: _fetch,
                  ),
                  const SizedBox(height: 12),
                  InstantGrabBar(
                    settings: settings,
                    onToggleInstant: () {
                      Haptics.selection();
                      ref
                          .read(settingsProvider.notifier)
                          .update(
                            (x) => x.copyWith(instantGrab: !x.instantGrab),
                          );
                    },
                    onCycleMode: () => _cycleDefaultMode(settings),
                    onPickQuality: () => _pickQuickQuality(settings),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in platforms)
                        _PlatformChip(label: p, active: p == detected),
                      const _PlatformChip(label: '+ 1,800 more', active: false),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    version.when(
                      data: (v) => 'yt-dlp ${v ?? ''}',
                      loading: () => 'Starting engine…',
                      error: (e, _) => 'Engine failed to start',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  ...switch (s.info) {
                    AsyncLoading() => [
                      const SizedBox(height: 24),
                      const _FetchingCard(),
                    ],
                    AsyncError(:final error) => [
                      const SizedBox(height: 24),
                      _ErrorCard(message: '$error', onRetry: _fetch),
                    ],
                    AsyncData(:final value?) => [
                      const SizedBox(height: 24),
                      _ReadyCard(info: value, onOpen: () => _choose(value)),
                    ],
                    _ => const <Widget>[],
                  },
                  if (allJobs.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Row(
                      key: _downloadsHubKey,
                      children: [
                        const Expanded(child: PopSection('Downloads')),
                        if (activeJobs.isNotEmpty) ...[
                          PopTag(
                            '${activeJobs.length} active',
                            color: cs.primaryContainer,
                            foreground: cs.onPrimaryContainer,
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (historyJobs.isNotEmpty)
                          TextButton.icon(
                            onPressed: () => _clearFinished(historyJobs),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(
                              Icons.cleaning_services_rounded,
                              size: 16,
                            ),
                            label: const Text(
                              'Clear finished',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ExpressivePillChip(
                          label: 'All (${allJobs.length})',
                          selected: _filter == HomeDownloadsFilter.all,
                          onTap: () =>
                              setState(() => _filter = HomeDownloadsFilter.all),
                        ),
                        ExpressivePillChip(
                          label: 'Active (${activeJobs.length})',
                          selected: _filter == HomeDownloadsFilter.active,
                          onTap: () => setState(
                            () => _filter = HomeDownloadsFilter.active,
                          ),
                        ),
                        ExpressivePillChip(
                          label: 'Completed (${completedJobs.length})',
                          selected: _filter == HomeDownloadsFilter.completed,
                          onTap: () => setState(
                            () => _filter = HomeDownloadsFilter.completed,
                          ),
                        ),
                      ],
                    ),
                    if (runningOrQueued.length > 1 ||
                        pausedJobs.isNotEmpty ||
                        failedJobs.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (runningOrQueued.length > 1)
                            ExpressivePillChip(
                              icon: Icons.pause_rounded,
                              label: 'Pause all',
                              onTap: () => _pauseAllActive(runningOrQueued),
                            ),
                          if (pausedJobs.isNotEmpty)
                            ExpressivePillChip(
                              icon: Icons.play_arrow_rounded,
                              label: 'Resume all (${pausedJobs.length})',
                              onTap: () => _resumeAllPaused(pausedJobs),
                            ),
                          if (failedJobs.isNotEmpty)
                            ExpressivePillChip(
                              icon: Icons.refresh_rounded,
                              label: 'Retry failed (${failedJobs.length})',
                              onTap: () => _retryAllFailed(failedJobs),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    if (visibleJobs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _filter == HomeDownloadsFilter.active
                              ? 'No active downloads right now.'
                              : 'No completed downloads yet.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      )
                    else
                      for (final (i, j) in visibleJobs.indexed)
                        DownloadJobCard(
                          key: ValueKey('home-job-${j.id}'),
                          job: j,
                          index: i,
                          highlighted: j.id == _highlightedJobId,
                        ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill text field with animated focus outline and shape-morphing Fetch button.
class _LinkField extends StatefulWidget {
  const _LinkField({
    required this.controller,
    required this.busy,
    required this.onFetch,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onFetch;

  @override
  State<_LinkField> createState() => _LinkFieldState();
}

class _LinkFieldState extends State<_LinkField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final radius = m3.shapeStyle == M3ShapeStyle.crisp ? 18.0 : 999.0;
    return AnimatedContainer(
      duration: m3.motion.resolve(context, m3.motion.fastEffectsDuration),
      padding: const EdgeInsets.fromLTRB(20, 6, 6, 6),
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(
            color: _focus.hasFocus ? cs.primary : Colors.transparent,
            width: 2,
          ),
        ),
        color: cs.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              focusNode: _focus,
              controller: widget.controller,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => widget.onFetch(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              decoration: const InputDecoration(
                hintText: 'Paste a video link',
                filled: false,
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (widget.controller.text.isNotEmpty && !widget.busy)
            IconButton(
              tooltip: 'Clear',
              onPressed: widget.controller.clear,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          PopButton(
            label: 'Fetch',
            onPressed: widget.onFetch,
            busy: widget.busy,
            expand: false,
            height: 48,
          ),
        ],
      ),
    );
  }
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    return AnimatedScale(
      scale: active ? 1.05 : 1.0,
      duration: m3.motion.resolve(context, m3.motion.defaultSpatialDuration),
      curve: m3.motion.defaultSpatialCurve,
      child: AnimatedContainer(
        duration: m3.motion.resolve(context, m3.motion.defaultSpatialDuration),
        curve: m3.motion.defaultSpatialCurve,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          color: active ? cs.primary : cs.secondaryContainer,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: active ? cs.onPrimary : cs.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

/// Placeholder while yt-dlp reads the link, featuring the M3 Expressive polygon loader.
class _FetchingCard extends StatelessWidget {
  const _FetchingCard();

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(h),
      ),
    );
    final card = Container(
      padding: EdgeInsets.all(m3.cardPad),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: m3.cardRadius,
      ),
      child: Row(
        children: [
          const ExpressiveLoadingIndicator(size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(double.infinity, 14),
                const SizedBox(height: 10),
                bar(120, 12),
                const SizedBox(height: 10),
                Text(
                  'Reading the link…',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (m3.motion.reduced(context)) return card;
    return card
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1200.ms, color: cs.surface);
  }
}

/// Shown after a fetch, in case the sheet was closed without downloading.
class _ReadyCard extends StatelessWidget {
  const _ReadyCard({required this.info, required this.onOpen});

  final MediaInfo info;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    return InkWell(
      borderRadius: m3.cardRadius,
      onTap: onOpen,
      child: Container(
        padding: EdgeInsets.all(m3.cardPad),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: m3.cardRadius,
        ),
        child: Row(
          children: [
            PopThumb(seed: info.url, url: info.thumbnail, size: 72),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    info.isPlaylist
                        ? 'Pick from ${info.entries.length} items'
                        : 'Choose format',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onPrimaryContainer),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final card = Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
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
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: cs.onErrorContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: cs.onErrorContainer),
          ),
          Row(
            children: [
              TextButton(
                onPressed: onRetry,
                child: Text(
                  'Try again',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onErrorContainer,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: message)),
                child: Text(
                  'Copy error',
                  style: TextStyle(color: cs.onErrorContainer),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (m3.motion.reduced(context)) return card;
    return card.animate().shakeX(hz: 4, amount: 4, duration: 350.ms);
  }
}

/// Quick-Download Mode Bar on Home: toggleable Instant Grab pill plus inline
/// mode and quality/format quick chips.
class InstantGrabBar extends StatelessWidget {
  const InstantGrabBar({
    super.key,
    required this.settings,
    required this.onToggleInstant,
    required this.onCycleMode,
    required this.onPickQuality,
  });

  final AppSettings settings;
  final VoidCallback onToggleInstant;
  final VoidCallback onCycleMode;
  final VoidCallback onPickQuality;

  @override
  Widget build(BuildContext context) {
    final on = settings.instantGrab;
    final audio = settings.defaultMode == DownloadMode.audioOnly;
    final modeLabel = switch (settings.defaultMode) {
      DownloadMode.video => 'Video',
      DownloadMode.videoAndAudio => 'Video + audio',
      DownloadMode.audioOnly => 'Audio',
      DownloadMode.subtitlesOnly => 'Subtitles',
    };
    final qualityLabel = audio
        ? settings.audioFormat.toUpperCase()
        : (settings.maxHeight == null ? 'Best' : '${settings.maxHeight}p');

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ExpressivePillChip(
          label: 'Instant Grab',
          icon: Icons.bolt_rounded,
          selected: on,
          onTap: onToggleInstant,
          semanticLabel: 'Instant Grab, ${on ? 'on' : 'off'}',
        ),
        ExpressivePillChip(
          icon: audio ? Icons.music_note_rounded : Icons.videocam_rounded,
          label: modeLabel,
          onTap: onCycleMode,
        ),
        ExpressivePillChip(
          icon: audio ? Icons.graphic_eq_rounded : Icons.hd_rounded,
          label: qualityLabel,
          onTap: onPickQuality,
        ),
      ],
    );
  }
}
