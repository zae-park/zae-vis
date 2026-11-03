import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/input_dialogs.dart';
import '../widgets/markdown_view.dart';
import 'collect_screen.dart' show SourceIcon;
import 'file_screen.dart';
import 'log_screen.dart';
import '../widgets/knowledge_panel.dart';
import 'review_screen.dart';

/// 메모리: everything the app knows, in three layers — 기록 (the log lines, mine and the digest's),
/// 원본 (the collected day files and inbox material the lines came from) and 상태 (the project
/// pages the digest keeps). Wide windows show 상태 as a panel on the right.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key, required this.api, required this.onOpenProject, this.onOpenConnect, this.onOpenReports, this.onOpenSettings});
  final WorklogApi api;
  final void Function(String slug) onOpenProject;

  /// Where the knowledge panel's next step leads (the shell's tabs and settings).
  final VoidCallback? onOpenConnect;
  final VoidCallback? onOpenReports;
  final VoidCallback? onOpenSettings;

  static const panelBreakpoint = 1040.0;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

enum _Layer {
  log(Icons.list_alt_outlined),
  day(Icons.calendar_today_outlined),
  origins(Icons.inventory_2_outlined),
  projects(Icons.folder_outlined);

  const _Layer(this.icon);
  final IconData icon;

  String label(AppLocalizations l) => switch (this) {
        log => l.memoryLayerLog,
        day => l.memoryLayerDay,
        origins => l.memoryLayerOrigins,
        projects => l.memoryLayerProjects,
      };
}

class _MemoryScreenState extends State<MemoryScreen> {
  _Layer _layer = _Layer.log;
  // the knowledge panel says where things stand; the flow explanation is one tap away
  bool _showFlow = false;
  int _generation = 0; // bumped after a review is applied, so the layers read the worklog again

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= MemoryScreen.panelBreakpoint;
    final layers = wide ? [_Layer.log, _Layer.day, _Layer.origins] : _Layer.values;
    if (wide && _layer == _Layer.projects) _layer = _Layer.log;
    final main = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          SegmentedButton<_Layer>(
            segments: [for (final l in layers) ButtonSegment(value: l, label: Text(l.label(context.l10n)), icon: Icon(l.icon, size: 18))],
            selected: {_layer},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => setState(() => _layer = s.first),
          ),
          const Spacer(),
          IconButton(
            tooltip: _showFlow ? context.l10n.memoryHideFlow : context.l10n.memoryShowFlow,
            icon: Icon(_showFlow ? Icons.info : Icons.info_outline),
            onPressed: () => setState(() => _showFlow = !_showFlow),
          ),
        ]),
      ),
      KnowledgePanel(
        api: widget.api,
        onReview: (id) => ReviewScreen.open(context, widget.api, id),
        onOpenConnect: widget.onOpenConnect,
        onOpenReports: widget.onOpenReports,
        onOpenSettings: widget.onOpenSettings,
        onChanged: () => setState(() => _generation++),
      ),
      if (_showFlow) _FlowStrip(layer: _layer),
      Expanded(
        key: ValueKey(_generation),
        child: switch (_layer) {
          _Layer.log => LogScreen(api: widget.api, onOpenProject: widget.onOpenProject),
          _Layer.day => _DayView(api: widget.api),
          _Layer.origins => _OriginsView(api: widget.api),
          _Layer.projects => _ProjectsPanel(api: widget.api, onOpen: widget.onOpenProject, asPanel: false),
        },
      ),
    ]);
    if (!wide) return main;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: main),
      SizedBox(width: 320, child: _ProjectsPanel(api: widget.api, onOpen: widget.onOpenProject, asPanel: true)),
    ]);
  }
}

