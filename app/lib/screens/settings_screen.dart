import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../backend/backend.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/input_dialogs.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api, required this.onServerChanged, this.backend});
  final WorklogApi api;
  final Backend? backend;
  final VoidCallback onServerChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _server = TextEditingController(text: widget.api.baseUrl);
  late Future<AppSettings> _future = widget.api.settings();

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
        _future = widget.api.settings();
      });

  bool get _managed => widget.backend?.managed == true;

  /// Runs `zaevis <args>` from the app bundle and shows its output live.
  Future<void> _runTask(String title, List<String> args, {List<String>? then}) async {
    final lines = ValueNotifier<List<String>>(const []);
    final done = ValueNotifier<String?>(null);
    void add(String l) => lines.value = [...lines.value, l];
    () async {
      try {
        await widget.backend!.run(args).forEach(add);
        if (then != null) await widget.backend!.run(then).forEach(add);
        done.value = '완료';
      } catch (e) {
        done.value = '실패: $e';
      }
    }();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 600,
          height: 320,
          child: ValueListenableBuilder<List<String>>(
            valueListenable: lines,
            builder: (_, l, __) => ListView(reverse: true, children: [
              for (final line in l.reversed) Text(line, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ]),
          ),
        ),
        actions: [
          ValueListenableBuilder<String?>(
            valueListenable: done,
            builder: (context, d, _) => d == null
                ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : TextButton(onPressed: () => Navigator.pop(context), child: Text('$d · 닫기')),
          ),
        ],
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _update({String? dailyAt, bool? indexOnInject, bool? localEmbedding}) async {
    try {
      await widget.api.updateSettings(dailyAt: dailyAt, indexOnInject: indexOnInject, localEmbedding: localEmbedding);
      if (mounted) toast(context, '저장했습니다');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: Readable(
        maxWidth: 720,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('서버', style: t.titleMedium),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _server, decoration: const InputDecoration(labelText: '서버 주소', hintText: defaultDesktopBase))),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () {
                widget.api.baseUrl = _server.text.trim().isEmpty ? defaultBaseUrl() : _server.text.trim();
                widget.onServerChanged();
                _reload();
              },
              child: const Text('적용'),
            ),
          ]),
          const SizedBox(height: 24),
          FutureBuilder<AppSettings>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snap.hasError) return ErrorPane(error: snap.error!, onRetry: _reload);
              final s = snap.data!;
              final schedule = !s.scheduleSupported
                  ? (s.scheduleHint ?? '이 OS에서는 자동 예약을 지원하지 않습니다.')
                  : !s.scheduleInstalled
                      ? '예약 없음 — 아래 시각을 저장하면 등록됩니다.'
                      : s.scheduleLoaded
                          ? '매일 ${s.dailyAt} 실행 중 (맥이 잠자기였으면 깨어날 때 실행)'
                          : '등록됐지만 아직 로드되지 않음';
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('매일 수집 · 색인', style: t.titleMedium),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text('실행 시각 ${s.dailyAt}'),
                  subtitle: Text(schedule),
                  trailing: OutlinedButton(
                    onPressed: () async {
                      final parts = s.dailyAt.split(':');
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 18, minute: int.tryParse(parts.last) ?? 30),
                      );
                      if (picked == null) return;
                      String two(int n) => n.toString().padLeft(2, '0');
                      await _update(dailyAt: '${two(picked.hour)}:${two(picked.minute)}');
                    },
                    child: const Text('바꾸기'),
                  ),
                ),
                if (s.lastDaily != null)
                  Padding(padding: const EdgeInsets.only(left: 56), child: Text('마지막 실행: ${s.lastDaily!.toLocal()}'.split('.').first, style: t.bodySmall)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.bolt),
                  title: const Text('넣자마자 색인'),
                  subtitle: const Text('한 줄 기록이나 전사본을 넣으면 바로 검색 색인을 갱신합니다. 끄면 예약·수동 색인 때만 반영됩니다.'),
                  value: s.indexOnInject,
                  onChanged: (v) => _update(indexOnInject: v),
                ),
                const SizedBox(height: 16),
                Text('검색', style: t.titleMedium),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.psychology_outlined),
                  title: const Text('의미 검색 (로컬 임베딩)'),
                  subtitle: const Text('이 맥에서 Qwen3-Embedding 모델을 돌려 뜻이 비슷한 기록도 찾습니다. 외부 서비스나 키는 쓰지 않습니다. '
                      '처음 켤 때 모델(1.1GB)을 내려받고 색인을 다시 만듭니다. 끄면 키워드 검색만 합니다.'),
                  value: s.localEmbedding,
                  onChanged: (v) => _update(localEmbedding: v),
                ),
                if (s.rerank != null) _RerankSection(api: widget.api, status: s.rerank!, onChanged: _reload),
                const SizedBox(height: 16),
                Text('정리 (지식화)', style: t.titleMedium),
                _DigestSection(api: widget.api),
                const SizedBox(height: 16),
                Text('확장', style: t.titleMedium),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(s.whisperx ? Icons.check_circle_outline : Icons.extension_outlined),
                  title: const Text('whisperX (녹음 전사)'),
                  subtitle: Text(s.whisperx
                      ? '설치됨'
                      : (_managed ? '설치하면 녹음을 올릴 때 자동으로 전사합니다 (1~2GB 다운로드)' : "설치되지 않음 — 터미널에서 'zaevis ext install whisperx'")),
                  trailing: !s.whisperx && _managed
                      ? FilledButton.tonal(onPressed: () => _runTask('whisperX 설치', const ['ext', 'install', 'whisperx']), child: const Text('설치'))
                      : null,
                ),
                if (_managed) ...[
                  const SizedBox(height: 16),
                  Text('앱', style: t.titleMedium),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.open_in_browser),
                    title: const Text('브라우저로 열기'),
                    subtitle: Text(widget.api.baseUrl),
                    onTap: () => widget.backend!.open(widget.api.baseUrl),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.terminal),
                    title: const Text('터미널에서 zaevis 명령 쓰기'),
                    subtitle: const Text('~/.local/bin 에 zaevis 명령을 등록합니다'),
                    onTap: () => _runTask('zaevis 명령 등록', const ['install']),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.restart_alt),
                    title: const Text('서버 다시 시작'),
                    onTap: () => _runTask('서버 다시 시작', const ['stop'], then: const ['start']),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('로그 폴더 열기'),
                    subtitle: const Text('~/.zaevis'),
                    onTap: () => widget.backend!.open('${widget.backend!.home}/.zaevis'),
                  ),
                ],
                const SizedBox(height: 16),
                Text('worklog 폴더', style: t.titleMedium),
                SelectableText(s.worklogDir, style: t.bodyMedium?.copyWith(fontFamily: 'monospace')),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

