import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
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
  String? _notice; // the last run's failure, shown once until dismissed

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
    return () => period == null ? Future.error(ApiException(404, '리포트가 없습니다')) : widget.api.report(kind, period);
  }

  Future<void> _refresh({bool initial = false, ReportRunning? justFinished}) async {
    try {
      final s = await widget.api.reports();
      if (!mounted) return;
      setState(() {
        _status = s;
        _error = null;
        if (initial && s.of(_kind).isEmpty) {
          // open on whatever exists (the monthly summaries, typically)
          _kind = reportKinds.firstWhere((k) => s.of(k).isNotEmpty, orElse: () => 'daily');
        }
        if (justFinished != null && reportKinds.contains(justFinished.kind)) {
          _kind = justFinished.kind;
          _period = justFinished.period;
          final run = s.lastRun[justFinished.kind];
          if (run != null && !run.ok && run.period == justFinished.period) _notice = run.error ?? '리포트 생성에 실패했습니다.';
        }
        final entries = s.of(_kind);
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
      final entries = _status?.of(kind) ?? const [];
      _period = period != null && entries.any((e) => e.period == period) ? period : (entries.isEmpty ? null : entries.first.period);
      _load = _loader();
    });
  }

  Future<void> _run(String kind, String? period) async {
    setState(() => _notice = null);
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
    final entries = status.of(_kind);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final running = status.running;
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
            tooltip: '리포트 설정',
            isSelected: _settingsOpen,
            icon: const Icon(Icons.tune),
            onPressed: () => setState(() => _settingsOpen = !_settingsOpen),
          ),
        ]),
      ),
      if (status.agents.isNotEmpty) _AgentLine(status: status),
      if (running != null) _RunningBar(running: running),
      if (_notice != null)
        MaterialBanner(
          content: Text(_notice!),
          leading: const Icon(Icons.error_outline),
          actions: [TextButton(onPressed: () => setState(() => _notice = null), child: const Text('닫기'))],
        ),
      if (_settingsOpen)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _SettingsPanel(settings: status.settings, onSave: _saveSettings, api: widget.api),
        ),
      const Divider(height: 1),
      Expanded(
        child: entries.isEmpty
            ? EmptyPane(
                '아직 ${reportKindLabel(_kind)} 리포트가 없습니다.\n"지금 만들기"로 바로 만들거나, 설정(⚙︎)에서 요일을 켜 두면 매일 수집 뒤 자동으로 만듭니다.',
                icon: Icons.summarize_outlined,
              )
            : wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SizedBox(width: 220, child: _PeriodList(entries: entries, selected: _period, onSelect: (p) => _select(_kind, p))),
                    const VerticalDivider(width: 1),
                    Expanded(child: _ReportBody(load: _load, onOpenProject: widget.onOpenProject, onRemake: running == null ? () => _run(_kind, _period) : null)),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: DropdownButton<String>(
                        value: _period,
                        isExpanded: true,
                        items: [for (final e in entries) DropdownMenuItem(value: e.period, child: Text(e.period))],
                        onChanged: (p) => _select(_kind, p),
                      ),
                    ),
                    Expanded(child: _ReportBody(load: _load, onOpenProject: widget.onOpenProject, onRemake: running == null ? () => _run(_kind, _period) : null)),
                  ]),
      ),
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
        label: const Text('지금 만들기'),
      ),
    );
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
      text = '리포트는 ${chosen.title}가 씁니다 · ${chosen.detail}';
      warn = false;
    } else if (signedOut.isNotEmpty) {
      text = signedOut.map((a) => '${a.title}: ${a.loginNote}').join(' · ');
      warn = true;
    } else {
      text = '쓸 수 있는 에이전트가 없습니다. Claude Code·Codex·Gemini CLI 중 하나를 설치하거나 설정에서 OpenRouter 키를 저장하세요.';
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
        Text('${reportKindLabel(running.kind)} 리포트 ${running.period} 만드는 중… ${running.agent == null ? '' : '(${running.agent})'} 수십 초에서 몇 분 걸립니다.', style: t.bodySmall),
        const SizedBox(height: 6),
        const LinearProgressIndicator(),
      ]),
    );
  }
}

class _PeriodList extends StatelessWidget {
  const _PeriodList({required this.entries, required this.selected, required this.onSelect});
  final List<ReportEntry> entries;
  final String? selected;
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
            subtitle: Text(e.createdAt == null ? (e.agent ?? '정리') : '${e.createdAt!.toLocal().toString().substring(0, 16)}${e.agent == null ? '' : ' · ${e.agent}'}', style: t.bodySmall),
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
              TextButton.icon(onPressed: onRemake, icon: const Icon(Icons.refresh, size: 16), label: const Text('다시 만들기')),
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
    return Panel(children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('일간 리포트'),
        subtitle: Text('고른 요일의 하루를 그날 수집 뒤에 정리합니다 (아침에 돌면 전날).', style: t.bodySmall),
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
          for (final p in const [('weekdays', '주중'), ('weekend', '주말'), ('everyday', '매일')])
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
        title: const Text('주간 리포트'),
        subtitle: Text('고른 요일에 그 전날이 든 주(월~일)를 정리합니다. 월요일이면 지난주.', style: t.bodySmall),
        value: settings.weeklyEnabled,
        onChanged: (v) => onSave(() => api.updateReportSettings(weeklyEnabled: v)),
        secondary: DropdownButton<String>(
          value: settings.weeklyDay,
          items: [for (final d in weekdayCodes) DropdownMenuItem(value: d, child: Text('${weekdayLabel(d)}요일'))],
          onChanged: (d) => d == null ? null : onSave(() => api.updateReportSettings(weeklyDay: d)),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('월간 리포트'),
        subtitle: Text('매달 고른 날에 지난달을 정리합니다 (summaries/YYYY-MM.md, 월간 정리 자리).', style: t.bodySmall),
        value: settings.monthlyEnabled,
        onChanged: (v) => onSave(() => api.updateReportSettings(monthlyEnabled: v)),
        secondary: DropdownButton<int>(
          value: settings.monthlyDay.clamp(1, 28),
          items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('$d일'))],
          onChanged: (d) => d == null ? null : onSave(() => api.updateReportSettings(monthlyDay: d)),
        ),
      ),
    ]);
  }
}