/// One line on how memory flows: what I write → what the digest adds → what everything is used for.
class _FlowStrip extends StatelessWidget {
  const _FlowStrip({required this.layer});
  final _Layer layer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    final steps = switch (layer) {
      _Layer.log => [
          (Icons.lock_outline, l.memoryMine, l.memoryFlowMineBody),
          (Icons.auto_awesome, l.memoryFlowDigestTitle, l.memoryFlowDigestBody),
          (Icons.search, l.memoryFlowUseTitle, l.memoryFlowUseBody),
        ],
      _Layer.day => [
          (Icons.calendar_today_outlined, l.memoryFlowSameDayTitle, l.memoryFlowSameDayBody),
          (Icons.link, l.memoryLinked, l.memoryFlowLinkedBody),
          (Icons.inventory_2_outlined, l.memoryFlowOneRecordTitle, l.memoryFlowOneRecordBody),
        ],
      _Layer.origins => [
          (Icons.download_outlined, l.memoryFlowDailyTitle, l.memoryFlowDailyBody),
          (Icons.auto_awesome, l.logDigest, l.memoryFlowDigestStepBody),
          (Icons.search, l.commonSearch, l.memoryFlowSearchBody),
        ],
      _Layer.projects => [
          (Icons.folder_outlined, l.memoryFlowProjectPagesTitle, l.memoryFlowProjectPagesBody),
          (Icons.link, l.memoryFlowLinkTitle, l.memoryFlowLinkBody),
        ],
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(10), border: Border.all(color: scheme.outlineVariant)),
        child: Wrap(spacing: 18, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) Icon(Icons.arrow_forward, size: 14, color: scheme.outline),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(steps[i].$1, size: 15, color: scheme.primary),
              const SizedBox(width: 5),
              Text(steps[i].$2, style: t.labelLarge),
              const SizedBox(width: 6),
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: Text(steps[i].$3, style: t.bodySmall)),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// The collected material, by day: a row per date with a chip per file, and how many log lines
/// cite that day's material.
class _OriginsView extends StatefulWidget {
  const _OriginsView({required this.api});
  final WorklogApi api;

  @override
  State<_OriginsView> createState() => _OriginsViewState();
}

class _OriginsViewState extends State<_OriginsView> {
  late Future<(List<OriginFile>, List<LogEntry>)> _future = _load();
  final Set<String> _sources = {};

  Future<(List<OriginFile>, List<LogEntry>)> _load() async {
    final files = await widget.api.origins();
    // the lines that cite material: the newest two months are enough to count citations per day
    final months = (await widget.api.logMonths()).take(2);
    final entries = <LogEntry>[];
    for (final m in months) {
      entries.addAll(await widget.api.log(m));
    }
    return (files, entries);
  }

  static int citations(OriginFile f, List<LogEntry> entries) => entries.where((e) => lineCitesFile(e, f)).length;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<(List<OriginFile>, List<LogEntry>)>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return ErrorPane(error: snap.error!, onRetry: () => setState(() => _future = _load()));
        final (files, entries) = snap.data!;
        if (files.isEmpty) return EmptyPane(context.l10n.memoryOriginsEmpty);
        final sources = <String, String>{for (final f in files) f.source: f.sourceLabel};
        final shown = files.where((f) => _sources.isEmpty || _sources.contains(f.source)).toList();
        final byDate = <String, List<OriginFile>>{};
        for (final f in shown) {
          byDate.putIfAbsent(f.date, () => []).add(f);
        }
        final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final e in sources.entries)
                FilterChip(
                  avatar: SourceIcon(e.key, size: 18),
                  label: Text(e.value),
                  selected: _sources.contains(e.key),
                  visualDensity: VisualDensity.compact,
                  onSelected: (on) => setState(() => on ? _sources.add(e.key) : _sources.remove(e.key)),
                ),
              Text(context.l10n.memoryOriginsCount(shown.length, dates.length), style: t.labelMedium?.copyWith(color: scheme.outline)),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: dates.length,
              itemBuilder: (context, i) {
                final d = dates[i];
                final day = byDate[d]!;
                final cited = day.fold(0, (n, f) => n + citations(f, entries));
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 104,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(d, style: t.labelLarge),
                        Text(cited > 0 ? context.l10n.memoryCitedBy(cited) : context.l10n.memoryNotDigested, style: t.labelSmall?.copyWith(color: cited > 0 ? scheme.primary : scheme.outline)),
                      ]),
                    ),
                    Expanded(
                      child: Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final f in day) _OriginChip(file: f, cited: citations(f, entries), onOpen: () => FileScreen.open(context, widget.api, f.path)),
                      ]),
                    ),
                  ]),
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}

class _OriginChip extends StatelessWidget {
  const _OriginChip({required this.file, required this.cited, required this.onOpen});
  final OriginFile file;
  final int cited;
  final VoidCallback onOpen;

