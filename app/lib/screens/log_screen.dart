import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/input_dialogs.dart';
import '../widgets/markdown_view.dart';
import 'file_screen.dart';
import 'review_screen.dart';

const _tags = ['done', 'decision', 'blocked', 'learned'];

class LogScreen extends StatefulWidget {
  const LogScreen({super.key, required this.api, required this.onOpenProject});
  final WorklogApi api;
  final void Function(String slug) onOpenProject;

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  int _generation = 0;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _ProposalBanner(key: ValueKey('banner$_generation'), api: widget.api, onChanged: () => setState(() => _generation++)),
      Expanded(
        child: AsyncView<List<String>>(
          key: ValueKey('log$_generation'),
          load: widget.api.logMonths,
          builder: (context, months, _) => months.isEmpty
              ? const EmptyPane('아직 로그가 없습니다. log/YYYY-MM.md에 한 줄을 적거나 주간 정리를 기다려 주세요.')
              : _MonthLog(api: widget.api, months: months, onOpenProject: widget.onOpenProject),
        ),
      ),
    ]);
  }
}

/// "정리 제안 N건이 검토를 기다립니다" above the log when a reviewed digest run is pending.
class _ProposalBanner extends StatefulWidget {
  const _ProposalBanner({super.key, required this.api, required this.onChanged});
  final WorklogApi api;
  final VoidCallback onChanged;

  @override
  State<_ProposalBanner> createState() => _ProposalBannerState();
}