/// Optional OpenRouter re-ranking: the only place a search leaves this machine. Off until the user
/// turns it on and saves a key; the key is sent to the server once and only its last 4 chars come back.
class _RerankSection extends StatefulWidget {
  const _RerankSection({required this.api, required this.status, required this.onChanged});
  final WorklogApi api;
  final RerankStatus status;
  final VoidCallback onChanged;

  @override
  State<_RerankSection> createState() => _RerankSectionState();
}

class _RerankSectionState extends State<_RerankSection> {
  final _key = TextEditingController();
  bool _busy = false;
  String? _check;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() task) async {
    setState(() {
      _busy = true;
      _check = null;
    });
    try {
      final msg = await task();
      if (mounted && msg != null) toast(context, msg);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final s = widget.status;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.cloud_outlined),
        title: const Text('검색 결과 재정렬 (OpenRouter)'),
        subtitle: Text(s.hasKey
            ? '검색 상위 25개 문단을 OpenRouter의 ${s.model} 모델로 다시 정렬합니다. 켜면 검색어와 그 문단이 외부로 나갑니다.'
            : '켜려면 아래에 OpenRouter API 키를 저장하세요. 키가 없으면 켜도 아무것도 전송되지 않습니다.'),
        value: s.enabled,
        onChanged: _busy ? null : (v) => _run(() async => (await widget.api.updateRerank(enabled: v)).active ? '재정렬을 켰습니다' : (v ? '켰지만 키가 없어 전송되지 않습니다' : '재정렬을 껐습니다')),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 56, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _key,
                obscureText: true,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'OpenRouter API 키',
                  hintText: s.hasKey ? '저장됨 •••• ${s.keyHint}' : 'sk-or-v1-…',
                  helperText: s.hasKey ? '새 키를 넣고 저장하면 바뀝니다. 키는 ~/.zaevis/secrets.json(소유자만 읽기)에만 저장됩니다.' : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _busy || _key.text.trim().isEmpty
                  ? null
                  : () => _run(() async {
                        await widget.api.updateRerank(apiKey: _key.text.trim());
                        _key.clear();
                        return '키를 저장했습니다';
                      }),
              child: const Text('저장'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _busy || (!s.hasKey && _key.text.trim().isEmpty)
                  ? null
                  : () => _run(() async {
                        final r = await widget.api.testRerankKey(_key.text.trim().isEmpty ? null : _key.text.trim());
                        setState(() => _check = r.message);
                        return null;
                      }),
              child: const Text('연결 확인'),
            ),
            if (s.hasKey)
              TextButton(
                onPressed: _busy ? null : () => _run(() async => (await widget.api.updateRerank(apiKey: '')).hasKey ? null : '키를 지웠습니다'),
                child: const Text('키 삭제'),
              ),
          ]),
          if (_check != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_check!, style: t.bodySmall)),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('지금 외부로 나가는 요청: ${s.external}', style: t.bodySmall?.copyWith(color: s.active ? scheme.error : scheme.outline)),
          ),
        ]),
      ),
    ]);
  }
}

