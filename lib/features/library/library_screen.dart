import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_playback.dart';
import '../../core/theme/pop_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/dock_inset.dart';
import '../../core/widgets/expressive_app_bar.dart';
import '../../core/widgets/expressive_shapes.dart';
import '../../core/widgets/morph.dart';
import '../../core/widgets/pop_widgets.dart';
import '../../core/widgets/toasts.dart';
import '../detail/download_detail_screen.dart';
import 'library_items.dart';
import 'player_screen.dart';

/// Every saved file that still exists on the phone.
final libraryProvider = Provider<List<LibraryItem>>((ref) {
  final jobs = ref.watch(jobsProvider).value ?? const [];
  return buildLibrary(jobs, exists: (p) => File(p).existsSync());
});

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _search = TextEditingController();
  LibraryKind? _kind;
  var _query = '';
  late var _sort =
      LibrarySort.values.asNameMap()[ref
          .read(sharedPrefsProvider)
          .getString('librarySort')] ??
      LibrarySort.newest;
  late var _group =
      ref.read(sharedPrefsProvider).getBool('libraryGroup') ?? false;

  /// Paths picked in selection mode; empty = not selecting.
  final _picked = <String>{};
  bool get _selecting => _picked.isNotEmpty;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setSort(LibrarySort s) {
    Haptics.selection();
    setState(() => _sort = s);
    ref.read(sharedPrefsProvider).setString('librarySort', s.name);
  }

  void _setGroup(bool g) {
    Haptics.selection();
    setState(() => _group = g);
    ref.read(sharedPrefsProvider).setBool('libraryGroup', g);
  }

  void _toggle(LibraryItem i) {
    Haptics.selection();
    setState(
      () => _picked.contains(i.path)
          ? _picked.remove(i.path)
          : _picked.add(i.path),
    );
  }

  Future<void> _shareSelected(List<LibraryItem> all) async {
    final files = [
      for (final i in all)
        if (_picked.contains(i.path)) XFile(i.path),
    ];
    if (files.isEmpty) return;
    await SharePlus.instance.share(ShareParams(files: files));
  }

  Future<void> _deleteSelected() async {
    final n = _picked.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(n == 1 ? 'Delete 1 file?' : 'Delete $n files?'),
        content: const Text(
          "They will be removed from your phone. This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(
                color: context.cs.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    var failed = 0;
    for (final path in _picked) {
      try {
        await AudioPlayback.forget(path);
        await File(path).delete();
      } catch (_) {
        failed++;
      }
    }
    setState(_picked.clear);
    ref.invalidate(libraryProvider);
    Haptics.success();
    popToast(
      failed == 0 ? 'Deleted $n' : 'Deleted ${n - failed}, $failed failed',
      icon: Icons.delete_rounded,
      error: failed > 0,
    );
  }

  static int _size(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return 0;
    }
  }

  Widget _grid(List<LibraryItem> items, {double bottom = 18}) {
    final m3 = context.m3;
    final still = m3.motion.reduced(context);
    final cols = ref.watch(settingsProvider.select((s) => s.libraryColumns));
    final gap = m3.listGap;
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, bottom),
      sliver: SliverGrid.builder(
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: gap + 4,
          crossAxisSpacing: gap,
          childAspectRatio: cols == 3 ? 0.68 : 0.78,
        ),
        itemBuilder: (context, i) {
          final item = items[i];
          final tile = _Tile(
            key: ValueKey(item.path),
            item: item,
            selecting: _selecting,
            selected: _picked.contains(item.path),
            compact: cols == 3,
            onToggle: () => _toggle(item),
          );
          return still
              ? tile
              : tile
                    .animate()
                    .fadeIn(
                      duration: m3.motion.defaultEffectsDuration,
                      delay: (25 * (i % 10)).ms,
                    )
                    .scaleXY(
                      begin: 0.94,
                      end: 1,
                      curve: m3.motion.defaultSpatialCurve,
                    );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(libraryProvider);
    final items = sortLibrary(
      filterLibrary(all, kind: _kind, query: _query),
      _sort,
      sizeOf: _size,
    );
    // Drop picks for files that disappeared.
    _picked.removeWhere((p) => !all.any((i) => i.path == p));

    // Back leaves selection mode first.
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_picked.clear);
      },
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: () async => ref.invalidate(libraryProvider),
          child: CustomScrollView(
            slivers: [
              if (_selecting)
                SliverAppBar(
                  pinned: true,
                  automaticallyImplyLeading: false,
                  backgroundColor: context.cs.surfaceContainer,
                  surfaceTintColor: Colors.transparent,
                  toolbarHeight: 64,
                  titleSpacing: 16,
                  title: _SelectionBar(
                    key: const ValueKey('select'),
                    count: _picked.length,
                    onClose: () => setState(_picked.clear),
                    onAll: () => setState(
                      () => _picked.addAll(items.map((i) => i.path)),
                    ),
                    onShare: () => _shareSelected(all),
                    onDelete: _deleteSelected,
                  ),
                )
              else
                ExpressiveSliverHeader(
                  title: 'Library',
                  actions: [
                    if (items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: TextButton(
                          onPressed: () => _toggle(items.first),
                          child: const Text(
                            'Select',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                sliver: SliverList.list(
                  children: [
                    TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: 'Search downloads',
                        prefixIcon: Icon(Icons.search_rounded),
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 12),
                    PopSegmented<LibraryKind?>(
                      values: const [
                        null,
                        LibraryKind.video,
                        LibraryKind.audio,
                        LibraryKind.subtitles,
                      ],
                      labels: const ['All', 'Video', 'Audio', 'Subs'],
                      selected: _kind,
                      onChanged: (k) => setState(() => _kind = k),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        PopupMenuButton<LibrarySort>(
                          tooltip: 'Sort',
                          initialValue: _sort,
                          onSelected: _setSort,
                          itemBuilder: (_) => [
                            for (final s in LibrarySort.values)
                              CheckedPopupMenuItem(
                                value: s,
                                checked: s == _sort,
                                child: Text(s.label),
                              ),
                          ],
                          child: Chip(
                            avatar: const Icon(Icons.sort_rounded, size: 18),
                            label: Text(_sort.label),
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: context.pop.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          avatar: _group
                              ? null
                              : const Icon(Icons.workspaces_rounded, size: 18),
                          label: const Text('By platform'),
                          selected: _group,
                          onSelected: _setGroup,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
              if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      12,
                      24,
                      DockInset.listBottom(context),
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ExpressiveEmptyState(
                        icon: all.isEmpty
                            ? Icons.video_library_rounded
                            : Icons.search_off_rounded,
                        polygon: all.isEmpty
                            ? ExpressivePolygon.cookie12
                            : ExpressivePolygon.clover4,
                        containerColor: context.cs.secondaryContainer,
                        iconColor: context.cs.onSecondaryContainer,
                        title: all.isEmpty
                            ? 'Your downloads show up here'
                            : 'Nothing matches',
                        subtitle: all.isEmpty
                            ? 'Saved videos, audio, and subtitles will appear neatly here.'
                            : 'Try clearing your search or switching filters.',
                        actionLabel: all.isEmpty ? null : 'Clear filters',
                        actionIcon: all.isEmpty ? null : Icons.clear_all_rounded,
                        onAction: all.isEmpty
                            ? null
                            : () => setState(() {
                                _search.clear();
                                _query = '';
                                _kind = null;
                              }),
                      ),
                    ),
                  ),
                )
              else if (!_group)
                _grid(items, bottom: DockInset.listBottom(context))
              else ...[
                for (final (name, group) in groupBySite(items)) ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                    sliver: SliverToBoxAdapter(
                      child: PopSection('$name · ${group.length}'),
                    ),
                  ),
                  _grid(group),
                ],
                SliverToBoxAdapter(
                  child: SizedBox(height: DockInset.listBottom(context) - 20),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({
    super.key,
    required this.item,
    required this.selecting,
    required this.selected,
    required this.compact,
    required this.onToggle,
  });

  final LibraryItem item;
  final bool selecting;
  final bool selected;
  final bool compact;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.cs;
    final m3 = context.m3;
    final subs = item.kind == LibraryKind.subtitles;
    return Semantics(
      button: true,
      label:
          '${item.title}, ${item.ext}${selecting ? (selected ? ', selected' : ', not selected') : ''}',
      excludeSemantics: true,
      child: Morph(
        shape: const RoundedRectangleBorder(),
        page: (_) => DownloadDetailScreen(jobId: item.jobId),
        builder: (context, open) => InkWell(
          borderRadius: m3.thumbRadius,
          onTap: selecting ? onToggle : open,
          onLongPress: onToggle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: subs
                          ? Container(
                              decoration: BoxDecoration(
                                color: cs.tertiaryContainer,
                                borderRadius: m3.thumbRadius,
                              ),
                              child: Icon(
                                Icons.subtitles_rounded,
                                size: 40,
                                color: cs.onTertiaryContainer,
                              ),
                            )
                          : PopThumb(
                              seed: item.jobId,
                              url: item.thumbnail,
                              audio: item.kind == LibraryKind.audio,
                              size: double.infinity,
                            ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          shape: const StadiumBorder(),
                          color: cs.primaryContainer,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: Text(
                            item.ext,
                            style: TextStyle(
                              color: cs.onPrimaryContainer,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (selected)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: m3.thumbRadius,
                            border: Border.all(color: cs.primary, width: 3.5),
                            color: cs.primary.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: selecting
                          ? Padding(
                              padding: const EdgeInsets.all(8),
                              child: AnimatedScale(
                                scale: selected ? 1.08 : 1.0,
                                duration: m3.motion.resolve(
                                  context,
                                  m3.motion.fastSpatialDuration,
                                ),
                                curve: m3.motion.fastSpatialCurve,
                                child: AnimatedContainer(
                                  duration: m3.motion.resolve(
                                    context,
                                    m3.motion.defaultSpatialDuration,
                                  ),
                                  curve: m3.motion.defaultSpatialCurve,
                                  width: 28,
                                  height: 28,
                                  decoration: ShapeDecoration(
                                    color: selected
                                        ? cs.primary
                                        : Colors.black38,
                                    shape: ExpressivePolygonBorder(
                                      polygon: selected
                                          ? ExpressivePolygon.cookie9
                                          : ExpressivePolygon.circle,
                                      side: const BorderSide(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: selected
                                      ? Icon(
                                          Icons.check_rounded,
                                          size: 17,
                                          color: cs.onPrimary,
                                        )
                                      : null,
                                ),
                              ),
                            )
                          : IconButton(
                              tooltip: 'More',
                              onPressed: () => _actions(context, ref),
                              padding: compact
                                  ? EdgeInsets.zero
                                  : const EdgeInsets.all(8),
                              constraints: compact
                                  ? const BoxConstraints.tightFor(
                                      width: 30,
                                      height: 30,
                                    )
                                  : null,
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black45,
                                foregroundColor: Colors.white,
                              ),
                              icon: Icon(
                                Icons.more_horiz_rounded,
                                size: compact ? 18 : 24,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 13 : 15,
                ),
              ),
              Text(
                [
                  item.site,
                  fileSizeLabel(item.path),
                ].whereType<String>().join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: compact ? 11 : 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _actions(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final cs = context.cs;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  item.fileName,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                ExpressiveGroup(
                  children: [
                    if (item.kind != LibraryKind.subtitles)
                      ExpressiveListRow(
                        title: 'Play',
                        leading: Icon(
                          Icons.play_arrow_rounded,
                          color: cs.primary,
                        ),
                        onTap: () => Navigator.pop(context, 'play'),
                      ),
                    ExpressiveListRow(
                      title: 'Share',
                      leading: Icon(Icons.share_rounded, color: cs.primary),
                      onTap: () => Navigator.pop(context, 'share'),
                    ),
                    ExpressiveListRow(
                      title: 'Delete file',
                      leading: Icon(
                        Icons.delete_outline_rounded,
                        color: cs.error,
                      ),
                      onTap: () => Navigator.pop(context, 'delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!context.mounted) return;
    switch (action) {
      case 'play':
        openPlayer(context, item);
      case 'share':
        await SharePlus.instance.share(
          ShareParams(files: [XFile(item.path)], subject: item.title),
        );
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete this file?'),
            content: Text(
              '${item.fileName}\n\nIt will be removed from your phone. This can\'t be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'Delete',
                  style: TextStyle(
                    color: context.cs.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
        if (ok != true) return;
        try {
          await AudioPlayback.forget(item.path);
          await File(item.path).delete();
          ref.invalidate(libraryProvider);
          popToast(
            'Deleted',
            icon: Icons.delete_rounded,
            detail: item.fileName,
          );
        } catch (e) {
          popToast("Couldn't delete", error: true, detail: '$e');
        }
    }
  }
}

/// Replaces the Library title while picking files.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    super.key,
    required this.count,
    required this.onClose,
    required this.onAll,
    required this.onShare,
    required this.onDelete,
  });

  final int count;
  final VoidCallback onClose;
  final VoidCallback onAll;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Done',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
          Expanded(
            child: Text(
              '$count selected',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(onPressed: onAll, child: const Text('All')),
          PopIconButton(
            icon: Icons.share_rounded,
            tooltip: 'Share selected',
            onPressed: onShare,
          ),
          const SizedBox(width: 6),
          PopIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete selected',
            background: cs.errorContainer,
            foreground: cs.onErrorContainer,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
