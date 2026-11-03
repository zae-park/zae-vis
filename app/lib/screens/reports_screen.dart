import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import '../widgets/agent_rail.dart';
import '../widgets/common.dart';
import '../widgets/markdown_view.dart';

/// "리포트": the daily / weekly / monthly write-ups an agent makes from the worklog. Kinds on top,
/// periods on the left (a dropdown when narrow), the report on the right, "지금 만들기" for any
/// period, and a settings panel for which days the daily job writes which report.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.api, required this.onOpenProject, this.clock});
  final WorklogApi api;
  final void Function(String slug) onOpenProject;

  /// "오늘"/"이번 주" are computed from this (tests pin it).
  final DateTime Function()? clock;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportsStatus? _status;
  Object? _error;
  String _kind = 'daily';
  String? _period;
  bool _settingsOpen = false;
  Timer? _poll;

  // What the body shows: a new load each time kind/period changes (AsyncView reloads when the closure changes).
  late Future<Report> Function() _load = _loader();

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _refresh(initial: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<Report> Function() _loader() {
    final kind = _kind;
    final period = _period;
    return () => period == null ? Future.error(ApiException(404, l10nNow.reportsNone)) : widget.api.report(kind, period);
  }

  Future<void> _refresh({bool initial = false, ReportRunning? justFinished}) async {
    try {
      final s = await widget.api.reports();
      if (!mounted) return;
      setState(() {
        _status = s;
        _error = null;
        if (initial && _periodsOf(s, _kind).isEmpty) {
          // open on whatever exists (a failed attempt counts; otherwise the monthly summaries)
          _kind = reportKinds.firstWhere((k) => _periodsOf(s, k).isNotEmpty, orElse: () => 'daily');
        }
        if (justFinished != null && reportKinds.contains(justFinished.kind)) {
          _kind = justFinished.kind;
          _period = justFinished.period;
        }
        final entries = _periodsOf(s, _kind);
        if (_period == null || !entries.any((e) => e.period == _period)) _period = entries.isEmpty ? null : entries.first.period;
        _load = _loader();
      });
      if (s.running != null) _startPolling(s.running!);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  void _startPolling(ReportRunning running) {
    if (_poll != null) return;
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      ReportsStatus s;
      try {
        s = await widget.api.reports();
      } catch (_) {
        return;
      }
      if (!mounted) return;
      if (s.running == null) {
        _poll?.cancel();
        _poll = null;
        await _refresh(justFinished: running);
      } else {
        setState(() => _status = s);
      }
    });
  }

  void _select(String kind, [String? period]) {
    setState(() {
      _kind = kind;
      final entries = _status == null ? const <ReportEntry>[] : _periodsOf(_status!, kind);
      _period = period != null && entries.any((e) => e.period == period) ? period : (entries.isEmpty ? null : entries.first.period);
      _load = _loader();
    });
  }

  Future<void> _run(String kind, String? period) async {
    try {
      final made = await widget.api.runReport(kind, period: period);
      if (!mounted) return;
      final running = ReportRunning(kind: kind, period: made);
      setState(() {
        _status = ReportsStatus(
          settings: _status?.settings ?? const ReportSettings(),
          reports: _status?.reports ?? const {},
          running: running,
          lastRun: _status?.lastRun ?? const {},
          defaults: _status?.defaults ?? const {},
          agents: _status?.agents ?? const [],
          chosen: _status?.chosen,
        );
      });
      _startPolling(running);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _saveSettings(Future<ReportsStatus> Function() save) async {
    try {
      final s = await save();
      if (mounted) setState(() => _status = s);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null) return _error == null ? const Center(child: CircularProgressIndicator()) : ErrorPane(error: _error!, onRetry: () => _refresh(initial: true));
    final entries = _periodsOf(status, _kind);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final running = status.running;
    final failed = status.lastRun[_kind];
    final failedHere = failed != null && !failed.ok && failed.period == _period;
    final hasFile = status.of(_kind).any((e) => e.period == _period);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Row(children: [
          SegmentedButton<String>(
            segments: [for (final k in reportKinds) ButtonSegment(value: k, label: Text(reportKindLabel(k)))],
            selected: {_kind},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => _select(s.first),
          ),
          const Spacer(),
          _MakeNowButton(now: _now, enabled: running == null, onPick: _run),
          const SizedBox(width: 4),
          IconButton(
            tooltip: context.l10n.reportsSettings,
            isSelected: _settingsOpen,
            icon: const Icon(Icons.tune),
            onPressed: () => setState(() => _settingsOpen = !_settingsOpen),
          ),
        ]),
      ),
      if (status.agents.isNotEmpty) _AgentLine(status: status),
      if (!(failedHere && failed.rail.isNotEmpty))
        if (_reportRail(status, running, _kind, _period) case final rail?) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 4), child: AgentRail(stops: rail)),
      if (running != null) _RunningBar(running: running),
      if (_settingsOpen)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _SettingsPanel(settings: status.settings, onSave: _saveSettings, api: widget.api),
        ),
      const Divider(height: 1),
      Expanded(child: _body(entries, wide, running, failedHere ? failed : null, hasFile)),
    ]);
  }

  Widget _body(List<ReportEntry> entries, bool wide, ReportRunning? running, ReportRun? failedHere, bool hasFile) {
    if (entries.isEmpty) {
      return EmptyPane(
        context.l10n.reportsEmpty(reportKindWord(_kind)),
        icon: Icons.summarize_outlined,
      );
    }
    final remake = running == null ? () => _run(_kind, _period) : null;
    final report = _ReportBody(load: _load, onOpenProject: widget.onOpenProject, onRemake: remake);
    final card = failedHere == null ? null : _UnavailableCard(run: failedHere, onRemake: remake);
    final Widget pane;
    if (card != null && !hasFile) {
      pane = SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), child: card);
    } else if (card != null) {
      pane = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: card),
        Expanded(child: report),
      ]);
    } else {
      pane = report;
    }
    final unavailable = failedHere?.period;
    if (!wide) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: DropdownButton<String>(
            value: _period,
            isExpanded: true,
            items: [
              for (final e in entries)
                DropdownMenuItem(value: e.period, child: Text(e.period == unavailable ? context.l10n.reportsPeriodNoService(e.period) : e.period)),
            ],
            onChanged: (p) => _select(_kind, p),
          ),
        ),
        Expanded(child: pane),
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 220, child: _PeriodList(entries: entries, selected: _period, unavailable: unavailable, onSelect: (p) => _select(_kind, p))),
      const VerticalDivider(width: 1),
      Expanded(child: pane),
    ]);
  }
}