/// Weekly digest ("지식화"): which agent on this Mac turns inbox + sources into log lines, project
/// updates and monthly summaries. Runs with what the user already has — an installed agent CLI on
/// their own subscription, or the saved OpenRouter key — and never asks for a new account.
class _DigestSection extends StatefulWidget {
  const _DigestSection({required this.api});
  final WorklogApi api;

  @override
  State<_DigestSection> createState() => _DigestSectionState();
}

class _DigestSectionState extends State<_DigestSection> {
  late Future<DigestStatus> _future = widget.api.digest();
  Timer? _poll;
  late final _model = TextEditingController();

  @override
  void dispose() {
    _poll?.cancel();
    _model.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
        _future = widget.api.digest();
      });

  void _watch(DigestStatus s) {
    _poll?.cancel();
    if (s.running) _poll = Timer(const Duration(seconds: 4), _reload);
  }

  Future<void> _update({String? agent, String? model, bool? weekly}) async {
    try {
      await widget.api.updateDigest(agent: agent, model: model, weekly: weekly);
      if (mounted) toast(context, '저장했습니다');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    _reload();
  }

  Future<void> _run() async {
    try {
      await widget.api.runDigest();
      if (mounted) toast(context, '정리를 시작했습니다. 몇 분 걸립니다.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    _reload();
  }

  static const _labels = {'auto': '자동 (설치된 것 중 첫 번째)', 'claude': 'Claude Code', 'codex': 'Codex CLI', 'gemini': 'Gemini CLI', 'openrouter': 'OpenRouter API'};

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<DigestStatus>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
        if (snap.hasError) return ErrorPane(error: snap.error!, onRetry: _reload);
        final s = snap.data!;
        _watch(s);
        if (_model.text.isEmpty && s.model.isNotEmpty) _model.text = s.model;
        final chosen = s.agents.where((a) => a.id == s.chosen).firstOrNull;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('inbox의 전사본·세션 노트와 매일 수집한 원본을 읽어 로그 줄·프로젝트 상태·월간 정리를 씁니다. '
              '이 맥에 설치된 에이전트(본인 구독)나 저장된 OpenRouter 키 중 쓸 수 있는 것으로 돌립니다.', style: t.bodySmall),
          const SizedBox(height: 8),
          for (final a in s.agents)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(a.available ? Icons.check_circle_outline : Icons.radio_button_unchecked, color: a.available ? scheme.primary : scheme.outline),
              title: Text(a.title),
              subtitle: Text(a.detail, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: s.chosen == a.id ? const Chip(label: Text('사용'), visualDensity: VisualDensity.compact) : null,
            ),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: s.agent,
                decoration: const InputDecoration(labelText: '정리 에이전트'),
                items: [for (final e in _labels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: s.running ? null : (v) => v == null ? null : _update(agent: v),
              ),
            ),
            if (s.agent == 'openrouter' || s.chosen == 'openrouter') ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _model,
                  decoration: const InputDecoration(labelText: 'OpenRouter 모델', hintText: 'anthropic/claude-sonnet-4.5'),
                  onSubmitted: (v) => _update(model: v.trim()),
                ),
              ),
            ],
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.event_repeat),
            title: const Text('매주 월요일 자동 정리'),
            subtitle: Text(s.weekly ? '다음 실행: ${s.nextWeekly ?? '다음 월요일'} (매일 수집 뒤에 이어서)' : '끄면 아래 버튼으로만 실행합니다'),
            value: s.weekly,
            onChanged: s.running ? null : (v) => _update(weekly: v),
          ),
          Row(children: [
            FilledButton.icon(
              onPressed: s.running || chosen == null ? null : _run,
              icon: s.running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
              label: Text(s.running ? '정리 중… (${_labels[s.runningAgent] ?? s.runningAgent})' : '지금 정리하기'),
            ),
            const SizedBox(width: 12),
            if (chosen == null) Expanded(child: Text('쓸 수 있는 에이전트가 없습니다. Claude Code·Codex·Gemini CLI를 설치하거나 위에서 OpenRouter 키를 저장하세요.', style: t.bodySmall?.copyWith(color: scheme.error))),
          ]),
          if (s.last != null) ...[
            const SizedBox(height: 8),
            Text('마지막 정리: ${s.last!.ok ? '완료' : '실패'} · ${_labels[s.last!.agent] ?? s.last!.agent} · ${s.last!.at?.toLocal().toString().split('.').first ?? ''}',
                style: t.bodySmall?.copyWith(color: s.last!.ok ? null : scheme.error)),
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
              child: SelectableText(s.last!.report.length > 1200 ? '…${s.last!.report.substring(s.last!.report.length - 1200)}' : s.last!.report,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12), minLines: 1, maxLines: 14),
            ),
          ],
        ]);
      },
    );
  }
}
