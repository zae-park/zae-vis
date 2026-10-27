import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../recording/recorder.dart';
import '../widgets/input_dialogs.dart';
import '../widgets/record_dialog.dart';

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
  const CollectScreen({super.key, required this.api, this.recorder});
  final WorklogApi api;
  final Recorder? recorder;

  @override
  State<CollectScreen> createState() => _CollectScreenState();
}

class _CollectScreenState extends State<CollectScreen> {
  SourcesState? _sources;
  Inbox? _inbox;
  DatasourcesState? _external;
  Object? _error;
  Timer? _poll;

  /// Connector just added from the dialog: its card opens so the first collect's result is visible.
  String? _justAdded;

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
      final x = await widget.api.datasources();
      if (!mounted) return;
      setState(() {
        _sources = s;
        _inbox = i;
        _external = x;
        _error = null;
      });
      _poll?.cancel();
      if (s.collecting || i.transcribing || x.syncing) _poll = Timer(const Duration(seconds: 3), _load);
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

    return Readable(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
          // ── real-time input ─────────────────────────────────────────────
          const SectionHeader('바로 넣기', subtitle: '저장하는 즉시 worklog에 들어갑니다. 검색에는 다음 색인 뒤에 잡힙니다.'),
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
                await recordAndNotify(context, widget.api, recorder: widget.recorder);
                await _load();
              },
              icon: const Icon(Icons.mic),
              label: const Text('녹음하기'),
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
          SectionHeader(
            '데이터소스',
            subtitle: '매일 자동으로 모읍니다. 켜고 끄거나, 지금 바로 모을 수 있습니다.',
            trailing: FilledButton.icon(
              onPressed: s.collecting ? null : () => _act(() => widget.api.collect(), done: '수집을 시작했습니다 (끝나면 색인까지)'),
              icon: s.collecting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
              label: Text(s.collecting ? '수집 중…' : '지금 수집'),
            ),
          ),
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
                initiallyExpanded: src.name == _justAdded,
                onToggle: (on) => _act(() => widget.api.setSourceEnabled(src.name, on)),
                onCollect: () => _act(() => widget.api.collect(only: [src.name]), done: '${src.title} 수집을 시작했습니다'),
                onSave: (settings) => _act(() => widget.api.saveSourceSettings(src.name, settings), done: '저장했습니다'),
                onRemove: src.builtin ? null : () => _act(() => widget.api.removeSource(src.name), done: '삭제했습니다'),
              ),
            ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () async {
              final name = await showAddSourceDialog(context, widget.api);
              if (name == null) return;
              setState(() => _justAdded = name);
              // collect right away so the user sees whether the command works, on the card below
              await _act(() => widget.api.collect(only: [name]), done: '"$name" 커넥터를 추가하고 첫 수집을 시작했습니다. 결과는 카드에 표시됩니다.');
            },
            icon: const Icon(Icons.add),
            label: const Text('커넥터 추가'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Markdown이나 텍스트를 출력하는 명령이면 무엇이든 데이터소스가 됩니다 — 폴더의 노트, 캘린더, 사내 도구의 내보내기 스크립트.',
                style: Theme.of(context).textTheme.bodySmall),
          ),

          // ── external AutoRAG datasources ─────────────────────────────────
          if (_external != null && _external!.datasources.isNotEmpty) ...[
            const SizedBox(height: 28),
            SectionHeader(
              '외부 소스 (AutoRAG)',
              subtitle: 'Slack·Notion·Obsidian·GitHub 같은 곳을 AutoRAG가 직접 색인해 검색에 섞습니다. worklog에는 들어가지 않습니다.',
              trailing: _external!.syncing
                  ? const Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('동기화 중…'),
                    ])
                  : null,
            ),
            const SizedBox(height: 8),
            for (final d in _external!.datasources)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ExternalCard(
                  key: ValueKey('ext-${d.name}'),
                  source: d,
                  syncing: _external!.syncing,
                  onToggle: (on) => _act(() => widget.api.saveDatasource(d.name, enabled: on), done: on ? '${d.title}을(를) 켰습니다. 동기화를 시작합니다.' : '${d.title}을(를) 껐습니다'),
                  onSave: (connector, note) => _act(() => widget.api.saveDatasource(d.name, enabled: true, connector: connector, description: note),
                      done: d.configured ? '저장했습니다. 동기화를 시작합니다.' : '${d.title}을(를) 연결했습니다. 첫 동기화를 시작합니다.'),
                  onSync: () => _act(() => widget.api.syncDatasources(d.name), done: '외부 소스 동기화를 시작했습니다'),
                  onRemove: () => _act(() => widget.api.removeDatasource(d.name), done: '${d.title} 연결을 지웠습니다'),
                ),
              ),
          ],
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
          group('Claude Code 세션 노트', inbox.sessions),
        ]),
      ),
    );
  }
}