  static String _size(int b) => b >= 1 << 20 ? '${(b / (1 << 20)).toStringAsFixed(1)}MB' : '${(b / 1024).ceil()}KB';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final label = file.source == 'transcripts' || file.source == 'session-notes' ? file.name.replaceAll(RegExp(r'\.(md|txt)$'), '').replaceFirst(RegExp(r'^\d{4}-\d{2}-\d{2}[_ ]?'), '') : file.sourceLabel;
    return Tooltip(
      message: '${file.path} · ${_size(file.bytes)}${file.kind == 'inbox' ? ' · ${context.l10n.memoryInboxPending}' : file.kind == 'processed' ? ' · ${context.l10n.memoryProcessed}' : ''}',
      child: Material(
        color: scheme.surface,
        shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SourceIcon(file.source, size: 18),
              const SizedBox(width: 6),
              Text(label.isEmpty ? file.name : label, style: t.labelMedium),
              if (cited > 0) ...[
                const SizedBox(width: 6),
                Text('$cited', style: t.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// A log line's `(src: …)` names this collected file.
bool lineCitesFile(LogEntry e, OriginFile f) {
  final s = e.source;
  if (s == null) return false;
  final base = f.name.replaceAll(RegExp(r'\.(md|txt)$'), '');
  // agent-sessions replaced claude-code: a line may cite either name for the same day
  final twin = f.source == 'agent-sessions' ? 'claude-code' : f.source == 'claude-code' ? 'agent-sessions' : null;
  if (s.contains('${f.source} ${f.date}') || (twin != null && s.contains('$twin ${f.date}')) || (f.source == 'shell-history' && s.contains('shell ${f.date}'))) return true;
  return (f.source == 'transcripts' || f.source == 'session-notes') && s.contains(base);
}

/// A log line plus the month file it lives in, so `10-08` becomes `2026-10-08`.
class _DatedLine {
  const _DatedLine(this.month, this.entry);
  final String month;
  final LogEntry entry;

  /// `log/2026-10.md` stores the day as `10-06`, so the year comes from the file.
  String get day {
    final d = entry.date;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d)) return d;
    if (RegExp(r'^\d{2}-\d{2}$').hasMatch(d) && RegExp(r'^\d{4}-\d{2}$').hasMatch(month)) return '${month.substring(0, 4)}-$d';
    return '';
  }
}

/// One date: my lines, the collected files, and digest lines that belong to that date.
class _DayBundle {
  _DayBundle(this.date);
  final String date;
  final mine = <_DatedLine>[];
  final fromSources = <_DatedLine>[];
  final files = <OriginFile>[];

  bool get linked => fromSources.any((l) => files.any((f) => lineCitesFile(l.entry, f)));

  String note(AppLocalizations l) {
    if (mine.isNotEmpty && files.isNotEmpty && linked) return l.memoryNoteMineFilesLinked;
    if (mine.isNotEmpty && files.isNotEmpty) return l.memoryNoteMineFiles;
    if (linked) return l.memoryNoteLinked;
    if (mine.isNotEmpty && files.isEmpty) return l.memoryNoteMineOnly;
    if (files.isNotEmpty && fromSources.isEmpty) return l.memoryNoteFilesOnly;
    if (files.isNotEmpty && fromSources.isNotEmpty) return l.memoryNoteFilesDigest;
    return l.memoryNoteDigestOnly;
  }
}

List<_DayBundle> dayBundles(List<OriginFile> files, List<_DatedLine> lines) {
  final days = <String, _DayBundle>{};
  _DayBundle of(String d) => days.putIfAbsent(d, () => _DayBundle(d));
  for (final f in files) {
    if (f.date.isNotEmpty) of(f.date).files.add(f);
  }
  for (final line in lines) {
    final own = line.day;
    if (!line.entry.byClaude) {
      if (own.isNotEmpty) of(own).mine.add(line);
      continue;
    }
    final homes = <String>{if (own.isNotEmpty) own, for (final f in files) if (f.date.isNotEmpty && lineCitesFile(line.entry, f)) f.date};
    for (final d in homes) {
      of(d).fromSources.add(line);
    }
  }
  return days.values.toList()..sort((a, b) => b.date.compareTo(a.date));
}

/// One card per day, so a one-line note and that day's collected files are visibly one record.
class _DayView extends StatefulWidget {
  const _DayView({required this.api});
  final WorklogApi api;

  @override
  State<_DayView> createState() => _DayViewState();
}

class _DayViewState extends State<_DayView> {
  late Future<(List<OriginFile>, List<_DatedLine>)> _future = _load();

  Future<(List<OriginFile>, List<_DatedLine>)> _load() async {
    final files = await widget.api.origins();
    final lines = <_DatedLine>[];
    for (final m in await widget.api.logMonths()) {
      for (final e in await widget.api.log(m)) {
        lines.add(_DatedLine(m, e));
      }
    }
    return (files, lines);
  }

  Future<void> _openOrigin(LogEntry entry) async {
    final src = entry.source;
    if (src == null) return;
    List<String> paths = const [];
    try {
      paths = await widget.api.origin(src);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
      return;
    }
    if (!mounted) return;
    if (paths.isEmpty) {
      toast(context, context.l10n.logOriginNotFound(src));
      return;
    }
    FileScreen.open(context, widget.api, paths.first);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<(List<OriginFile>, List<_DatedLine>)>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return ErrorPane(error: snap.error!, onRetry: () => setState(() => _future = _load()));
        final (files, lines) = snap.data!;
        final days = dayBundles(files, lines);
        if (days.isEmpty) return EmptyPane(context.l10n.memoryDayEmpty);
        final mine = lines.where((l) => !l.entry.byClaude).length;
        final digest = lines.where((l) => l.entry.byClaude).length;
        final together = days.where((d) => d.mine.isNotEmpty && d.files.isNotEmpty).length;
        final linked = days.where((d) => d.linked).length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '${context.l10n.memoryDaySummary(mine, digest, files.length)}'
              '${together > 0 ? ' · ${context.l10n.memoryDayTogether(together)}' : ''}'
              '${linked > 0 ? ' · ${context.l10n.memoryDayLinked(linked)}' : ''}',
              style: t.labelMedium?.copyWith(color: scheme.outline),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _DayCard(day: days[i], onOpenFile: (f) => FileScreen.open(context, widget.api, f.path), onOpenLine: _openOrigin),
            ),
          ),
        ]);
      },
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.onOpenFile, required this.onOpenLine});
  final _DayBundle day;
  final void Function(OriginFile file) onOpenFile;
  final void Function(LogEntry entry) onOpenLine;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final joined = day.mine.isNotEmpty && day.files.isNotEmpty;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(day.date, style: t.titleSmall),
            const Spacer(),
            Text(joined ? context.l10n.memoryJoined : day.linked ? context.l10n.memoryLinked : context.l10n.memoryOneSide, style: t.labelSmall?.copyWith(color: joined || day.linked ? scheme.primary : scheme.outline)),
          ]),
          const SizedBox(height: 2),
          Text(day.note(context.l10n), style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          if (day.mine.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(context.l10n.memoryMine, style: t.labelSmall?.copyWith(color: scheme.outline)),
            for (final l in day.mine) Padding(padding: const EdgeInsets.only(top: 2), child: Text(l.entry.text, style: t.bodyMedium)),
          ],
          if (day.files.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(context.l10n.memoryCollected, style: t.labelSmall?.copyWith(color: scheme.outline)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final f in day.files) _OriginChip(file: f, cited: day.fromSources.where((l) => lineCitesFile(l.entry, f)).length, onOpen: () => onOpenFile(f)),
            ]),
          ],
          if (day.fromSources.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(day.linked ? context.l10n.memoryLinesFromFiles : context.l10n.memoryDayDigest, style: t.labelSmall?.copyWith(color: scheme.outline)),
            for (final l in day.fromSources)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(l.entry.text, style: t.bodyMedium),
                  if (l.entry.source != null)
                    InkWell(
                      onTap: () => onOpenLine(l.entry),
                      child: Text(context.l10n.logSource(l.entry.source!), style: t.bodySmall?.copyWith(color: scheme.primary, decoration: TextDecoration.underline, decorationColor: scheme.primary.withValues(alpha: 0.4))),
                    ),
                ]),
              ),
          ],
        ]),
      ),
    );
  }
}

