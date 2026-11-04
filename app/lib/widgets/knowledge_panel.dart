import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import 'input_dialogs.dart' show toast;

/// "지식화 현황": the one thing to do next, with its button, over the five steps from collection to reports.
/// [compact] shows only the next-step line (the chat's empty state).
class KnowledgePanel extends StatefulWidget {
  const KnowledgePanel({
    super.key,
    required this.api,
    required this.onReview,
    this.onOpenConnect,
    this.onOpenSettings,
    this.onOpenReports,
    this.onChanged,
    this.compact = false,
    this.poll = const Duration(seconds: 5),
  });
  final WorklogApi api;

  /// Opens a proposal for review; resolves true when it was applied or dismissed.
  final Future<bool> Function(String id) onReview;
  final VoidCallback? onOpenConnect;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenReports;

  /// After a review was applied (the memory views reload).
  final VoidCallback? onChanged;
  final bool compact;
  final Duration poll;

  @override
  State<KnowledgePanel> createState() => _KnowledgePanelState();
}

class _KnowledgePanelState extends State<KnowledgePanel> {
  KnowledgeStatus? _s;
  Timer? _timer;
  bool _busy = false;
  bool _steps = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.knowledge();
      if (!mounted) return;
      setState(() => _s = s);
      _timer?.cancel();
      if (s.digestRunning) _timer = Timer(widget.poll, _load);
    } catch (_) {
      // an older server without /api/knowledge, or a moment offline: the panel stays out of the way
    }
  }

  /// Collects what is new and turns every day since the last digest into log lines (the server's daily scope).
  Future<void> _digest() async {
    setState(() => _busy = true);
    try {
      await widget.api.runDigest();
      if (mounted) toast(context, context.l10n.knDigestStarted);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  Future<void> _act(KnowledgeNext next) async {
    final s = _s!;
    switch (next) {
      case KnowledgeNext.review:
        final changed = await widget.onReview(s.review.first.id);
        if (changed) widget.onChanged?.call();
        await _load();
      case KnowledgeNext.digest:
        await _digest();
      case KnowledgeNext.collectFailed || KnowledgeNext.nothingCollected:
        widget.onOpenConnect?.call();
      case KnowledgeNext.noAgent:
        widget.onOpenSettings?.call();
      case KnowledgeNext.reports:
        widget.onOpenReports?.call();
      case KnowledgeNext.digestRunning || KnowledgeNext.allSet:
        break;
    }
  }

  String _line(AppLocalizations l, KnowledgeStatus s, KnowledgeNext next) {
    switch (next) {
      case KnowledgeNext.digestRunning:
        return l.knNextRunning;
      case KnowledgeNext.review:
        final created = s.review.first.createdAt;
        final days = created == null ? 0 : DateTime.now().difference(created).inDays;
        return days > 0 ? l.knNextReview(days, s.reviewLines, s.reviewProjects) : l.knNextReviewToday(s.reviewLines, s.reviewProjects);
      case KnowledgeNext.collectFailed:
        return l.knNextCollectFailed;
      case KnowledgeNext.nothingCollected:
        return l.knNextNothing;
      case KnowledgeNext.noAgent:
        return l.knNextNoAgent;
      case KnowledgeNext.digest:
        return l.knNextDigest(s.waitingSourceDays, s.waitingFiles);
      case KnowledgeNext.reports:
        return l.knNextReports;
      case KnowledgeNext.allSet:
        if (s.daily) return l.knNextAllSetDaily;
        return s.weekly && s.nextWeekly != null ? l.knNextAllSetWhen(s.nextWeekly!) : l.knNextAllSet;
    }
  }

  String? _action(AppLocalizations l, KnowledgeNext next) => switch (next) {
        KnowledgeNext.review => l.knActionReview,
        KnowledgeNext.digest => l.knActionDigest,
        KnowledgeNext.collectFailed || KnowledgeNext.nothingCollected => widget.onOpenConnect == null ? null : l.knActionConnect,
        KnowledgeNext.noAgent => widget.onOpenSettings == null ? null : l.knActionSettings,
        KnowledgeNext.reports => widget.onOpenReports == null ? null : l.knActionReports,
        KnowledgeNext.digestRunning || KnowledgeNext.allSet => null,
      };

  /// The step the next action is about, highlighted in the strip.
  static int _stepOf(KnowledgeNext next) => switch (next) {
        KnowledgeNext.collectFailed || KnowledgeNext.nothingCollected => 0,
        KnowledgeNext.digestRunning || KnowledgeNext.noAgent || KnowledgeNext.digest => 1,
        KnowledgeNext.review => 2,
        KnowledgeNext.allSet => 3,
        KnowledgeNext.reports => 4,
      };

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const SizedBox.shrink();
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final next = knowledgeNext(s);
    final action = _action(l, next);
    final urgent = next == KnowledgeNext.review || next == KnowledgeNext.collectFailed || next == KnowledgeNext.noAgent;
    final line = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      if (next == KnowledgeNext.digestRunning)
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
      else
        Icon(next == KnowledgeNext.allSet ? Icons.check_circle_outline : Icons.flag_outlined, size: 20, color: urgent ? scheme.error : scheme.primary),
      const SizedBox(width: 10),
      Expanded(child: Text(_line(l, s, next), style: t.bodyMedium)),
      if (action != null) ...[
        const SizedBox(width: 10),
        FilledButton(
          onPressed: _busy ? null : () => _act(next),
          child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(action),
        ),
      ],
    ]);
    if (widget.compact) return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: line));

    final current = _stepOf(next);
    String day(String? d) => d == null ? l.knNone : d.substring(5);
    final reportKinds = [if (s.monthlyReports) l.knKindMonthly, if (s.weeklyReports) l.knKindWeekly, if (s.dailyReports) l.knKindDaily];
    final steps = [
      (l.knStepCollect, l.knCollectValue(s.collectDays), s.latestDay == null ? l.knNone : l.knLatest(day(s.latestDay))),
      (
        l.knStepWaiting,
        s.waitingFiles > 0 ? '${l.knWaitingValue(s.waitingSourceDays)} · ${l.knWaitingFiles(s.waitingFiles)}' : l.knWaitingValue(s.waitingSourceDays),
        s.lastDigest == null ? l.knNeverDigested : l.knLastDigest(day(s.lastDigest)),
      ),
      (l.knStepReview, s.review.isEmpty ? l.knReviewNone : l.knReviewValue(s.reviewLines, s.reviewProjects), ''),
      (l.knStepKnowledge, l.knKnowledgeValue(s.logLines), l.knKnowledgeSub(s.projects, s.summaries)),
      (l.knStepReports, l.knReportsValue(s.monthlyCount, s.weeklyCount, s.dailyCount), reportKinds.isEmpty ? l.knReportsOff : l.knReportsOn(reportKinds.join('·'))),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Material(
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: urgent ? scheme.error.withValues(alpha: 0.5) : scheme.outlineVariant)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text(l.knTitle, style: t.labelLarge?.copyWith(color: scheme.outline)),
              const Spacer(),
              // "지금 정리" is always one click away, not only when the material has piled up
              if (s.agent != null && next != KnowledgeNext.digest && next != KnowledgeNext.digestRunning)
                TextButton.icon(onPressed: _busy ? null : _digest, icon: const Icon(Icons.auto_awesome, size: 16), label: Text(l.knActionDigest)),
              TextButton(onPressed: () => setState(() => _steps = !_steps), child: Text(_steps ? l.knHideSteps : l.knShowSteps)),
            ]),
            Padding(padding: const EdgeInsets.only(right: 6), child: line),
            if (_steps) ...[
              const SizedBox(height: 10),
              LayoutBuilder(builder: (context, box) {
                final cells = [
                  for (var i = 0; i < steps.length; i++)
                    _Step(index: i + 1, title: steps[i].$1, value: steps[i].$2, sub: steps[i].$3, current: i == current, urgent: i == current && urgent),
                ];
                if (box.maxWidth < 640) return Wrap(spacing: 8, runSpacing: 8, children: [for (final c in cells) SizedBox(width: (box.maxWidth - 8) / 2 - 1, child: c)]);
                return IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < cells.length; i++) ...[
                      if (i > 0) Icon(Icons.chevron_right, size: 16, color: scheme.outline),
                      Expanded(child: cells[i]),
                    ],
                  ]),
                );
              }),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.title, required this.value, required this.sub, required this.current, required this.urgent});
  final int index;
  final String title;
  final String value;
  final String sub;
  final bool current;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final accent = urgent ? scheme.error : scheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: current ? accent.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: current ? accent.withValues(alpha: 0.6) : scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$index  $title', style: t.labelMedium?.copyWith(color: current ? accent : scheme.outline)),
        const SizedBox(height: 2),
        Text(value, style: t.bodyMedium?.copyWith(fontWeight: current ? FontWeight.w600 : null)),
        if (sub.isNotEmpty) Text(sub, style: t.bodySmall?.copyWith(color: scheme.outline)),
      ]),
    );
  }
}