class _SourceCard extends StatefulWidget {
  const _SourceCard({super.key, required this.source, required this.busy, required this.onToggle, required this.onCollect, required this.onSave, this.onRemove, this.initiallyExpanded = false});
  final SourceInfo source;
  final bool busy;
  final bool initiallyExpanded;
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

  /// bool options are kept here (they have no text controller); absent = on, the server's default.
  late final Map<String, bool> _bools = {
    for (final o in widget.source.options)
      if (o.kind == 'bool') o.key: widget.source.settings[o.key] != false,
  };

  Map<String, Object?> _values() => {
        for (final o in widget.source.options)
          o.key: switch (o.kind) {
            'bool' => _bools[o.key] ?? true,
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
        initiallyExpanded: widget.initiallyExpanded,
        leading: Switch(value: s.enabled, onChanged: widget.onToggle),
        title: Text(s.title, style: t.titleSmall),
        subtitle: Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: s.lastOk == false ? scheme.error : null)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.description, style: t.bodySmall),
          const SizedBox(height: 8),
          for (final o in s.options)
            if (o.kind == 'bool')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(o.label),
                subtitle: o.help == null ? null : Text(o.help!, style: t.bodySmall),
                value: _bools[o.key] ?? true,
                onChanged: (v) => setState(() => _bools[o.key] = v),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _field(o),
                  minLines: o.kind == 'paths' ? 2 : 1,
                  maxLines: o.kind == 'paths' ? 5 : 1,
                  keyboardType: o.kind == 'number' ? TextInputType.number : null,
                  decoration: InputDecoration(labelText: o.label, helperText: o.help ?? (o.kind == 'paths' ? '한 줄에 하나씩' : null), isDense: true),
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

/// One AutoRAG datasource template: install hint when its CLI is missing, a connect form otherwise,
/// and on/off · sync · delete once connected.
class _ExternalCard extends StatefulWidget {
  const _ExternalCard({super.key, required this.source, required this.syncing, required this.onToggle, required this.onSave, required this.onSync, required this.onRemove});
  final ExternalDatasource source;
  final bool syncing;
  final void Function(bool) onToggle;
  final void Function(Map<String, Object?> connector, String note) onSave;
  final VoidCallback onSync;
  final VoidCallback onRemove;

  @override
  State<_ExternalCard> createState() => _ExternalCardState();
}

class _ExternalCardState extends State<_ExternalCard> {
  final Map<String, TextEditingController> _fields = {};
  late final TextEditingController _note = TextEditingController(text: widget.source.note ?? '');

  TextEditingController _field(DatasourceField f) => _fields.putIfAbsent(f.key, () => TextEditingController(text: widget.source.fieldText(f)));

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  Map<String, Object?> _connector() => {
        for (final f in widget.source.fields)
          f.key: f.kind == 'list' ? _field(f).text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList() : _field(f).text.trim(),
      };