class _MakeNowButton extends StatelessWidget {
  const _MakeNowButton({required this.now, required this.enabled, required this.onPick});
  final DateTime now;
  final bool enabled;
  final void Function(String kind, String period) onPick;

  @override
  Widget build(BuildContext context) {
    final choices = ReportChoice.forNow(now);
    final t = Theme.of(context).textTheme;
    return MenuAnchor(
      menuChildren: [
        for (var i = 0; i < choices.length; i++) ...[
          if (i > 0 && choices[i].kind != choices[i - 1].kind) const Divider(height: 8),
          MenuItemButton(
            onPressed: () => onPick(choices[i].kind, choices[i].period),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(choices[i].label),
              Text('${reportKindLabel(choices[i].kind)} · ${choices[i].period}', style: t.bodySmall),
            ]),
          ),
        ],
      ],
      builder: (context, controller, _) => FilledButton.tonalIcon(
        onPressed: enabled ? () => controller.isOpen ? controller.close() : controller.open() : null,
        icon: const Icon(Icons.auto_awesome, size: 18),
        label: Text(context.l10n.reportsMakeNow),
      ),
    );
  }
}

/// Periods on disk, plus the latest failed attempt when it never wrote a file.
List<ReportEntry> _periodsOf(ReportsStatus status, String kind) {
  final files = status.of(kind);
  final last = status.lastRun[kind];
  if (last == null || last.ok || last.period.isEmpty || files.any((e) => e.period == last.period)) return files;
  final extra = ReportEntry(kind: kind, period: last.period, path: '', createdAt: last.at, agent: last.agent);
  return [...files, extra]..sort((a, b) => b.period.compareTo(a.period));
}

/// Live rail while a report is being written; the trail of a failed or quota-skipping run; otherwise who would write the next one.
List<RailStop>? _reportRail(ReportsStatus status, ReportRunning? running, String kind, String? period) {
  if (running != null && running.rail.isNotEmpty) return running.rail;
  final last = status.lastRun[kind];
  if (running == null && last != null && last.rail.isNotEmpty && (!last.ok || (last.period == period && last.rail.any((s) => s.state == 'quota')))) return last.rail;
  if (status.rail.isNotEmpty) return status.rail;
  return null;
}

/// The attempt stayed in the list, with why no service could write it.
class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({required this.run, this.onRemake});
  final ReportRun run;
  final VoidCallback? onRemake;

  bool get _noService {
    final wrote = run.rail.any((s) => s.state == 'wrote');
    return !wrote && (run.rail.any((s) => s.state == 'quota') || (run.error?.contains('넘길 서비스') ?? false));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Panel(divided: false, padding: const EdgeInsets.fromLTRB(16, 14, 16, 12), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline, color: scheme.error),
        const SizedBox(width: 10),
        Expanded(child: Text(_noService ? context.l10n.reportsNoServiceWas : context.l10n.reportsFailed, style: t.titleSmall)),
        TextButton.icon(onPressed: onRemake, icon: const Icon(Icons.refresh, size: 16), label: Text(context.l10n.reportsRemake)),
      ]),
      if (run.error != null && run.error!.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(run.error!, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
      if (run.rail.isNotEmpty) AgentRail(stops: run.rail),
    ]);
  }
}

