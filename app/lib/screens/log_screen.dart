import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/input_dialogs.dart';
import '../widgets/markdown_view.dart';

const _tags = ['done', 'decision', 'blocked', 'learned'];

class LogScreen extends StatelessWidget {
  const LogScreen({super.key, required this.api, required this.onOpenProject});
  final WorklogApi api;
  final void Function(String slug) onOpenProject;

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<String>>(
      load: api.logMonths,
      builder: (context, months, _) => months.isEmpty
          ? const EmptyPane('아직 로그가 없습니다. log/YYYY-MM.md에 한 줄을 적거나 주간 정리를 기다려 주세요.')
          : _MonthLog(api: api, months: months, onOpenProject: onOpenProject),
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
            Wrap(spacing: 6, runSpacing: 4, children: [
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
                child: Text('Claude 정리 · ${entry.source}', style: t.bodySmall?.copyWith(color: scheme.outline)),
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
