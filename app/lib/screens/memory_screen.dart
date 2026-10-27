import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/markdown_view.dart';
import 'collect_screen.dart' show SourceIcon;
import 'file_screen.dart';
import 'log_screen.dart';

/// 메모리: everything the app knows, in three layers — 기록 (the log lines, mine and the digest's),
/// 원본 (the collected day files and inbox material the lines came from) and 상태 (the project
/// pages the digest keeps). Wide windows show 상태 as a panel on the right.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key, required this.api, required this.onOpenProject});
  final WorklogApi api;
  final void Function(String slug) onOpenProject;

  static const panelBreakpoint = 1040.0;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

enum _Layer {
  log('기록', Icons.list_alt_outlined),
  origins('원본', Icons.inventory_2_outlined),
  projects('상태', Icons.folder_outlined);

  const _Layer(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _MemoryScreenState extends State<MemoryScreen> {
  _Layer _layer = _Layer.log;
  bool _showFlow = true;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= MemoryScreen.panelBreakpoint;
    final layers = wide ? [_Layer.log, _Layer.origins] : _Layer.values;
    if (wide && _layer == _Layer.projects) _layer = _Layer.log;
    final main = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          SegmentedButton<_Layer>(
            segments: [for (final l in layers) ButtonSegment(value: l, label: Text(l.label), icon: Icon(l.icon, size: 18))],
            selected: {_layer},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => setState(() => _layer = s.first),
          ),
          const Spacer(),
          IconButton(
            tooltip: _showFlow ? '흐름 설명 숨기기' : '내 기록이 어떻게 쓰이는지',
            icon: Icon(_showFlow ? Icons.info : Icons.info_outline),
            onPressed: () => setState(() => _showFlow = !_showFlow),
          ),
        ]),
      ),
      if (_showFlow) _FlowStrip(layer: _layer),
      Expanded(
        child: switch (_layer) {
          _Layer.log => LogScreen(api: widget.api, onOpenProject: widget.onOpenProject),
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
    final steps = switch (layer) {
      _Layer.log => const [
          (Icons.lock_outline, '내가 쓴 줄', '한 줄 기록·녹음·전사본. 정리 에이전트는 고치지 못하고 검토를 거쳐 제안만 합니다.'),
          (Icons.auto_awesome, '정리가 쓴 줄', '수집된 원본에서 에이전트가 뽑은 줄. 출처를 누르면 원본이 열립니다.'),
          (Icons.search, '쓰임', '검색·질문·리포트가 이 줄들과 원본을 근거로 씁니다.'),
        ],
      _Layer.origins => const [
          (Icons.download_outlined, '매일 수집', 'git·에이전트 세션·셸·전사본·커넥터가 날짜별 파일로 쌓입니다.'),
          (Icons.auto_awesome, '정리', '주간 정리가 이 파일을 읽어 기록 줄과 프로젝트 상태를 씁니다 (검토 뒤 적용).'),
          (Icons.search, '검색', '원본도 그대로 색인되어 검색·질문에 잡힙니다.'),
        ],
      _Layer.projects => const [
          (Icons.folder_outlined, '프로젝트 페이지', '정리 에이전트가 프로젝트마다 현재 상태·결정·열린 문제를 갱신합니다.'),
          (Icons.link, '기록과 연결', '기록 줄의 [[프로젝트]] 링크가 이 페이지로 옵니다.'),
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

  /// Log lines whose (src: …) names this file: by "<source> <date>", a transcript's name, or a git hash in the file.
  static int citations(OriginFile f, List<LogEntry> entries) {
    var n = 0;
    final base = f.name.replaceAll(RegExp(r'\.(md|txt)$'), '');
    for (final e in entries) {
      final s = e.source;
      if (s == null) continue;
      if (s.contains('${f.source} ${f.date}') || (f.source == 'agent-sessions' && s.contains('claude-code ${f.date}')) || (f.source == 'shell-history' && s.contains('shell ${f.date}'))) {
        n++;
      } else if ((f.source == 'transcripts' || f.source == 'session-notes') && s.contains(base)) {
        n++;
      }
    }
    return n;
  }

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
        if (files.isEmpty) return const EmptyPane('아직 수집된 원본이 없습니다\n연결 탭에서 "지금 수집"을 누르거나 매일 수집을 기다리면 날짜별 파일이 여기 쌓입니다.');
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
              Text('${shown.length}개 파일 · ${dates.length}일', style: t.labelMedium?.copyWith(color: scheme.outline)),
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
                        Text(cited > 0 ? '기록 $cited줄의 근거' : '아직 정리 안 됨', style: t.labelSmall?.copyWith(color: cited > 0 ? scheme.primary : scheme.outline)),
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
      message: '${file.path} · ${_size(file.bytes)}${file.kind == 'inbox' ? ' · inbox (아직 정리 전)' : file.kind == 'processed' ? ' · 정리됨' : ''}',
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
              Expanded(child: Text('프로젝트 상태', style: t.titleSmall)),
              Text('${projects.length}', style: t.labelMedium?.copyWith(color: scheme.outline)),
              IconButton(tooltip: '새로고침', icon: const Icon(Icons.refresh, size: 18), onPressed: reload, visualDensity: VisualDensity.compact),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text('정리 에이전트가 프로젝트마다 갱신하는 현재 상태 · 결정 · 열린 문제', style: t.bodySmall?.copyWith(color: scheme.outline)),
          ),
          Expanded(
            child: projects.isEmpty
                ? const EmptyPane('아직 프로젝트 페이지가 없습니다\n정리가 돌면 기록의 [[프로젝트]]마다 페이지를 만듭니다.', icon: Icons.folder_open_outlined)
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
