import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../backend/backend.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/task_dialog.dart';

/// Shows AutoRAG index health and lets the user rebuild it. Polls while a refresh runs and shows
/// the phase and file counts as a progress bar.
class IndexSheet extends StatefulWidget {
  const IndexSheet({super.key, required this.api, this.backend});
  final WorklogApi api;

  /// The bundle's runner, for the Kiwi install button; null on the web.
  final Backend? backend;

  static Future<void> show(BuildContext context, WorklogApi api, {Backend? backend}) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => IndexSheet(api: api, backend: backend),
      );

  @override
  State<IndexSheet> createState() => _IndexSheetState();
}

class _IndexSheetState extends State<IndexSheet> {
  IndexStatus? _status;
  Object? _error;
  Timer? _poll;
  DateTime? _startedAt;
  bool _justFinished = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final s = await widget.api.indexStatus();
      if (!mounted) return;
      final wasRefreshing = _status?.refreshing ?? false;
      setState(() {
        _status = s;
        _error = null;
        if (wasRefreshing && !s.refreshing) _justFinished = true;
        if (s.refreshing) _startedAt ??= DateTime.now();
        if (!s.refreshing) _startedAt = null;
      });
      _poll?.cancel();
      if (s.refreshing || s.embedding?.state == 'starting') _poll = Timer(const Duration(seconds: 2), _fetch);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// `zaevis ext install kiwi` through the bundle; the row then shows that a rebuild is owed.
  Future<void> _installKiwi() async {
    await runBackendTask(context, widget.backend!, context.l10n.indexKiwiInstallTitle, const ['ext', 'install', 'kiwi']);
    if (mounted) await _fetch();
  }

  Future<void> _refresh({bool force = false}) async {
    setState(() {
      _justFinished = false;
      _startedAt = DateTime.now();
    });
    try {
      await widget.api.refreshIndex(force: force);
      await _fetch();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    final s = _status;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: _error != null
            ? ErrorPane(error: _error!, onRetry: _fetch)
            : s == null
                ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
                : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.indexTitle, style: t.titleLarge),
                    const SizedBox(height: 12),
                    if (s.refreshing) _Progress(status: s, startedAt: _startedAt) else ...[
                      _row(l.indexStatus, _justFinished ? l.indexDone : _stateLabel(l, s.state)),
                      _row(l.indexFreshness, s.stale ? l.indexStale : l.indexUpToDate),
                    ],
                    if (s.embedding != null) _row(l.indexSemantic, s.embedding!.label),
                    if (s.tokenizer != null) _tokenizerRow(context, s.tokenizer!, s.refreshing),
                    if (s.lastError != null && !s.refreshing) _row(l.indexLastError, s.lastError!),
                    for (final m in s.messages.take(4))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('· $m', style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    if (s.messages.length > 4)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(l.indexMoreMessages(s.messages.length - 4), style: t.bodySmall),
                      ),
                    const SizedBox(height: 16),
                    Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      FilledButton.icon(
                        onPressed: s.refreshing ? null : () => _refresh(),
                        icon: s.refreshing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.sync),
                        label: Text(s.refreshing ? l.indexRefreshing : l.indexRefresh),
                      ),
                      OutlinedButton(
                        onPressed: s.refreshing ? null : () => _refresh(force: true),
                        child: Text(l.indexRebuild),
                      ),
                      if (_justFinished) Icon(Icons.check_circle, color: scheme.primary, size: 20),
                    ]),
                    const SizedBox(height: 8),
                    Text(s.refreshing ? l.indexKeepsRunning : l.indexFirstSlow, style: t.bodySmall),
                  ]),
      ),
    );
  }

  String _stateLabel(AppLocalizations l, String state) => switch (state) {
        'fresh' || 'ready' || 'succeeded' || 'completed' || 'success' => l.indexStateReady,
        'failed' => l.commonFailed,
        'never' || '' => l.indexStateNever,
        'idle' => l.indexStateIdle,
        'not-configured' => l.indexStateNotConfigured,
        'unavailable' => l.indexStateUnavailable,
        'running' || 'refreshing' || 'indexing' => l.indexRefreshing,
        _ => state,
      };

  /// "키워드 분석": Kiwi morphemes or whitespace, with the install button (bundle only) or the rebuild hint.
  Widget _tokenizerRow(BuildContext context, TokenizerStatus ts, bool refreshing) {
    final scheme = Theme.of(context).colorScheme;
    final canInstall = !ts.kiwi.installed && ts.kiwi.installable && widget.backend?.managed == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 96, child: Text(context.l10n.indexKeywords, style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(
          child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SelectableText(ts.label, style: ts.needsReindex && !refreshing ? TextStyle(color: scheme.primary) : null),
            if (canInstall) OutlinedButton(onPressed: refreshing ? null : _installKiwi, child: Text(context.l10n.indexInstallKiwi)),
            if (!ts.kiwi.installed && !canInstall && ts.kiwi.installable && widget.backend == null)
              Text(context.l10n.indexKiwiTerminalHint("'zaevis ext install kiwi'"), style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ]),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 96, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: SelectableText(v)),
        ]),
      );
}

/// Phase label, elapsed time and a bar that fills as files are read and embedded.
class _Progress extends StatelessWidget {
  const _Progress({required this.status, required this.startedAt});
  final IndexStatus status;
  final DateTime? startedAt;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    final p = status.progress;
    final fraction = p?.fraction;
    final elapsed = startedAt == null ? null : DateTime.now().difference(startedAt!);
    final elapsedText = elapsed == null ? '' : elapsed.inMinutes >= 1 ? ' · ${l.collectSpanMinSec(elapsed.inMinutes, elapsed.inSeconds % 60)}' : ' · ${l.collectSpanSec(elapsed.inSeconds)}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(p?.label ?? l.indexStarting, style: t.titleSmall)),
          Text(fraction == null ? elapsedText.replaceFirst(' · ', '') : '${(fraction * 100).round()}%$elapsedText', style: t.labelMedium),
        ]),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: fraction, minHeight: 8)),
        const SizedBox(height: 8),
        Text(_steps(l, p?.phase ?? ''), style: t.bodySmall),
      ]),
    );
  }

  /// "본문 읽기 → 임베딩·색인 → 마무리" with the current step marked.
  String _steps(AppLocalizations l, String phase) {
    final steps = [('parsed', l.indexStepRead), ('minsync', l.indexStepEmbed), ('finalizing', l.indexStepFinish)];
    final current = switch (phase) {
      'parsed' || '' => 0,
      'minsync' => 1,
      _ => 2,
    };
    return [for (var i = 0; i < steps.length; i++) i == current ? '▶ ${steps[i].$2}' : steps[i].$2].join('  →  ');
  }
}
