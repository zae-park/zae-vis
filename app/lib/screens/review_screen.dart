import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/input_dialogs.dart';
import '../widgets/markdown_view.dart';

/// Review of one digest run: the log lines, project pages and monthly summaries the agent wanted to
/// write, each with a checkbox. 적용 writes the chosen parts into the worklog; 버리기 drops the run.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.api, required this.id});
  final WorklogApi api;
  final String id;

  /// Pushes the screen; resolves to true when the proposal was applied or dismissed.
  static Future<bool> open(BuildContext context, WorklogApi api, String id) async =>
      await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ReviewScreen(api: api, id: id))) ?? false;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late Future<Proposal> _future = widget.api.proposal(widget.id);
  final Set<int> _lines = {};
  final Set<String> _projects = {};
  bool _summaries = true;
  bool _processed = true;
  bool _initialised = false;
  bool _busy = false;

  void _init(Proposal p) {
    if (_initialised) return;
    _initialised = true;
    _lines.addAll(List.generate(p.logLines.length, (i) => i));
    _projects.addAll(p.projects.map((e) => e.slug));
  }

  int _chosen(Proposal p) => _lines.length + _projects.length + (_summaries ? p.summaries.length : 0) + (_processed ? p.processed.length : 0);

  Future<void> _apply(Proposal p) async {
    setState(() => _busy = true);
    try {
      await widget.api.applyProposal(
        widget.id,
        lines: _lines.length == p.logLines.length ? null : (_lines.toList()..sort()),
        projects: _projects.length == p.projects.length ? null : _projects.toList(),
        summaries: _summaries,
        processed: _processed,
      );
      if (!mounted) return;
      toast(context, context.l10n.reviewApplied(_lines.length, _projects.length));
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      toast(context, e.message, error: true);
      setState(() {
        _busy = false;
        _future = widget.api.proposal(widget.id);
      });
    }
  }

  Future<void> _dismiss() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.reviewDismissTitle),
        content: Text(context.l10n.reviewDismissBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.reviewDismiss)),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.dismissProposal(widget.id);
      if (!mounted) return;
      toast(context, context.l10n.reviewDismissed);
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      toast(context, e.message, error: true);
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.reviewTitle)),
      body: FutureBuilder<Proposal>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return ErrorPane(error: snap.error!, onRetry: () => setState(() => _future = widget.api.proposal(widget.id)));
          final p = snap.data!;
          _init(p);
          final when = p.createdAt?.toLocal().toString().split('.').first ?? '';
          return Column(children: [
            Expanded(
              child: Readable(
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
                  Text('${_agentLabel(p.agent)} · $when${p.pending ? '' : ' · ${_statusLabel(context.l10n, p.status)}'}', style: t.bodySmall),
                  const SizedBox(height: 4),
                  Text(context.l10n.reviewIntro, style: t.bodySmall),
                  if (p.removedLines.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: scheme.errorContainer.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(8)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(context.l10n.reviewRemoved(p.removedLines.length), style: t.labelLarge?.copyWith(color: scheme.error)),
                        for (final l in p.removedLines.take(10))
                          Padding(padding: const EdgeInsets.only(top: 4), child: Text('${l.month} · ${l.entry.text}', style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // ── log lines ───────────────────────────────────────────
                  SectionHeader(
                    context.l10n.reviewLogLines(_lines.length, p.logLines.length),
                    subtitle: p.logLines.isEmpty ? context.l10n.reviewNoNewLines : null,
                    trailing: p.logLines.isEmpty
                        ? null
                        : TextButton(
                            onPressed: () => setState(() => _lines.length == p.logLines.length ? _lines.clear() : _lines.addAll(List.generate(p.logLines.length, (i) => i))),
                            child: Text(_lines.length == p.logLines.length ? context.l10n.reviewDeselectAll : context.l10n.reviewSelectAll),
                          ),
                  ),
                  for (final month in p.logLines.map((l) => l.month).toSet()) ...[
                    Padding(padding: const EdgeInsets.only(top: 8, bottom: 2), child: Text(month, style: t.labelLarge?.copyWith(color: scheme.outline))),
                    for (var i = 0; i < p.logLines.length; i++)
                      if (p.logLines[i].month == month) _LineTile(line: p.logLines[i], checked: _lines.contains(i), onChanged: (v) => setState(() => v ? _lines.add(i) : _lines.remove(i))),
                  ],
                  const SizedBox(height: 16),
                  // ── projects ────────────────────────────────────────────
                  SectionHeader(context.l10n.reviewProjects(_projects.length, p.projects.length), subtitle: p.projects.isEmpty ? context.l10n.reviewNoProjects : null),
                  for (final pr in p.projects)
                    _FileTile(
                      title: pr.slug,
                      badge: pr.isNew ? context.l10n.reviewNewFile : context.l10n.reviewChanged,
                      before: pr.before,
                      after: pr.after,
                      checked: _projects.contains(pr.slug),
                      onChanged: (v) => setState(() => v ? _projects.add(pr.slug) : _projects.remove(pr.slug)),
                    ),
                  const SizedBox(height: 16),
                  // ── summaries ───────────────────────────────────────────
                  SectionHeader(context.l10n.reviewSummaries(p.summaries.length), subtitle: p.summaries.isEmpty ? context.l10n.reviewNoSummaries : null),
                  if (p.summaries.isNotEmpty)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.l10n.reviewApplySummaries),
                      subtitle: Text(p.summaries.map((s) => s.path).join(', ')),
                      value: _summaries,
                      onChanged: (v) => setState(() => _summaries = v),
                    ),
                  for (final s in p.summaries) _FileTile(title: s.path, badge: s.before == null ? context.l10n.reviewNewFile : context.l10n.reviewChanged, before: s.before, after: s.after),
                  const SizedBox(height: 16),
                  // ── processed inbox files ───────────────────────────────
                  SectionHeader(context.l10n.reviewProcessed(p.processed.length), subtitle: p.processed.isEmpty ? context.l10n.commonNone : null),
                  if (p.processed.isNotEmpty)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.l10n.reviewMoveProcessed),
                      subtitle: Text('${p.processed.map((m) => m.from.split('/').last).take(5).join(', ')}${p.processed.length > 5 ? ' ${context.l10n.reviewMore(p.processed.length - 5)}' : ''}\n${context.l10n.reviewProcessedHint}'),
                      value: _processed,
                      onChanged: (v) => setState(() => _processed = v),
                    ),
                  if (p.report.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(context.l10n.reviewAgentReport, style: t.titleSmall),
                      children: [
                        SelectableText(p.report.length > 4000 ? '…${p.report.substring(p.report.length - 4000)}' : p.report, style: ZaevisTheme.mono.copyWith(fontSize: 12), minLines: 1),
                      ],
                    ),
                  ],
                ]),
              ),
            ),
            if (p.pending)
              Material(
                elevation: 4,
                color: scheme.surface,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Row(children: [
                      Expanded(child: Text(context.l10n.reviewSelected(_chosen(p)), style: t.bodyMedium)),
                      TextButton(onPressed: _busy ? null : _dismiss, child: Text(context.l10n.reviewDismiss, style: TextStyle(color: scheme.error))),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _busy || _chosen(p) == 0 ? null : () => _apply(p),
                        icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                        label: Text(context.l10n.reviewApply),
                      ),
                    ]),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }

  static String _agentLabel(String id) => switch (id) {
        'claude' => 'Claude Code',
        'codex' => 'Codex CLI',
        'gemini' => 'Gemini CLI',
        'openrouter' => 'OpenRouter API',
        _ => id,
      };

  static String _statusLabel(AppLocalizations l, String s) => switch (s) {
        'applied' => l.reviewStatusApplied,
        'dismissed' => l.reviewStatusDismissed,
        _ => s,
      };
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.checked, required this.onChanged});
  final ProposedLine line;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final e = line.entry;
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: checked,
      onChanged: (v) => onChanged(v ?? false),
      title: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 48, child: Text(e.date, style: t.labelLarge?.copyWith(color: scheme.outline))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (e.tags.isNotEmpty || e.projects.isNotEmpty)
              Wrap(spacing: 6, children: [
                for (final tag in e.tags) Text(tagLabel(tag), style: t.labelSmall?.copyWith(color: tagColor(scheme, tag))),
                for (final p in e.projects) Text(p, style: t.labelMedium?.copyWith(color: scheme.primary)),
              ]),
            Text.rich(inlineSpan(context, e.text, base: t.bodyMedium)),
            if (e.source != null) Text(context.l10n.logSource(e.source!), style: t.bodySmall?.copyWith(color: scheme.outline)),
          ]),
        ),
      ]),
    );
  }
}