/// Which agent writes the reports — or why none can right now (a CLI that only needs a login).
class _AgentLine extends StatelessWidget {
  const _AgentLine({required this.status});
  final ReportsStatus status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final chosen = status.chosenAgent;
    final signedOut = status.agents.where((a) => a.needsLogin).toList();
    final String text;
    final bool warn;
    if (chosen != null) {
      text = context.l10n.reportsWrittenBy(chosen.title, chosen.detail);
      warn = false;
    } else if (signedOut.isNotEmpty) {
      text = signedOut.map((a) => '${a.title}: ${a.loginNote}').join(' · ');
      warn = true;
    } else {
      text = context.l10n.reportsNoAgent;
      warn = true;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Text(text, style: t.bodySmall?.copyWith(color: warn ? scheme.error : scheme.outline)),
    );
  }
}

class _RunningBar extends StatelessWidget {
  const _RunningBar({required this.running});
  final ReportRunning running;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.l10n.reportsRunning(reportKindWord(running.kind), running.period, running.agent == null ? '' : '(${running.agent})'), style: t.bodySmall),
        const SizedBox(height: 6),
        const LinearProgressIndicator(),
      ]),
    );
  }
}

class _PeriodList extends StatelessWidget {
  const _PeriodList({required this.entries, required this.selected, required this.onSelect, this.unavailable});
  final List<ReportEntry> entries;
  final String? selected;
  final String? unavailable;
  final void Function(String period) onSelect;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (final e in entries)
          ListTile(
            dense: true,
            selected: e.period == selected,
            title: Text(e.period),
            subtitle: Text(
              e.period == unavailable ? context.l10n.reportsNoService : (e.createdAt == null ? (e.agent ?? context.l10n.reportsDigest) : '${e.createdAt!.toLocal().toString().substring(0, 16)}${e.agent == null ? '' : ' · ${e.agent}'}'),
              style: t.bodySmall,
            ),
            onTap: () => onSelect(e.period),
          ),
      ],
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.load, required this.onOpenProject, this.onRemake});
  final Future<Report> Function() load;
  final void Function(String slug) onOpenProject;
  final VoidCallback? onRemake;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return AsyncView<Report>(
      load: load,
      builder: (context, r, _) => Readable(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  [r.path, if (r.createdAt != null) r.createdAt!.toLocal().toString().substring(0, 16), if (r.agent != null) r.agent!].join(' · '),
                  style: t.bodySmall?.copyWith(color: scheme.outline),
                ),
              ),
              TextButton.icon(onPressed: onRemake, icon: const Icon(Icons.refresh, size: 16), label: Text(context.l10n.reportsRemake)),
            ]),
            const SizedBox(height: 4),
            MarkdownView(r.markdown, onLink: onOpenProject),
          ]),
        ),
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.settings, required this.onSave, required this.api});
  final ReportSettings settings;
  final WorklogApi api;
  final Future<void> Function(Future<ReportsStatus> Function() save) onSave;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final preset = settings.dailyPreset;
    final l = context.l10n;
    return Panel(children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l.reportsDaily),
        subtitle: Text(l.reportsDailyHint, style: t.bodySmall),
        value: settings.dailyEnabled,
        onChanged: (v) => onSave(() => api.updateReportSettings(dailyEnabled: v)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final d in weekdayCodes)
            FilterChip(
              label: Text(weekdayLabel(d)),
              selected: settings.dailyDays.contains(d),
              visualDensity: VisualDensity.compact,
              onSelected: (on) {
                final days = on ? [...settings.dailyDays, d] : settings.dailyDays.where((x) => x != d).toList();
                onSave(() => api.updateReportSettings(dailyDays: days));
              },
            ),
          const SizedBox(width: 10),
          for (final p in [('weekdays', l.reportsWeekdays), ('weekend', l.reportsWeekend), ('everyday', l.reportsEveryday)])
            ChoiceChip(
              label: Text(p.$2),
              selected: preset == p.$1,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onSave(() => api.updateReportSettings(dailyDays: weekdayPresets[p.$1]!)),
            ),
        ]),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l.reportsWeekly),
        subtitle: Text(l.reportsWeeklyHint, style: t.bodySmall),
        value: settings.weeklyEnabled,
        onChanged: (v) => onSave(() => api.updateReportSettings(weeklyEnabled: v)),
        secondary: DropdownButton<String>(
          value: settings.weeklyDay,
          items: [for (final d in weekdayCodes) DropdownMenuItem(value: d, child: Text(l.reportsWeekdayName(weekdayLabel(d))))],
          onChanged: (d) => d == null ? null : onSave(() => api.updateReportSettings(weeklyDay: d)),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l.reportsMonthly),
        subtitle: Text(l.reportsMonthlyHint, style: t.bodySmall),
        value: settings.monthlyEnabled,
        onChanged: (v) => onSave(() => api.updateReportSettings(monthlyEnabled: v)),
        secondary: DropdownButton<int>(
          value: settings.monthlyDay.clamp(1, 28),
          items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text(l.reportsMonthDay(d)))],
          onChanged: (d) => d == null ? null : onSave(() => api.updateReportSettings(monthlyDay: d)),
        ),
      ),
    ]);
  }
}