  String _status(ExternalDatasource d) {
    if (d.unavailable != null) return d.unavailable!;
    if (d.needsInstall) return '미설치 — ${d.cliBin} 명령이 없습니다';
    if (!d.configured) return '연결 안 됨';
    if (!d.enabled) return '꺼짐';
    if (d.lastOk == false) return d.lastError ?? '동기화 실패';
    final parts = <String>['연결됨'];
    if (d.lastSync != null) parts.add('동기화 ${_ago(d.lastSync)}');
    if (d.chunks != null) parts.add('조각 ${d.chunks}개');
    if (d.autoragStatus == null && d.lastSync == null) parts.add('아직 동기화 안 함');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.source;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final failed = d.lastOk == false && d.enabled;
    final mono = TextStyle(fontFamily: 'monospace', fontSize: 13, color: scheme.onSurface);
    final Widget leading = d.configured
        ? Switch(value: d.enabled, onChanged: d.unavailable != null ? null : widget.onToggle)
        : Icon(d.unavailable != null ? Icons.block : d.needsInstall ? Icons.download_outlined : Icons.add_link, color: scheme.outline);
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: leading,
        title: Text(d.title, style: t.titleSmall),
        subtitle: Text(_status(d), maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: failed ? scheme.error : null)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.description, style: t.bodySmall),
          if (d.external != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('밖으로 나가는 것: ${d.external}', style: t.bodySmall?.copyWith(color: scheme.outline))),
          if (d.needsInstall) ...[
            const SizedBox(height: 10),
            Text('먼저 터미널에서 설치하고 로그인·수집을 한 번 해 두세요:', style: t.bodySmall),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
              child: SelectableText(d.install ?? '', style: mono, minLines: 1, maxLines: 3),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: d.install ?? ''));
                  if (context.mounted) toast(context, '설치 명령을 복사했습니다');
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('설치 명령 복사'),
              ),
              if (d.homepage != null) OutlinedButton(onPressed: () => Clipboard.setData(ClipboardData(text: d.homepage!)), child: Text(d.homepage!, style: t.bodySmall)),
            ]),
          ] else if (d.unavailable == null) ...[
            if (d.archive == false)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${d.cliBin}의 아카이브가 아직 없습니다. 먼저 ${d.cliBin}으로 로그인·수집을 한 번 하세요.', style: t.bodySmall?.copyWith(color: scheme.error)),
              ),
            for (final e in d.env)
              if (!e.set)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('환경 변수 ${e.name}이(가) 서버에 없습니다. 값은 여기 적지 말고 서버를 띄운 셸에 설정하세요.', style: t.bodySmall?.copyWith(color: scheme.error)),
                ),
            for (final f in d.fields)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _field(f),
                  minLines: f.kind == 'list' ? 2 : 1,
                  maxLines: f.kind == 'list' ? 6 : 1,
                  style: f.kind == 'list' || f.kind == 'env' ? mono : null,
                  decoration: InputDecoration(
                    labelText: f.required ? '${f.label} *' : f.label,
                    hintText: f.placeholder,
                    helperText: f.help ?? (f.kind == 'list' ? '한 줄에 하나씩' : f.kind == 'env' ? '값이 아니라 환경 변수 이름' : null),
                    helperMaxLines: 2,
                    isDense: true,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(controller: _note, decoration: const InputDecoration(labelText: '메모 (선택)', helperText: '이 연결이 무엇인지. 질문 모드의 에이전트에게도 보입니다.', isDense: true)),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              FilledButton(onPressed: () => widget.onSave(_connector(), _note.text.trim()), child: Text(d.configured ? '저장' : '연결')),
              if (d.configured) OutlinedButton(onPressed: widget.syncing || !d.enabled ? null : widget.onSync, child: const Text('지금 동기화')),
              if (d.configured) TextButton(onPressed: widget.onRemove, child: Text('연결 삭제', style: TextStyle(color: scheme.error))),
            ]),
          ],
        ],
      ),
    );
  }
}

/// Ready-made connectors: pick one, adjust the folder/command, add. Everything is a shell command
/// that prints text, so the user can also start from scratch.
class ConnectorPreset {
  const ConnectorPreset({required this.id, required this.title, required this.description, required this.name, required this.command, this.requires});
  final String id;
  final String title;
  final String description;
  final String name;
  final String command;

  /// What has to be installed for the command to work, if anything.
  final String? requires;

