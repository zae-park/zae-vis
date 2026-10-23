import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/input_dialogs.dart';

String _ago(DateTime? t) {
  if (t == null) return '아직 수집 안 함';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return '방금';
  if (d.inHours < 1) return '${d.inMinutes}분 전';
  if (d.inDays < 1) return '${d.inHours}시간 전';
  return '${d.inDays}일 전';
}

String _size(int b) => b >= 1 << 20 ? '${(b / (1 << 20)).toStringAsFixed(1)}MB' : '${(b / 1024).ceil()}KB';

/// Data sources (batch) + inbox and real-time input.
class CollectScreen extends StatefulWidget {
  const CollectScreen({super.key, required this.api});
  final WorklogApi api;

  @override
  State<CollectScreen> createState() => _CollectScreenState();
}

class _CollectScreenState extends State<CollectScreen> {
  SourcesState? _sources;
  Inbox? _inbox;
  Object? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.sources();
      final i = await widget.api.inbox();
      if (!mounted) return;
      setState(() {
        _sources = s;
        _inbox = i;
        _error = null;
      });
      _poll?.cancel();
      if (s.collecting || i.transcribing) _poll = Timer(const Duration(seconds: 3), _load);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _act(Future<void> Function() f, {String? done}) async {
    try {
      await f();
      if (mounted && done != null) toast(context, done);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorPane(error: _error!, onRetry: _load);
    final s = _sources;
    final inbox = _inbox;
    if (s == null || inbox == null) return const Center(child: CircularProgressIndicator());
    final t = Theme.of(context).textTheme;

    return Readable(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
          // ── real-time input ─────────────────────────────────────────────
          Text('바로 넣기', style: t.titleMedium),
          const SizedBox(height: 4),
          Text('저장하는 즉시 worklog에 들어갑니다. 검색에는 다음 색인 뒤에 잡힙니다.', style: t.bodySmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: () async {
                if (await showAddLogDialog(context, widget.api) && context.mounted) toast(context, '로그에 추가했습니다');
              },
              icon: const Icon(Icons.edit_note),
              label: const Text('한 줄 기록'),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                final f = await showPasteTranscriptDialog(context, widget.api);
                if (f != null && context.mounted) toast(context, 'inbox에 저장: $f');
                await _load();
              },
              icon: const Icon(Icons.content_paste),
              label: const Text('전사본 붙여넣기'),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                final n = await pickAndUploadAudio(context, widget.api);
                if (n > 0 && context.mounted) toast(context, '녹음 $n개를 전사 대기열에 넣었습니다');
                await _load();
              },
              icon: const Icon(Icons.mic_none),
              label: const Text('녹음 올리기 (whisperX)'),
            ),
          ]),
          const SizedBox(height: 16),
          _InboxCard(inbox: inbox),
          const SizedBox(height: 28),

          // ── batch sources ────────────────────────────────────────────────
          Row(children: [
            Expanded(child: Text('데이터소스 (매일 자동 수집)', style: t.titleMedium)),
            FilledButton.icon(
              onPressed: s.collecting ? null : () => _act(() => widget.api.collect(), done: '수집을 시작했습니다 (끝나면 색인까지)'),
              icon: s.collecting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
              label: Text(s.collecting ? '수집 중…' : '지금 수집'),
            ),
          ]),
          if (s.lastCollectError != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(s.lastCollectError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 8),
          for (final src in s.sources)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SourceCard(
                key: ValueKey(src.name),
                source: src,
                busy: s.collecting,
                onToggle: (on) => _act(() => widget.api.setSourceEnabled(src.name, on)),
                onCollect: () => _act(() => widget.api.collect(only: [src.name]), done: '${src.title} 수집을 시작했습니다'),
                onSave: (settings) => _act(() => widget.api.saveSourceSettings(src.name, settings), done: '저장했습니다'),
                onRemove: src.builtin ? null : () => _act(() => widget.api.removeSource(src.name), done: '삭제했습니다'),
              ),
            ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () async {
              if (await _showAddSourceDialog(context, widget.api)) await _load();
            },
            icon: const Icon(Icons.add),
            label: const Text('커넥터 추가 (명령어)'),
          ),
        ]),
      ),
    );
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({required this.inbox});
  final Inbox inbox;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget group(String title, List<InboxFile> files) => ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('$title (${files.length})', style: t.titleSmall),
          children: [
            if (files.isEmpty) Align(alignment: Alignment.centerLeft, child: Text('없음', style: t.bodySmall)),
            for (final f in files.take(20))
              ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(f.name), trailing: Text(_size(f.size), style: t.bodySmall)),
          ],
        );
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 8), child: Text('inbox — 다음 주간 정리에서 로그로 정리됩니다', style: t.labelLarge)),
          for (final j in inbox.jobs.take(5))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: switch (j.state) {
                'running' => const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                'failed' => Icon(Icons.error_outline, color: scheme.error),
                'done' => const Icon(Icons.check_circle_outline),
                _ => const Icon(Icons.schedule),
              },
              title: Text(j.file),
              subtitle: Text(j.error ?? j.result ?? (j.state == 'queued' ? '전사 대기' : '전사 중…'), maxLines: 2),
            ),
          group('전사본', inbox.transcripts),
          group('전사 대기 녹음', inbox.audio),
          group('Claude 세션 노트', inbox.sessions),
        ]),
      ),
    );
  }
}