/// A project page or summary: new or changed, with the proposed text (and the current one) behind
/// an expander. Without [onChanged] the tile has no checkbox (summaries toggle as a group).
class _FileTile extends StatelessWidget {
  const _FileTile({required this.title, required this.badge, required this.before, required this.after, this.checked, this.onChanged});
  final String title;
  final String badge;
  final String? before;
  final String after;
  final bool? checked;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: onChanged == null ? null : Checkbox(value: checked, onChanged: (v) => onChanged!(v ?? false)),
        title: Row(children: [
          Flexible(child: Text(title, style: t.titleSmall)),
          const SizedBox(width: 8),
          Chip(label: Text(badge), visualDensity: VisualDensity.compact, labelStyle: t.labelSmall),
        ]),
        subtitle: Text('${context.l10n.reviewLineCount(after.split('\n').length)}${before != null ? ' ${context.l10n.reviewPrevLineCount(before!.split('\n').length)}' : ''}', style: t.bodySmall),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.reviewProposed, style: t.labelLarge?.copyWith(color: scheme.primary)),
          MarkdownView(after),
          if (before != null) ...[
            const Divider(),
            Text(context.l10n.reviewCurrent, style: t.labelLarge?.copyWith(color: scheme.outline)),
            Opacity(opacity: 0.65, child: MarkdownView(before!)),
          ],
        ],
      ),
    );
  }
}