  static const all = [
    ConnectorPreset(
      id: 'folder',
      title: '폴더의 노트 (Markdown·텍스트)',
      description: '폴더 안에서 수집 구간에 수정된 .md/.txt 파일을 통째로 가져옵니다. Obsidian 볼트, 메모 폴더에 맞습니다.',
      name: 'notes',
      command: "find ~/Notes -type f \\( -name '*.md' -o -name '*.txt' \\) -newermt {fromDate} -exec sh -c 'echo \"## \$1\"; cat \"\$1\"; echo' _ {} \\;",
    ),
    ConnectorPreset(
      id: 'calendar',
      title: 'macOS 캘린더 일정',
      description: '수집 구간의 캘린더 일정을 제목·시간·참석자와 함께 가져옵니다.',
      name: 'calendar',
      command: "icalBuddy -nc -nrd -b '- ' eventsFrom:{fromDate} to:{toDate}",
      requires: "brew install ical-buddy",
    ),
    ConnectorPreset(
      id: 'custom',
      title: '직접 입력',
      description: 'Markdown을 출력하는 아무 명령. 스크립트, curl, 사내 CLI…',
      name: '',
      command: '',
    ),
  ];
}

/// Returns the new connector's name, or null when cancelled.
Future<String?> showAddSourceDialog(BuildContext context, WorklogApi api) async {
  final name = TextEditingController();
  final command = TextEditingController();
  final desc = TextEditingController();
  String? chosen;
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      String? error;
      bool busy = false;
      return StatefulBuilder(builder: (context, setLocal) {
        final t = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        void pick(ConnectorPreset p) => setLocal(() {
              chosen = p.id;
              name.text = p.name;
              command.text = p.command;
              desc.text = p.id == 'custom' ? '' : p.title;
              error = null;
            });
        return AlertDialog(
          title: const Text('커넥터 추가'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('1. 무엇을 모을지 고르세요', style: t.labelLarge),
                const SizedBox(height: 6),
                for (final p in ConnectorPreset.all)
                  Card.outlined(
                    margin: const EdgeInsets.only(bottom: 6),
                    color: chosen == p.id ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
                    child: ListTile(
                      dense: true,
                      leading: Icon(chosen == p.id ? Icons.radio_button_checked : Icons.radio_button_off, color: chosen == p.id ? scheme.primary : scheme.outline),
                      title: Text(p.title),
                      subtitle: Text([p.description, if (p.requires != null) '필요: ${p.requires}'].join('\n'), style: t.bodySmall),
                      onTap: () => pick(p),
                    ),
                  ),
                if (chosen != null) ...[
                  const SizedBox(height: 10),
                  Text('2. 확인하고 고치세요', style: t.labelLarge),
                  TextField(controller: name, decoration: const InputDecoration(labelText: '이름 (영문 소문자·숫자·-)', hintText: 'my-notes')),
                  TextField(
                    controller: command,
                    minLines: 1,
                    maxLines: 4,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      labelText: '명령',
                      hintText: 'python3 ~/bin/export.py --since {from}',
                      helperText: chosen == 'folder' ? '~/Notes 를 실제 폴더로 바꾸세요' : null,
                    ),
                  ),
                  TextField(controller: desc, decoration: const InputDecoration(labelText: '설명 (선택)')),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      '명령 안의 자리표시자는 수집 때 바뀝니다:\n'
                      '  {fromDate} {toDate}  →  2026-10-20  (날짜만)\n'
                      '  {from} {to}  →  2026-10-20T00:00:00.000Z  (ISO 시각)\n'
                      '출력을 날짜별로 나누려면 줄 사이에 <!-- zaevis:date 2026-10-23 --> 를 넣으세요. 없으면 수집한 날의 기록이 됩니다.\n'
                      '추가하면 바로 한 번 수집해 결과를 카드에 보여 줍니다.',
                      style: t.bodySmall,
                    ),
                  ),
                ],
                if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: scheme.error))),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
            FilledButton(
              onPressed: chosen == null || busy
                  ? null
                  : () async {
                      final n = name.text.trim();
                      final c = command.text.trim();
                      if (n.isEmpty || c.isEmpty) {
                        setLocal(() => error = '이름과 명령을 채워 주세요');
                        return;
                      }
                      setLocal(() => busy = true);
                      try {
                        await api.addSource(n, c, description: desc.text.trim().isEmpty ? null : desc.text.trim());
                        if (context.mounted) Navigator.pop(context, n);
                      } on ApiException catch (e) {
                        if (!context.mounted) return;
                        setLocal(() {
                          error = e.message;
                          busy = false;
                        });
                      }
                    },
              child: const Text('추가하고 수집'),
            ),
          ],
        );
      });
    },
  );
  return result;
}