class _SourceCard extends StatefulWidget {
  const _SourceCard({super.key, required this.source, required this.busy, required this.onToggle, required this.onCollect, required this.onSave, this.onRemove});
  final SourceInfo source;
  final bool busy;
  final void Function(bool) onToggle;
  final VoidCallback onCollect;
  final void Function(Map<String, Object?>) onSave;
  final VoidCallback? onRemove;

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  final Map<String, TextEditingController> _fields = {};

  TextEditingController _field(SourceOption o) =>
      _fields.putIfAbsent(o.key, () => TextEditingController(text: widget.source.optionText(o)));

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> _values() => {
        for (final o in widget.source.options)
          o.key: switch (o.kind) {
            'paths' => _field(o).text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList(),
            'number' => num.tryParse(_field(o).text.trim()),
            _ => _field(o).text.trim(),
          },
      };

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = s.lastOk == false ? (s.lastError ?? '실패') : [_ago(s.lastRun), if (s.lastNote != null) s.lastNote!].join(' · ');
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Switch(value: s.enabled, onChanged: widget.onToggle),
        title: Text(s.title, style: t.titleSmall),
        subtitle: Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: s.lastOk == false ? scheme.error : null)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.description, style: t.bodySmall),
          const SizedBox(height: 8),
          for (final o in s.options)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _field(o),
                minLines: o.kind == 'paths' ? 2 : 1,
                maxLines: o.kind == 'paths' ? 5 : 1,
                keyboardType: o.kind == 'number' ? TextInputType.number : null,
                decoration: InputDecoration(labelText: o.label, helperText: o.kind == 'paths' ? '한 줄에 하나씩' : null, isDense: true),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            FilledButton(onPressed: () => widget.onSave(_values()), child: const Text('저장')),
            OutlinedButton(onPressed: widget.busy || !s.enabled ? null : widget.onCollect, child: const Text('이것만 수집')),
            if (widget.onRemove != null)
              TextButton(onPressed: widget.onRemove, child: Text('삭제', style: TextStyle(color: scheme.error))),
          ]),
        ],
      ),
    );
  }
}

Future<bool> _showAddSourceDialog(BuildContext context, WorklogApi api) async {
  final name = TextEditingController();
  final command = TextEditingController();
  final desc = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      String? error;
      return StatefulBuilder(builder: (context, setLocal) => AlertDialog(
            title: const Text('커넥터 추가'),
            content: SizedBox(
              width: 560,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Markdown을 출력하는 명령이면 무엇이든 연결됩니다. {from}, {to}는 수집 구간(ISO 시각)으로 바뀝니다. '
                    '날짜별로 나누려면 출력에 <!-- zaevis:date 2026-10-23 --> 줄을 넣으세요.'),
                const SizedBox(height: 12),
                TextField(controller: name, decoration: const InputDecoration(labelText: '이름 (영문 소문자)', hintText: 'slack')),
                TextField(
                  controller: command,
                  decoration: const InputDecoration(labelText: '명령', hintText: 'python3 ~/bin/slack_export.py --since {from}'),
                ),
                TextField(controller: desc, decoration: const InputDecoration(labelText: '설명 (선택)')),
                if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
              FilledButton(
                onPressed: () async {
                  try {
                    await api.addSource(name.text.trim(), command.text.trim(), description: desc.text.trim().isEmpty ? null : desc.text.trim());
                    if (context.mounted) Navigator.pop(context, true);
                  } on ApiException catch (e) {
                    if (!context.mounted) return;
                    setLocal(() => error = e.message);
                  }
                },
                child: const Text('추가'),
              ),
            ],
          ));
    },
  );
  return ok == true;
}