class _ProposalBannerState extends State<_ProposalBanner> {
  // a failed fetch just hides the banner; the log itself reports server trouble
  late final Future<List<ProposalSummary>> _future = widget.api.proposals().catchError((_) => <ProposalSummary>[]);

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    final onChanged = widget.onChanged;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<ProposalSummary>>(
      future: _future,
      builder: (context, snap) {
        final pending = (snap.data ?? const <ProposalSummary>[]).where((p) => p.pending).toList();
        if (pending.isEmpty) return const SizedBox.shrink();
        final total = pending.fold(0, (n, p) => n + p.lines);
        return Readable(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Material(
              color: scheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: Row(children: [
                  Icon(Icons.rule, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('정리 제안 ${pending.length}건이 검토를 기다립니다 — 로그 $total줄. 고른 줄만 worklog에 들어갑니다.', style: t.bodyMedium),
                  ),
                  FilledButton.tonal(
                    onPressed: () async {
                      if (await ReviewScreen.open(context, api, pending.first.id)) onChanged();
                    },
                    child: const Text('검토하기'),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MonthLog extends StatefulWidget {
  const _MonthLog({required this.api, required this.months, required this.onOpenProject});
  final WorklogApi api;
  final List<String> months;
  final void Function(String slug) onOpenProject;

  @override
  State<_MonthLog> createState() => _MonthLogState();
}

class _MonthLogState extends State<_MonthLog> {
  late String _month = widget.months.first;
  late Future<List<LogEntry>> Function() _load = _loader(_month);
  final Set<String> _selected = {};
  bool _onlyMine = false;

  Future<List<LogEntry>> Function() _loader(String m) => () => widget.api.log(m);

  @override
  Widget build(BuildContext context) {
    return Readable(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: _month,
                items: [for (final m in widget.months) DropdownMenuItem(value: m, child: Text(m))],
                onChanged: (m) => setState(() {
                  _month = m!;
                  _load = _loader(m);
                }),
              ),
              for (final tag in _tags)
                FilterChip(
                  label: Text(tagLabel(tag)),
                  selected: _selected.contains(tag),
                  onSelected: (on) => setState(() => on ? _selected.add(tag) : _selected.remove(tag)),
                ),
              FilterChip(
                label: const Text('내가 쓴 줄만'),
                selected: _onlyMine,
                onSelected: (on) => setState(() => _onlyMine = on),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView<List<LogEntry>>(
            load: _load,
            builder: (context, entries, reload) {
              final shown = entries
                  .where((e) => _selected.isEmpty || e.tags.any(_selected.contains))
                  .where((e) => !_onlyMine || !e.byClaude)
                  .toList()
                  .reversed
                  .toList();
              if (shown.isEmpty) return const EmptyPane('조건에 맞는 로그가 없습니다.');
              return RefreshIndicator(
                onRefresh: () async => reload(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _EntryTile(entry: shown[i], month: _month, api: widget.api, onOpenProject: widget.onOpenProject, onChanged: reload),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.month, required this.api, required this.onOpenProject, required this.onChanged});
  final LogEntry entry;
  final String month;
  final WorklogApi api;
  final void Function(String slug) onOpenProject;
  final VoidCallback onChanged;

  Future<void> _edit(BuildContext context) async {
    List<String> projects = const [];
    try {
      projects = (await api.projects()).map((p) => p.slug).toList();
    } catch (_) {}
    if (!context.mounted) return;
    if (await showEditLogDialog(context, api, month: month, entry: entry, projects: projects)) {
      if (context.mounted) toast(context, '줄을 고쳤습니다');
      onChanged();
    }
  }

  /// Opens the material the line was written from (its "(src: …)" marker).
  Future<void> _openOrigin(BuildContext context) async {
    final src = entry.source;
    if (src == null) return;
    List<String> paths = const [];
    try {
      paths = await api.origin(src);
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
      return;
    }
    if (!context.mounted) return;
    if (paths.isEmpty) {
      toast(context, '원본 파일을 찾지 못했습니다: $src');
      return;
    }
    FileScreen.open(context, api, paths.first);
  }

  Future<void> _delete(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이 줄을 지울까요?'),
        content: Text(entry.text, maxLines: 4, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('지우기')),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    try {
      await api.deleteLog(month, entry.raw);
      if (context.mounted) toast(context, '줄을 지웠습니다');
      onChanged();
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 52, child: Text(entry.date, style: t.labelLarge?.copyWith(color: scheme.outline))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              // who wrote it: my own lines are never rewritten by the digest (it can only propose)
              Tooltip(
                message: entry.byClaude ? '정리 에이전트가 원본에서 뽑아 쓴 줄 — 출처를 누르면 원본이 열립니다' : '내가 쓴 줄 — 정리 에이전트는 이 줄을 고치지 않습니다 (검토를 거쳐 제안만 합니다)',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(border: Border.all(color: entry.byClaude ? scheme.outlineVariant : scheme.primary.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(entry.byClaude ? Icons.auto_awesome : Icons.lock_outline, size: 11, color: entry.byClaude ? scheme.outline : scheme.primary),
                    const SizedBox(width: 3),
                    Text(entry.byClaude ? '정리' : '내 기록', style: t.labelSmall?.copyWith(color: entry.byClaude ? scheme.outline : scheme.primary)),
                  ]),
                ),
              ),
              for (final tag in entry.tags)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: tagColor(scheme, tag).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(tagLabel(tag), style: t.labelSmall?.copyWith(color: tagColor(scheme, tag))),
                ),
              for (final p in entry.projects)
                InkWell(
                  onTap: () => onOpenProject(p),
                  child: Text(p, style: t.labelMedium?.copyWith(color: scheme.primary)),
                ),
            ]),
            const SizedBox(height: 4),
            SelectableText.rich(inlineSpan(context, entry.text, base: t.bodyMedium, onLink: onOpenProject), minLines: 1, maxLines: 6),
            if (entry.source != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: InkWell(
                  onTap: () => _openOrigin(context),
                  borderRadius: BorderRadius.circular(4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.subdirectory_arrow_right, size: 13, color: scheme.outline),
                    const SizedBox(width: 3),
                    Flexible(child: Text('출처 ${entry.source}', style: t.bodySmall?.copyWith(color: scheme.primary, decoration: TextDecoration.underline, decorationColor: scheme.primary.withValues(alpha: 0.4)), overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ),
          ]),
        ),
        PopupMenuButton<String>(
          tooltip: '줄 메뉴',
          icon: Icon(Icons.more_horiz, size: 18, color: scheme.outline),
          onSelected: (v) => v == 'edit' ? _edit(context) : _delete(context),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: ListTile(dense: true, leading: Icon(Icons.edit_outlined), title: Text('편집'))),
            PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: Icon(Icons.delete_outline), title: Text('지우기'))),
          ],
        ),
      ]),
    );
  }
}