/// Project pages: the digest's view of where each project stands. A side panel on wide windows.
class _ProjectsPanel extends StatelessWidget {
  const _ProjectsPanel({required this.api, required this.onOpen, required this.asPanel});
  final WorklogApi api;
  final void Function(String slug) onOpen;
  final bool asPanel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: asPanel ? BoxDecoration(color: scheme.surfaceContainerLow, border: Border(left: BorderSide(color: scheme.outlineVariant))) : null,
      child: AsyncView<List<Project>>(
        load: api.projects,
        builder: (context, projects, reload) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
            child: Row(children: [
              Expanded(child: Text(context.l10n.memoryProjectStatus, style: t.titleSmall)),
              Text('${projects.length}', style: t.labelMedium?.copyWith(color: scheme.outline)),
              IconButton(tooltip: context.l10n.memoryRefresh, icon: const Icon(Icons.refresh, size: 18), onPressed: reload, visualDensity: VisualDensity.compact),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(context.l10n.memoryProjectsHint, style: t.bodySmall?.copyWith(color: scheme.outline)),
          ),
          Expanded(
            child: projects.isEmpty
                ? EmptyPane(context.l10n.memoryProjectsEmpty, icon: Icons.folder_open_outlined)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: projects.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final p = projects[i];
                      return Card.outlined(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => onOpen(p.slug),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(p.title, style: t.titleSmall)),
                                if (p.status.isNotEmpty) Text(p.status, style: t.labelSmall?.copyWith(color: scheme.primary)),
                              ]),
                              if (p.currentState.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text.rich(inlineSpan(context, p.currentState, base: t.bodySmall), maxLines: asPanel ? 4 : 3, overflow: TextOverflow.ellipsis),
                              ],
                              if (p.repos.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(p.repos.join(' · '), style: ZaevisTheme.mono.copyWith(fontSize: 11, color: scheme.outline), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
