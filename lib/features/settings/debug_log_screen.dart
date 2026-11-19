import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/log/app_log.dart';
import '../../core/theme/pop_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/expressive_shapes.dart';
import '../../core/widgets/pop_widgets.dart';
import '../../core/widgets/toasts.dart';

enum _LogTab { app, errors, logcat }

/// In-app diagnostic & crash log viewer. Shows persistent app/crash events
/// from both `main` and `shareMain` isolates alongside native Android `logcat`
/// for the current process, with 1-tap Copy, Share, Refresh, and Clear.
class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key});

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  _LogTab _tab = _LogTab.app;
  String _appLogText = '';
  String _logcatText = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AppLog.revision.addListener(_onLogChanged);
    _refresh();
  }

  @override
  void dispose() {
    AppLog.revision.removeListener(_onLogChanged);
    super.dispose();
  }

  void _onLogChanged() {
    if (mounted) _loadAppLog();
  }

  Future<void> _loadAppLog() async {
    final text = await AppLog.readAppLogs();
    if (!mounted) return;
    setState(() => _appLogText = text);
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      AppLog.readAppLogs(),
      AppLog.readNativeLogcat(),
    ]);
    if (!mounted) return;
    setState(() {
      _appLogText = results[0];
      _logcatText = results[1];
      _loading = false;
    });
  }

  String get _displayedText {
    switch (_tab) {
      case _LogTab.app:
        return _appLogText.trim().isEmpty
            ? 'No app log entries recorded yet.'
            : _appLogText;
      case _LogTab.errors:
        final blocks = _appLogText
            .split('\n[' )
            .map((b) => b.startsWith('[') ? b : '[$b')
            .where((b) => b.contains('[ERROR]') || b.contains('[WARN]'))
            .toList();
        if (blocks.isEmpty) {
          return 'No errors or warnings recorded.';
        }
        return blocks.join('\n');
      case _LogTab.logcat:
        return _logcatText.trim().isEmpty
            ? 'No native logcat lines available.'
            : _logcatText;
    }
  }

  Future<void> _copy() async {
    Haptics.selection();
    final text = _displayedText;
    await Clipboard.setData(ClipboardData(text: text));
    popToast(
      'Debug log copied',
      icon: Icons.copy_rounded,
      detail: '${text.split('\n').length} lines copied to clipboard.',
    );
  }

  Future<void> _share() async {
    Haptics.selection();
    final report = StringBuffer()
      ..writeln('=== GRAB DEBUG & CRASH LOG ===')
      ..writeln('Generated: ${DateTime.now().toIso8601String()}')
      ..writeln('\n--- APP & CRASH LOG ---')
      ..writeln(_appLogText.trim().isEmpty ? '(empty)' : _appLogText)
      ..writeln('\n--- NATIVE LOGCAT ---')
      ..writeln(_logcatText.trim().isEmpty ? '(empty)' : _logcatText);
    await SharePlus.instance.share(
      ShareParams(
        text: report.toString(),
        subject: 'Grab Debug Log',
      ),
    );
  }

  Future<void> _clear() async {
    Haptics.medium();
    await AppLog.clear();
    await _refresh();
    popToast(
      'Debug log cleared',
      icon: Icons.cleaning_services_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final text = _displayedText;
    final logPath = AppLog.logFilePath;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Debug log',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Copy log',
            onPressed: _copy,
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(
            tooltip: 'Share full report',
            onPressed: _share,
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: 'Clear logs',
            onPressed: _clear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: PopSegmented<_LogTab>(
              values: const [_LogTab.app, _LogTab.errors, _LogTab.logcat],
              labels: const ['App Log', 'Errors Only', 'Android Logcat'],
              selected: _tab,
              onChanged: (t) {
                Haptics.selection();
                setState(() => _tab = t);
              },
            ),
          ),
          if (logPath != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: Text(
                'File: $logPath',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: m3.cardRadius,
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
                child: _loading
                    ? Center(
                        child: ExpressiveLoadingIndicator(
                          color: cs.primary,
                          containerColor: cs.primaryContainer,
                        ),
                      )
                    : Scrollbar(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(14),
                          child: SelectableText(
                            text,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              height: 1.4,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
