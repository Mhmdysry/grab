import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../core/theme/pop_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/dock_inset.dart';
import '../../core/widgets/expressive_app_bar.dart';
import '../../core/widgets/expressive_shapes.dart';
import '../../core/widgets/morph.dart';
import '../../core/widgets/pop_widgets.dart';
import '../../core/widgets/toasts.dart';
import '../../data/db/app_database.dart';
import '../../data/engine/media_info.dart';
import '../../data/repositories/download_repository.dart';
import '../detail/download_detail_screen.dart';

/// Downloads: active and waiting jobs on top, history below.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(jobsProvider);
    final cs = context.cs;
    final all = jobs.value ?? const <DownloadJob>[];
    final running = all.where((j) => j.status == JobStatus.running).length;
    final waiting = all.where((j) => j.status == JobStatus.queued).length;
    final paused = all.where((j) => j.status == JobStatus.paused).length;
    final offline = all.where((j) => j.status == JobStatus.waiting).length;
    final active = all.where((j) => _isActive(j.status)).toList();
    final history = all.where((j) => !active.contains(j)).toList();
    final summary = active.isEmpty
        ? 'Nothing running'
        : [
            '$running active',
            if (waiting > 0) '$waiting waiting',
            if (paused > 0) '$paused paused',
            if (offline > 0) '$offline need connection',
          ].join(' · ');

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          final db = ref.read(databaseProvider);
          db.notifyUpdates({TableUpdate.onTable(db.downloadJobs)});
          await ref.read(downloadRepositoryProvider).resume();
        },
        child: CustomScrollView(
          slivers: [
            ExpressiveSliverHeader(
              title: 'Downloads',
              actions: [
                if (active.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: Center(
                      child: PopTag(
                        '${active.length} active',
                        color: cs.primaryContainer,
                        foreground: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            ...jobs.when(
              loading: () => const [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: ExpressiveLoadingIndicator()),
                ),
              ],
              error: (e, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('$e')),
                ),
              ],
              data: (_) => [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    0,
                    24,
                    DockInset.listBottom(context),
                  ),
                  sliver: SliverList.list(
                    children: [
                      Text(
                        summary,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (all.isEmpty)
                        ExpressiveEmptyState(
                          icon: Icons.download_rounded,
                          polygon: ExpressivePolygon.clover4,
                          containerColor: cs.tertiaryContainer,
                          iconColor: cs.onTertiaryContainer,
                          title: 'Nothing here yet',
                          subtitle:
                              'Paste a link on Home, or share one to Grab from TikTok, YouTube or Pinterest.',
                        ),
                      for (final (i, j) in active.indexed)
                        _JobCard(key: ValueKey(j.id), job: j, index: i),
                      if (history.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const PopSection('History'),
                        for (final (i, j) in history.indexed)
                          _JobCard(
                            key: ValueKey(j.id),
                            job: j,
                            index: active.length + i,
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

bool _isActive(JobStatus s) =>
    s == JobStatus.running ||
    s == JobStatus.queued ||
    s == JobStatus.paused ||
    s == JobStatus.waiting;

class _JobCard extends ConsumerWidget {
  const _JobCard({super.key, required this.job, required this.index});

  final DownloadJob job;
  final int index;

  DownloadMode get _mode => DownloadMode.values.byName(job.mode);

  String get _what {
    final mode = _mode;
    return [
      switch (mode) {
        DownloadMode.video => 'Video',
        DownloadMode.videoAndAudio => 'Video + audio file',
        DownloadMode.audioOnly => 'Audio · ${job.audioFormat.toUpperCase()}',
        DownloadMode.subtitlesOnly => 'Subtitles · ${job.subLangs}',
      },
      if (job.maxHeight != null &&
          (mode == DownloadMode.video || mode == DownloadMode.videoAndAudio))
        '${job.maxHeight}p',
      if (job.subLangs.isNotEmpty && mode != DownloadMode.subtitlesOnly)
        'subs ${job.subLangs}',
      if (job.trimStart != null || job.trimEnd != null)
        'clip ${clockLabel(job.trimStart ?? 0)}–${job.trimEnd == null ? 'end' : clockLabel(job.trimEnd!)}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(downloadRepositoryProvider);
    final files = job.paths.isEmpty ? const <String>[] : job.paths.split('\n');
    final active = _isActive(job.status);
    final isRunning = job.status == JobStatus.running;
    final pct = job.progress.toStringAsFixed(0);
    final m3 = context.m3;
    final cs = context.cs;
    final still = m3.motion.reduced(context);

    final status = switch (job.status) {
      JobStatus.queued => 'Waiting',
      JobStatus.running when job.progress >= 100 => 'Finishing…',
      JobStatus.running => [
        job.progress <= 0 ? 'Starting…' : '${job.progress.toStringAsFixed(0)}%',
        ?ref.watch(speedsProvider).value?[job.id],
        if (job.eta != null && job.eta! > 0) '${_eta(job.eta!)} left',
      ].join(' · '),
      JobStatus.done =>
        files.isEmpty ? 'Saved' : files.map(p.basename).join('\n'),
      JobStatus.failed => job.error ?? 'Failed',
      JobStatus.canceled => 'Canceled',
      JobStatus.paused => job.progress > 0 ? 'Paused at $pct%' : 'Paused',
      JobStatus.waiting =>
        'Connection lost · trying again by itself (${job.attempts} of ${DownloadRepository.maxAutoRetries})',
    };

    final cardBg = isRunning ? cs.primaryContainer : cs.surfaceContainerLow;
    final cardFg = isRunning ? cs.onPrimaryContainer : cs.onSurface;
    final cardMuted = isRunning
        ? cs.onPrimaryContainer.withValues(alpha: 0.75)
        : cs.onSurfaceVariant;

    final card = Container(
      padding: EdgeInsets.fromLTRB(
        m3.cardPad - 2,
        m3.cardPad - 2,
        m3.cardPad - 6,
        m3.cardPad,
      ),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: m3.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PopThumb(
                seed: job.id,
                url: job.thumbnail,
                audio: _mode == DownloadMode.audioOnly,
                size: m3.thumbSize + 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        height: 1.2,
                        color: cardFg,
                      ),
                    ),
                    const SizedBox(height: 5),
                    if (job.site != null)
                      Text(
                        job.site!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: cardMuted, fontSize: 13),
                      ),
                    const SizedBox(height: 8),
                    PopTag(
                      _what,
                      color: isRunning ? cs.surfaceContainerLowest : null,
                      foreground: isRunning ? cs.onSurface : null,
                    ),
                  ],
                ),
              ),
              _StatusIcon(
                job: job,
                onCancel: () => repo.cancel(job.id),
                onRetry: () => repo.retry(job.id),
                onPause: () => repo.pause(job.id),
                onResume: () => repo.unpause(job.id),
              ),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: PopProgressBar(
                value: job.status == JobStatus.queued && job.progress == 0
                    ? null
                    : job.progress / 100,
                wavy: isRunning,
                active: isRunning || job.status == JobStatus.queued,
                color: isRunning ? cs.primary : cs.secondary,
                track: isRunning
                    ? cs.surfaceContainerLowest
                    : cs.surfaceContainerHighest,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    status,
                    maxLines: job.status == JobStatus.failed ? 3 : 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: job.status == JobStatus.failed
                          ? cs.error
                          : cardMuted,
                    ),
                  ),
                ),
                if (active && !isRunning)
                  GestureDetector(
                    onTap: () => repo.cancel(job.id),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                if (!active)
                  GestureDetector(
                    onTap: () => repo.remove(job.id),
                    child: Text(
                      'Remove',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    final inner = active
        ? card
        : Morph(
            color: cs.surfaceContainerLow,
            page: (_) => DownloadDetailScreen(jobId: job.id),
            builder: (context, open) => GestureDetector(
              onTap: open,
              behavior: HitTestBehavior.opaque,
              child: card,
            ),
          );

    final (rightLabel, rightIcon, rightBg, rightFg) = switch (job.status) {
      JobStatus.running ||
      JobStatus.queued ||
      JobStatus.waiting => (
        'Pause',
        Icons.pause_rounded,
        cs.secondaryContainer,
        cs.onSecondaryContainer,
      ),
      JobStatus.paused => (
        'Resume',
        Icons.play_arrow_rounded,
        cs.primaryContainer,
        cs.onPrimaryContainer,
      ),
      JobStatus.failed || JobStatus.canceled => (
        'Retry',
        Icons.refresh_rounded,
        cs.primaryContainer,
        cs.onPrimaryContainer,
      ),
      JobStatus.done => (
        'Details',
        Icons.open_in_new_rounded,
        cs.tertiaryContainer,
        cs.onTertiaryContainer,
      ),
    };

    final (leftLabel, leftIcon) = active
        ? ('Cancel', Icons.close_rounded)
        : ('Remove', Icons.delete_sweep_rounded);

    final tappable = Padding(
      padding: EdgeInsets.only(bottom: m3.listGap),
      child: _SwipeableJobCard(
        jobId: job.id,
        rightLabel: rightLabel,
        rightIcon: rightIcon,
        rightBg: rightBg,
        rightFg: rightFg,
        leftLabel: leftLabel,
        leftIcon: leftIcon,
        leftBg: cs.errorContainer,
        leftFg: cs.onErrorContainer,
        onSwipeRight: () {
          switch (job.status) {
            case JobStatus.running || JobStatus.queued || JobStatus.waiting:
              repo.pause(job.id);
            case JobStatus.paused:
              repo.unpause(job.id);
            case JobStatus.failed || JobStatus.canceled:
              repo.retry(job.id);
            case JobStatus.done:
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DownloadDetailScreen(jobId: job.id),
                ),
              );
          }
        },
        onSwipeLeft: () {
          if (active) {
            repo.cancel(job.id);
          } else {
            repo.remove(job.id);
            popToast(
              'Removed from history',
              icon: Icons.delete_sweep_rounded,
              context: context,
            );
          }
        },
        child: inner,
      ),
    );
    return still
        ? tappable
        : tappable
              .animate()
              .fadeIn(
                duration: m3.motion.defaultEffectsDuration,
                delay: (35 * (index % 8)).ms,
              )
              .slideY(
                begin: 0.08,
                end: 0,
                curve: m3.motion.defaultSpatialCurve,
              );
  }

  static String _eta(int s) => s >= 60 ? '${s ~/ 60}m ${s % 60}s' : '${s}s';
}

class _SwipeableJobCard extends StatefulWidget {
  const _SwipeableJobCard({
    required this.jobId,
    required this.rightLabel,
    required this.rightIcon,
    required this.rightBg,
    required this.rightFg,
    required this.leftLabel,
    required this.leftIcon,
    required this.leftBg,
    required this.leftFg,
    required this.onSwipeRight,
    required this.onSwipeLeft,
    required this.child,
  });

  final String jobId;
  final String rightLabel;
  final IconData rightIcon;
  final Color rightBg;
  final Color rightFg;
  final String leftLabel;
  final IconData leftIcon;
  final Color leftBg;
  final Color leftFg;
  final VoidCallback onSwipeRight;
  final VoidCallback onSwipeLeft;
  final Widget child;

  @override
  State<_SwipeableJobCard> createState() => _SwipeableJobCardState();
}

class _SwipeableJobCardState extends State<_SwipeableJobCard> {
  var _reached = false;

  @override
  Widget build(BuildContext context) {
    final m3 = context.m3;
    return ClipRRect(
      borderRadius: m3.cardRadius,
      child: Dismissible(
        key: ValueKey('swipe-${widget.jobId}'),
        dismissThresholds: const {
          DismissDirection.startToEnd: 0.28,
          DismissDirection.endToStart: 0.28,
        },
        movementDuration: m3.motion.resolve(
          context,
          m3.motion.defaultSpatialDuration,
        ),
        onUpdate: (details) {
          if (details.reached && !_reached) {
            _reached = true;
            Haptics.selection();
          } else if (!details.reached && _reached) {
            _reached = false;
          }
        },
        confirmDismiss: (direction) async {
          _reached = false;
          Haptics.medium();
          if (direction == DismissDirection.startToEnd) {
            widget.onSwipeRight();
          } else if (direction == DismissDirection.endToStart) {
            widget.onSwipeLeft();
          }
          // Returning false lets Drift's stream update or remove the item cleanly.
          return false;
        },
        background: _SwipeReveal(
          alignment: Alignment.centerLeft,
          color: widget.rightBg,
          foreground: widget.rightFg,
          icon: widget.rightIcon,
          label: widget.rightLabel,
        ),
        secondaryBackground: _SwipeReveal(
          alignment: Alignment.centerRight,
          color: widget.leftBg,
          foreground: widget.leftFg,
          icon: widget.leftIcon,
          label: widget.leftLabel,
        ),
        child: widget.child,
      ),
    );
  }
}

class _SwipeReveal extends StatelessWidget {
  const _SwipeReveal({
    required this.alignment,
    required this.color,
    required this.foreground,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final Color foreground;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isLeft = alignment == Alignment.centerLeft;
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLeft) ...[
            Icon(icon, color: foreground, size: 22),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ] else ...[
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon, color: foreground, size: 22),
          ],
        ],
      ),
    );
  }
}

/// Pause/Resume while active, organic cookie9 completion badge when done, retry on failure.
class _StatusIcon extends StatelessWidget {
  const _StatusIcon({
    required this.job,
    required this.onCancel,
    required this.onRetry,
    required this.onPause,
    required this.onResume,
  });

  final DownloadJob job;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onPause;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final Widget child = switch (job.status) {
      JobStatus.running => PopIconButton(
        key: const ValueKey('pause'),
        icon: Icons.pause_rounded,
        tooltip: 'Pause download',
        background: cs.surfaceContainerLowest,
        foreground: cs.onSurface,
        onPressed: onPause,
      ),
      JobStatus.queued || JobStatus.waiting => PopIconButton(
        key: const ValueKey('pause-waiting'),
        icon: Icons.pause_rounded,
        tooltip: 'Pause download',
        background: cs.surfaceContainerHigh,
        foreground: cs.onSurface,
        onPressed: onPause,
      ),
      JobStatus.paused => PopIconButton(
        key: const ValueKey('resume'),
        icon: Icons.play_arrow_rounded,
        tooltip: 'Resume download',
        background: cs.primary,
        foreground: cs.onPrimary,
        onPressed: onResume,
      ),
      JobStatus.done => ExpressiveShapeContainer(
        key: const ValueKey('done'),
        polygon: ExpressivePolygon.cookie9,
        size: 46,
        color: cs.primary,
        child: Icon(
          Icons.check_rounded,
          color: cs.onPrimary,
          semanticLabel: 'Done',
        ),
      ),
      JobStatus.failed || JobStatus.canceled => PopIconButton(
        key: const ValueKey('retry'),
        icon: Icons.refresh_rounded,
        tooltip: 'Try again',
        background: cs.errorContainer,
        foreground: cs.onErrorContainer,
        onPressed: onRetry,
      ),
    };
    return AnimatedSwitcher(
      duration: m3.motion.resolve(context, m3.motion.defaultSpatialDuration),
      switchInCurve: m3.motion.defaultSpatialCurve,
      transitionBuilder: (c, a) => ScaleTransition(
        scale: a,
        child: RotationTransition(
          turns: Tween(begin: -0.12, end: 0.0).animate(a),
          child: c,
        ),
      ),
      child: child,
    );
  }
}
