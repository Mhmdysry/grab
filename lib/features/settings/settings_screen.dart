import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/providers.dart';
import '../../core/theme/pop_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/permissions.dart';
import '../../core/utils/platform.dart';
import '../../core/widgets/dock_inset.dart';
import '../../core/widgets/expressive_app_bar.dart';
import '../../core/widgets/expressive_shapes.dart';
import '../../core/widgets/pop_widgets.dart';
import '../../core/widgets/toasts.dart';
import '../../data/db/app_database.dart';
import '../../data/engine/media_info.dart';
import '../../data/settings/app_settings.dart';
import '../library/library_items.dart';
import '../library/library_screen.dart';
import 'about_screen.dart';
import 'appearance_screen.dart';

final _outputDirProvider = FutureProvider<String?>(
  (ref) => ref.watch(engineProvider).outputDir(),
);
final _packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

/// Settings: download defaults, the yt-dlp engine, appearance, about.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  var _updating = false;
  var _permCheck = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _permCheck++);
    }
  }

  Future<void> _updateEngine() async {
    setState(() => _updating = true);
    try {
      final r = await ref.read(engineProvider).update();
      ref.invalidate(engineVersionProvider);
      popToast(
        r == 'updated' ? 'yt-dlp updated' : 'Already up to date',
        icon: Icons.system_update_alt_rounded,
      );
    } on PlatformException catch (e) {
      popToast('Update failed', error: true, detail: e.message);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier).update;
    final version = ref.watch(engineVersionProvider);
    final folder = ref.watch(_outputDirProvider).value;
    final app = ref.watch(_packageInfoProvider).value;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const ExpressiveSliverHeader(title: 'Settings'),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              24,
              4,
              24,
              DockInset.listBottom(context),
            ),
            sliver: SliverList.list(
              children: [
                const PopSection('Downloads'),
                _Group(
                  children: [
                    _Row(
                      label: 'Save to',
                      value: folder == null ? s.savePath : _shortPath(folder),
                      onTap: () => _editFolder(s),
                    ),
                    _Row(
                      label: 'File names',
                      value: previewFileName(s.fileTemplate),
                      onTap: () => _editTemplate(s),
                    ),
                    _Row(
                      label: 'Default mode',
                      value: _modeLabel(s.defaultMode),
                      onTap: () => _pick<DownloadMode>(
                        title: 'Default mode',
                        options: const [
                          DownloadMode.video,
                          DownloadMode.videoAndAudio,
                          DownloadMode.audioOnly,
                        ],
                        current: s.defaultMode,
                        label: _modeLabel,
                        onPick: (v) => set((x) => x.copyWith(defaultMode: v)),
                      ),
                    ),
                    _Row(
                      label: 'Default quality',
                      value: s.maxHeight == null
                          ? 'Best available'
                          : '${s.maxHeight}p',
                      onTap: () => _pick<int?>(
                        title: 'Default quality',
                        options: AppSettings.heights,
                        current: s.maxHeight,
                        label: (h) =>
                            h == null ? 'Best available' : '${h}p or lower',
                        onPick: (v) =>
                            set((x) => x.copyWith(maxHeight: () => v)),
                      ),
                    ),
                    _Row(
                      label: 'Video format',
                      value: s.container.toUpperCase(),
                      onTap: () => _pick<String>(
                        title: 'Video format',
                        options: AppSettings.containers,
                        current: s.container,
                        label: (c) => switch (c) {
                          'mp4' => 'MP4 · plays everywhere',
                          'mkv' => 'MKV · keeps every track',
                          _ => 'WEBM · smaller files',
                        },
                        onPick: (v) => set((x) => x.copyWith(container: v)),
                      ),
                    ),
                    _Row(
                      label: 'Audio format',
                      value: s.audioFormat.toUpperCase(),
                      onTap: () => _pick<String>(
                        title: 'Audio format',
                        options: AppSettings.audioFormats,
                        current: s.audioFormat,
                        label: (f) => switch (f) {
                          'mp3' => 'MP3 · plays everywhere',
                          'm4a' => 'M4A · good for Apple devices',
                          'opus' => 'Opus · smallest files',
                          _ => 'FLAC · lossless, large',
                        },
                        onPick: (v) => set((x) => x.copyWith(audioFormat: v)),
                      ),
                    ),
                    _Row(
                      label: 'Downloads at once',
                      value: '${s.maxParallel}',
                      onTap: () => _pick<int>(
                        title: 'Downloads at once',
                        options: const [1, 2, 3],
                        current: s.maxParallel,
                        label: (n) => n == 1
                            ? '1 · one after another'
                            : '$n at the same time',
                        onPick: (v) => set((x) => x.copyWith(maxParallel: v)),
                      ),
                    ),
                  ],
                ),
                if (isPhone) ...[
                  const SizedBox(height: 16),
                  const PopSection('Share & Quick Grab'),
                  _ShareOverlayHub(
                    settings: s,
                    onToggleInstantGrab: (v) {
                      Haptics.selection();
                      set((x) => x.copyWith(instantGrab: v));
                    },
                    onToggleKeepOpen: (v) {
                      Haptics.selection();
                      set((x) => x.copyWith(shareKeepOpen: v));
                    },
                  ),
                ],
                const SizedBox(height: 16),
                const PopSection('Storage'),
                const _StorageGroup(),
                const SizedBox(height: 16),
                const PopSection('Engine'),
                _Group(
                  children: [
                    _Row(
                      label: 'yt-dlp',
                      value: version.when(
                        data: (v) => v ?? 'unknown',
                        loading: () => 'starting…',
                        error: (_, _) => 'failed to start',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: PopButton(
                        label: 'Check for engine update',
                        icon: Icons.system_update_alt_rounded,
                        busy: _updating,
                        height: 48,
                        onPressed: _updateEngine,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    'Sites change often. If a link stops working, update the engine first.',
                    style: TextStyle(fontSize: 13, color: context.pop.muted),
                  ),
                ),
                const SizedBox(height: 16),
                if (isPhone) ...[
                  const PopSection('Notifications'),
                  _Group(
                    children: [
                      FutureBuilder<PermissionStatus>(
                        key: ValueKey(_permCheck),
                        future: notificationStatus(),
                        builder: (context, snap) {
                          final on = snap.data?.isGranted ?? false;
                          return _Row(
                            label: 'Download alerts',
                            value: snap.data == null ? '' : (on ? 'On' : 'Off'),
                            onTap: on
                                ? null
                                : () async {
                                    await requestNotifications();
                                    if (mounted) setState(() => _permCheck++);
                                  },
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                const PopSection('Appearance & Customization'),
                _AppearanceHeroCard(
                  settings: s,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AppearanceScreen()),
                  ),
                ),
                const SizedBox(height: 10),
                PopSegmented<ThemeMode>(
                  values: const [
                    ThemeMode.system,
                    ThemeMode.light,
                    ThemeMode.dark,
                  ],
                  labels: const ['System', 'Light', 'Dark'],
                  selected: s.themeMode,
                  onChanged: (m) => set((x) => x.copyWith(themeMode: m)),
                ),
                const SizedBox(height: 16),
                const PopSection('About'),
                _Group(
                  children: [
                    _Row(
                      label: 'Grab',
                      value: app == null ? '' : 'v${app.version}',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AboutScreen()),
                      ),
                    ),
                    _Row(
                      label: 'Open-source licenses',
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'Grab',
                        applicationVersion: app?.version,
                        applicationLegalese:
                            'Free software under GPL-3.0. Uses yt-dlp, FFmpeg and Python.',
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                  child: Text(
                    'Download only what you have the right to save. Respect creators and each site\'s rules.',
                    style: TextStyle(fontSize: 12, color: context.pop.muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pick<T>({
    required String title,
    required List<T> options,
    required T current,
    required String Function(T) label,
    required ValueChanged<T> onPick,
  }) async {
    final picked = await showModalBottomSheet<(T,)>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            for (final o in options)
              PopOptionTile(
                label: label(o),
                selected: o == current,
                onTap: () => Navigator.of(context).pop((o,)),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onPick(picked.$1);
  }

  static String _modeLabel(DownloadMode m) => switch (m) {
    DownloadMode.video => 'Video',
    DownloadMode.videoAndAudio => 'Video + audio file',
    DownloadMode.audioOnly => 'Audio only',
    DownloadMode.subtitlesOnly => 'Subtitles only',
  };

  static String _shortPath(String p) {
    for (final b in ['/Download/', '/Movies/', '/Music/']) {
      final i = p.indexOf(b);
      if (i >= 0) return p.substring(i + 1);
    }
    return p;
  }

  Future<void> _editFolder(AppSettings s) async {
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FolderSheet(base: s.saveBase, folder: s.saveFolder),
    );
    if (result == null) return;
    final (base, folder) = result;
    await ref
        .read(settingsProvider.notifier)
        .update((x) => x.copyWith(saveBase: base, saveFolder: folder));
    final path = await ref.read(engineProvider).setOutputDir(base, folder);
    ref.invalidate(_outputDirProvider);
    popToast(
      'New downloads go to ${_shortPath(path ?? '$base/$folder')}',
      icon: Icons.folder_rounded,
      detail: 'Files already saved stay where they are.',
    );
  }

  Future<void> _editTemplate(AppSettings s) async {
    final t = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TemplateSheet(initial: s.fileTemplate),
    );
    if (t == null) return;
    await ref
        .read(settingsProvider.notifier)
        .update((x) => x.copyWith(fileTemplate: t));
  }
}

class _FolderSheet extends StatefulWidget {
  const _FolderSheet({required this.base, required this.folder});

  final String base;
  final String folder;

  @override
  State<_FolderSheet> createState() => _FolderSheetState();
}

class _FolderSheetState extends State<_FolderSheet> {
  late var _base = widget.base;
  late final _name = TextEditingController(text: widget.folder);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _clean =>
      _name.text.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Save to',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          PopSegmented<String>(
            values: AppSettings.saveBases,
            labels: [
              for (final b in AppSettings.saveBases) AppSettings.baseLabel(b),
            ],
            selected: _base,
            onChanged: (b) => setState(() => _base = b),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Folder name',
              prefixIcon: Icon(Icons.folder_rounded),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Saves to ${AppSettings.baseLabel(_base)}/${_clean.isEmpty ? 'Grab' : _clean}. '
            'Android lets apps save straight into Download, Movies and Music.',
            style: TextStyle(color: context.pop.muted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          PopButton(
            label: 'Save',
            onPressed: () => Navigator.pop(context, (
              _base,
              _clean.isEmpty ? 'Grab' : _clean,
            )),
          ),
        ],
      ),
    );
  }
}

class _TemplateSheet extends StatefulWidget {
  const _TemplateSheet({required this.initial});

  final String initial;

  @override
  State<_TemplateSheet> createState() => _TemplateSheetState();
}

class _TemplateSheetState extends State<_TemplateSheet> {
  late final _t = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  void _insert(String token) {
    final sel = _t.selection;
    final text = _t.text;
    final at = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    _t.value = TextEditingValue(
      text: text.replaceRange(at, end, token),
      selection: TextSelection.collapsed(offset: at + token.length),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'File names',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _t,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Template',
              prefixIcon: Icon(Icons.text_fields_rounded),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final token in fileNameTokens.keys)
                ActionChip(label: Text(token), onPressed: () => _insert(token)),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.pop.soft,
              borderRadius: Pop.thumbRadius,
            ),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    previewFileName(_t.text),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Leaving out {id} gives cleaner names, but two videos with the same title will clash.',
            style: TextStyle(color: context.pop.muted, fontSize: 12),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, defaultFileTemplate),
                child: const Text('Reset'),
              ),
              const Spacer(),
              PopButton(
                label: 'Save',
                expand: false,
                onPressed: () => Navigator.pop(context, _t.text.trim()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppearanceHeroCard extends StatelessWidget {
  const _AppearanceHeroCard({required this.settings, required this.onTap});

  final AppSettings settings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final subtitle = [
      settings.useDynamicColor ? 'Dynamic' : settings.accentPalette.label,
      settings.schemeStyle.label,
      settings.navStyle.label,
      settings.motionPreset.label,
    ].join(' · ');

    return Material(
      color: cs.primaryContainer,
      borderRadius: m3.cardRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ExpressiveShapeContainer(
                polygon: ExpressivePolygon.cookie9,
                size: 50,
                color: cs.primary,
                child: Icon(
                  Icons.palette_rounded,
                  color: cs.onPrimary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appearance Studio',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimaryContainer.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: cs.onPrimaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ExpressiveGroup(children: children);
}

class _Row extends StatelessWidget {
  const _Row({required this.label, this.value, this.onTap});

  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final m3 = context.m3;
    final cs = context.cs;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 18,
            vertical: m3.rowVerticalPad - 2,
          ),
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  value ?? '',
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "2.3 GB used" by saved files, split by kind, plus clearing failed downloads.
class _StorageGroup extends ConsumerWidget {
  const _StorageGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.cs;
    final items = ref.watch(libraryProvider);
    final jobs = ref.watch(jobsProvider).value ?? const <DownloadJob>[];
    final failed = jobs
        .where(
          (j) => j.status == JobStatus.failed || j.status == JobStatus.canceled,
        )
        .length;
    final byKind = <LibraryKind, int>{};
    for (final i in items) {
      int size;
      try {
        size = File(i.path).lengthSync();
      } catch (_) {
        size = 0;
      }
      byKind[i.kind] = (byKind[i.kind] ?? 0) + size;
    }
    final total = byKind.values.fold(0, (a, b) => a + b);
    final kinds = [
      (LibraryKind.video, 'Video', cs.primary),
      (LibraryKind.audio, 'Audio', cs.tertiary),
      (LibraryKind.subtitles, 'Subtitles', cs.secondary),
    ];

    return _Group(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                total == 0 ? 'Nothing saved yet' : '${formatBytes(total)} used',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${items.length} ${items.length == 1 ? 'file' : 'files'} in ${ref.watch(settingsProvider).savePath}',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              if (total > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 12,
                    child: Row(
                      children: [
                        for (final (k, _, color) in kinds)
                          if ((byKind[k] ?? 0) > 0)
                            Expanded(
                              flex: ((byKind[k]! / total) * 1000).round().clamp(
                                8,
                                1000,
                              ),
                              child: ColoredBox(color: color),
                            ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    for (final (k, label, color) in kinds)
                      if ((byKind[k] ?? 0) > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: ShapeDecoration(
                                shape: const CircleBorder(),
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$label ${formatBytes(byKind[k])}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                  ],
                ),
              ],
            ],
          ),
        ),
        _Row(
          label: 'Clear failed downloads',
          value: failed == 0 ? 'None' : '$failed',
          onTap: failed == 0
              ? null
              : () async {
                  final n = await ref
                      .read(downloadRepositoryProvider)
                      .clearFailed();
                  popToast(
                    'Cleared $n from history',
                    icon: Icons.cleaning_services_rounded,
                    detail: 'Saved files are not touched.',
                  );
                },
        ),
      ],
    );
  }
}

class _ShareOverlayHub extends StatelessWidget {
  const _ShareOverlayHub({
    required this.settings,
    required this.onToggleInstantGrab,
    required this.onToggleKeepOpen,
  });

  final AppSettings settings;
  final ValueChanged<bool> onToggleInstantGrab;
  final ValueChanged<bool> onToggleKeepOpen;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return ExpressiveGroup(
      children: [
        ExpressiveListRow(
          title: 'Instant Grab',
          subtitle:
              'Auto-download single links with your default mode & quality',
          leading: Icon(Icons.bolt_rounded, color: cs.primary),
          trailing: Switch(
            value: settings.instantGrab,
            onChanged: onToggleInstantGrab,
          ),
          onTap: () => onToggleInstantGrab(!settings.instantGrab),
        ),
        ExpressiveListRow(
          title: 'Keep share popup open',
          subtitle: 'Watch progress inside the share card instead of closing',
          leading: Icon(
            Icons.picture_in_picture_alt_rounded,
            color: cs.primary,
          ),
          trailing: Switch(
            value: settings.shareKeepOpen,
            onChanged: onToggleKeepOpen,
          ),
          onTap: () => onToggleKeepOpen(!settings.shareKeepOpen),
        ),
      ],
    );
  }
}
