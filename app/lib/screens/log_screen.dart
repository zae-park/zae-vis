import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/input_dialogs.dart';
import '../widgets/markdown_view.dart';
import 'file_screen.dart';

const _tags = ['done', 'decision', 'blocked', 'learned'];

class LogScreen extends StatefulWidget {
  const LogScreen({super.key, required this.api, required this.onOpenProject});
  final WorklogApi api;
  final void Function(String slug) onOpenProject;

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  // a pending digest review is announced by the memory tab's knowledge panel (widgets/knowledge_panel.dart)
  @override
  Widget build(BuildContext context) {
    return AsyncView<List<String>>(
      load: widget.api.logMonths,
      builder: (context, months, _) => months.isEmpty
          ? EmptyPane(context.l10n.logEmpty)
          : _MonthLog(api: widget.api, months: months, onOpenProject: widget.onOpenProject),
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
                label: Text(context.l10n.logOnlyMine),
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
              if (shown.isEmpty) return EmptyPane(context.l10n.logNoMatch);
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
      if (context.mounted) toast(context, context.l10n.logEdited);
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
      toast(context, context.l10n.logOriginNotFound(src));
      return;
    }
    FileScreen.open(context, api, paths.first);
  }

  Future<void> _delete(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.logDeleteTitle),
        content: Text(entry.text, maxLines: 4, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.commonClear)),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    try {
      await api.deleteLog(month, entry.raw);
      if (context.mounted) toast(context, context.l10n.logDeleted);
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
                message: entry.byClaude ? context.l10n.logByDigestTip : context.l10n.logMineTip,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(border: Border.all(color: entry.byClaude ? scheme.outlineVariant : scheme.primary.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(entry.byClaude ? Icons.auto_awesome : Icons.lock_outline, size: 11, color: entry.byClaude ? scheme.outline : scheme.primary),
                    const SizedBox(width: 3),
                    Text(entry.byClaude ? context.l10n.logDigest : context.l10n.logMine, style: t.labelSmall?.copyWith(color: entry.byClaude ? scheme.outline : scheme.primary)),
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
                    Flexible(child: Text(context.l10n.logSource(entry.source!), style: t.bodySmall?.copyWith(color: scheme.primary, decoration: TextDecoration.underline, decorationColor: scheme.primary.withValues(alpha: 0.4)), overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ),
          ]),
        ),
        PopupMenuButton<String>(
          tooltip: context.l10n.logMenu,
          icon: Icon(Icons.more_horiz, size: 18, color: scheme.outline),
          onSelected: (v) => v == 'edit' ? _edit(context) : _delete(context),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit', child: ListTile(dense: true, leading: const Icon(Icons.edit_outlined), title: Text(context.l10n.logEdit))),
            PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: const Icon(Icons.delete_outline), title: Text(context.l10n.commonClear))),
          ],
        ),
      ]),
    );
  }
}
