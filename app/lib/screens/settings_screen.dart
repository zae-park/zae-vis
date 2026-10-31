import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../backend/backend.dart';
import '../models.dart';
import '../shortcuts.dart';
import '../theme.dart';
import '../widgets/agent_rail.dart';
import '../widgets/common.dart';
import '../widgets/input_dialogs.dart';
import '../widgets/task_dialog.dart';
import 'review_screen.dart';

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
    await runBackendTask(context, widget.backend!, title, args, then: then);
    if (mounted) _reload();
  }

  /// Installs Kiwi through the bundle, then offers the rebuild from scratch the new tokenizer needs.
  Future<void> _installKiwi() async {
    final ok = await runBackendTask(context, widget.backend!, '한국어 형태소 분석 (Kiwi) 설치', const ['ext', 'install', 'kiwi']);
    if (!mounted) return;
    _reload();
    if (!ok) return;
    final rebuild = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('처음부터 다시 색인할까요?'),
        content: const Text('Kiwi를 설치했습니다. 지금 있는 색인은 공백 기준으로 만든 것이라, 처음부터 다시 색인해야 조사·어미가 붙은 말도 찾습니다. '
            '몇 분 걸리고, 창을 닫아도 계속됩니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('나중에')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('다시 색인')),
        ],
      ),
    );
    if (rebuild != true || !mounted) return;
    try {
      await widget.api.refreshIndex(force: true);
      if (mounted) toast(context, '처음부터 다시 색인을 시작했습니다');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) _reload();
  }

  Future<void> _update({String? dailyAt, bool? indexOnInject, bool? localEmbedding, bool? notifications, String? hotkey, List<String>? memoryPaths}) async {
    try {
      await widget.api.updateSettings(dailyAt: dailyAt, indexOnInject: indexOnInject, localEmbedding: localEmbedding, notifications: notifications, hotkey: hotkey, memoryPaths: memoryPaths);
      if (hotkey != null) await GlobalHotkey.update(hotkey);
      if (mounted) toast(context, memoryPaths != null ? '폴더를 색인에 넣었습니다. 처음부터 다시 색인합니다.' : '저장했습니다');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) _reload();
  }

  Future<void> _addMemory(AppSettings s) async {
    final path = await showDialog<String>(
      context: context,
      builder: (context) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('색인할 폴더'),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: '폴더 경로', hintText: '/Users/…/worklog'),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('추가')),
          ],
        );
      },
    );
    if (path == null || path.isEmpty) return;
    await _update(memoryPaths: [...s.memoryPaths, path]);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: Readable(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 24, 32), children: [
          Text('서버', style: t.titleMedium),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Row(children: [
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
            ),
          ),
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
              final wide = MediaQuery.sizeOf(context).width >= 1100;
              final collect = <Widget>[
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
                if (s.tokenizer != null) _KiwiTile(status: s.tokenizer!, managed: _managed, onInstall: _installKiwi),
                if (s.rerank != null) _RerankSection(api: widget.api, status: s.rerank!, onChanged: _reload),
              ];
              final side = <Widget>[
                Text('알림', style: t.titleMedium),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.notifications_outlined),
                  title: const Text('시스템 알림'),
                  subtitle: const Text('정리가 끝나 검토할 것이 생겼을 때, 수집이 실패했을 때, 녹음 전사가 끝났을 때 알립니다. '
                      '서버가 보내므로 앱 창이 닫혀 있어도 옵니다.'),
                  value: s.notifications,
                  onChanged: (v) => _update(notifications: v),
                ),
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
                _HfLogin(api: widget.api, backend: widget.backend),
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
                Text('단축키', style: t.titleMedium),
                const SizedBox(height: 6),
                for (final (keys, what) in AppShortcuts.describe(hotkey: s.hotkey))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Container(
                        constraints: const BoxConstraints(minWidth: 110),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(6)),
                        child: Text(keys, style: ZaevisTheme.mono.copyWith(fontSize: 12, color: scheme.onSurface), textAlign: TextAlign.center),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(what, style: t.bodyMedium)),
                      if (what.contains('전역')) ...[
                        TextButton(
                          onPressed: () async {
                            final spec = await showHotkeyDialog(context, current: s.hotkey);
                            if (spec != null) await _update(hotkey: spec);
                          },
                          child: const Text('바꾸기'),
                        ),
                        if (s.hotkey.isNotEmpty) TextButton(onPressed: () => _update(hotkey: ''), child: const Text('기본값')),
                      ],
                    ]),
                  ),
                const SizedBox(height: 16),
                Text('색인 폴더', style: t.titleMedium),
                const SizedBox(height: 4),
                Text('기록 폴더는 항상 색인됩니다. 노트가 다른 폴더에 있으면 추가하세요. 추가하거나 빼면 처음부터 다시 색인합니다.', style: t.bodySmall),
                const SizedBox(height: 6),
                SelectableText(s.worklogDir, style: ZaevisTheme.mono),
                for (final p in s.memoryPaths)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(p, style: ZaevisTheme.mono, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      tooltip: '색인에서 빼기',
                      icon: const Icon(Icons.close),
                      onPressed: () => _update(memoryPaths: [for (final x in s.memoryPaths) if (x != p) x]),
                    ),
                  ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(onPressed: () => _addMemory(s), icon: const Icon(Icons.create_new_folder_outlined), label: const Text('폴더 추가')),
                ),
              ];
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('정리 (지식화)', style: t.titleMedium),
                _DigestSection(api: widget.api),
                const SizedBox(height: 20),
                if (wide)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: collect)),
                    const SizedBox(width: 36),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: side)),
                  ])
                else ...[
                  ...collect,
                  const SizedBox(height: 16),
                  ...side,
                ],
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
/// "한국어 형태소 분석 (Kiwi)": what the keyword index tokenizes with, and the one-click install when it is missing.
class _KiwiTile extends StatelessWidget {
  const _KiwiTile({required this.status, required this.managed, required this.onInstall});
  final TokenizerStatus status;
  final bool managed;
  final Future<void> Function() onInstall;

  @override
  Widget build(BuildContext context) {
    final k = status.kiwi;
    final String subtitle;
    if (k.installed) {
      subtitle = '${status.label}${k.source == 'zaevis' ? '' : ' · ${k.source == 'env' ? 'KIWI_LIBRARY_PATH·KIWI_MODEL_PATH' : k.library}'}';
    } else if (!k.installable) {
      subtitle = '이 플랫폼용 Kiwi 릴리스가 없습니다. 직접 받아 ~/.local/kiwi/{lib,models}에 두거나 KIWI_LIBRARY_PATH·KIWI_MODEL_PATH를 설정하세요.';
    } else if (managed) {
      subtitle = '설치하면 조사·어미가 붙은 말(인증서를)도 검색어(인증서)로 찾습니다. 키워드 검색이 한국어 형태소 단위가 됩니다 (${k.downloadMb}MB 다운로드, 설치 뒤 처음부터 다시 색인).';
    } else {
      subtitle = "설치되지 않음 — 터미널에서 'zaevis ext install kiwi' 뒤 처음부터 다시 색인";
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(k.installed ? (status.needsReindex ? Icons.sync_problem_outlined : Icons.check_circle_outline) : Icons.translate_outlined),
      title: const Text('한국어 형태소 분석 (Kiwi)'),
      subtitle: Text(subtitle),
      trailing: !k.installed && k.installable && managed ? FilledButton.tonal(onPressed: onInstall, child: const Text('설치')) : null,
    );
  }
}

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
  late Future<List<ProposalSummary>> _proposals = _fetchProposals();

  Future<List<ProposalSummary>> _fetchProposals() => widget.api.proposals().catchError((_) => <ProposalSummary>[]);
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
        _proposals = _fetchProposals();
      });

  Future<void> _review(String id) async {
    if (await ReviewScreen.open(context, widget.api, id)) _reload();
  }

  void _watch(DigestStatus s) {
    _poll?.cancel();
    if (s.running) _poll = Timer(const Duration(seconds: 4), _reload);
  }

  Future<void> _update({String? agent, String? model, bool? weekly, bool? review, List<String>? order, List<String>? skip}) async {
    try {
      await widget.api.updateDigest(agent: agent, model: model, weekly: weekly, review: review, order: order, skip: skip);
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

  static const _labels = {'auto': '자동 (할당량이면 다음 서비스)', 'claude': 'Claude Code', 'codex': 'Codex CLI', 'cursor': 'Cursor', 'gemini': 'Gemini CLI', 'openrouter': 'OpenRouter API'};

  String _quotaNote(List<RailStop> rail) {
    final names = rail.where((s) => s.state == 'quota').map((s) => s.title).toList();
    return names.isEmpty ? '' : ' · ${names.join(', ')} 할당량으로 건너뜀';
  }

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
              '블록을 왼쪽부터 시도하고, 할당량으로 막히면 다음 블록으로 넘깁니다. 끌어다 놓아 순서를 바꿉니다.', style: t.bodySmall),
          const SizedBox(height: 8),
          if (s.rail.isNotEmpty) AgentRail(stops: s.rail),
          _AgentOrder(
            agents: s.agents,
            skip: s.skip,
            chosen: s.chosen,
            enabled: !s.running,
            onReorder: (order) => _update(agent: 'auto', order: order, skip: s.skip),
            onSkip: (skip) => _update(agent: 'auto', order: [for (final a in s.agents) a.id], skip: skip),
          ),
          if (!s.skip.contains('openrouter') && (s.chosen == 'openrouter' || s.agents.any((a) => a.id == 'openrouter' && a.available))) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: TextField(
                  controller: _model,
                  decoration: const InputDecoration(labelText: 'OpenRouter 모델', hintText: 'anthropic/claude-sonnet-4.5'),
                  onSubmitted: (v) => _update(model: v.trim()),
                ),
              ),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.rule),
            title: const Text('적용 전에 검토'),
            subtitle: Text(s.review
                ? '정리 결과를 바로 쓰지 않고 제안으로 둡니다. 로그 탭이나 아래에서 줄마다 골라 적용합니다.'
                : '끄면 에이전트가 쓴 내용이 바로 worklog에 들어갑니다.'),
            value: s.review,
            onChanged: s.running ? null : (v) => _update(review: v),
          ),
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
          FutureBuilder<List<ProposalSummary>>(
            future: _proposals,
            builder: (context, ps) {
              final pending = (ps.data ?? const <ProposalSummary>[]).where((p) => p.pending).toList();
              if (pending.isEmpty) return const SizedBox.shrink();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 8),
                Text('검토 대기 ${pending.length}건', style: t.labelLarge?.copyWith(color: scheme.primary)),
                for (final p in pending)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.rule),
                    title: Text('${p.createdAt?.toLocal().toString().split('.').first ?? p.id} · ${_labels[p.agent] ?? p.agent}'),
                    subtitle: Text('로그 ${p.lines}줄 · 프로젝트 ${p.projects}개 · 월간 정리 ${p.summaries}개 · inbox ${p.processed}개'),
                    trailing: FilledButton.tonal(onPressed: () => _review(p.id), child: const Text('검토하기')),
                  ),
              ]);
            },
          ),
          if (s.last != null) ...[
            const SizedBox(height: 8),
            Text('마지막 정리: ${s.last!.ok ? (s.last!.proposalId != null ? '검토 대기' : '완료') : '실패'} · ${_labels[s.last!.agent] ?? s.last!.agent}${_quotaNote(s.last!.rail)} · ${s.last!.at?.toLocal().toString().split('.').first ?? ''}',
                style: t.bodySmall?.copyWith(color: s.last!.ok ? null : scheme.error)),
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
              child: SelectableText(s.last!.report.length > 1200 ? '…${s.last!.report.substring(s.last!.report.length - 1200)}' : s.last!.report,
                  style: ZaevisTheme.mono.copyWith(fontSize: 12), minLines: 1, maxLines: 14),
            ),
          ],
        ]);
      },
    );
  }
}

/// Fallback order as blocks. Drag to reorder. The switch keeps a service in the line without a checkbox list.
class _AgentOrder extends StatelessWidget {
  const _AgentOrder({required this.agents, required this.skip, required this.chosen, required this.enabled, required this.onReorder, required this.onSkip});
  final List<AgentInfo> agents;
  final List<String> skip;
  final String? chosen;
  final bool enabled;
  final ValueChanged<List<String>> onReorder;
  final ValueChanged<List<String>> onSkip;

  @override
  Widget build(BuildContext context) {
    if (agents.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 168,
      child: ReorderableListView(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.symmetric(vertical: 4),
        onReorder: (oldIndex, newIndex) {
          if (!enabled) return;
          if (newIndex > oldIndex) newIndex -= 1;
          final ids = [for (final a in agents) a.id];
          final moved = ids.removeAt(oldIndex);
          ids.insert(newIndex, moved);
          onReorder(ids);
        },
        children: [
          for (var i = 0; i < agents.length; i++)
            _AgentBlock(
              key: ValueKey(agents[i].id),
              agent: agents[i],
              index: i + 1,
              dragIndex: i,
              included: !skip.contains(agents[i].id),
              chosen: chosen == agents[i].id,
              enabled: enabled,
              onIncluded: (v) {
                final next = [for (final id in skip) id];
                if (v) {
                  next.remove(agents[i].id);
                } else if (!next.contains(agents[i].id)) {
                  next.add(agents[i].id);
                }
                onSkip(next);
              },
            ),
        ],
      ),
    );
  }
}

class _AgentBlock extends StatelessWidget {
  const _AgentBlock({super.key, required this.agent, required this.index, required this.dragIndex, required this.included, required this.chosen, required this.enabled, required this.onIncluded});
  final AgentInfo agent;
  final int index;
  final int dragIndex;
  final bool included;
  final bool chosen;
  final bool enabled;
  final ValueChanged<bool> onIncluded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final note = agent.needsLogin ? agent.loginNote : agent.detail;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: 210,
        child: Material(
          color: included ? scheme.surfaceContainerLow : scheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: chosen ? scheme.primary : scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                ReorderableDragStartListener(
                  index: dragIndex,
                  enabled: enabled,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('$index', style: t.labelLarge?.copyWith(color: scheme.primary)),
                    const SizedBox(width: 6),
                    Icon(Icons.drag_indicator, size: 16, color: scheme.outline),
                  ]),
                ),
                const Spacer(),
                if (chosen) const Chip(label: Text('사용'), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ]),
              const SizedBox(height: 6),
              Text(agent.title, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(note, style: t.bodySmall?.copyWith(color: agent.needsLogin ? scheme.error : scheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
              const Spacer(),
              Row(children: [
                Text(included ? '순서에 포함' : '건너뜀', style: t.labelSmall),
                const Spacer(),
                Switch(value: included, onChanged: enabled ? onIncluded : null),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Records a new global hotkey: the user presses the combination, the dialog shows it and saves the
/// spec ("meta+shift+space"). A key without a modifier is refused — it would swallow typing everywhere.
Future<String?> showHotkeyDialog(BuildContext context, {required String current}) {
  return showDialog<String>(
    context: context,
    builder: (context) {
      String? spec = current.isEmpty ? null : current;
      String? warning;
      final focus = FocusNode();
      return StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('전역 단축키 바꾸기'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('쓰고 싶은 조합을 지금 누르세요. 수정키(⌘·⌃·⌥·⇧ 또는 Ctrl·Alt·Shift)와 글자·숫자·F키·Space를 조합합니다.'),
              const SizedBox(height: 16),
              Focus(
                focusNode: focus,
                autofocus: true,
                onKeyEvent: (_, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final got = HotkeySpec.fromEvent(event);
                  setLocal(() {
                    if (got == null) {
                      warning = HotkeySpec.isModifier(event) ? null : '수정키와 함께 눌러야 합니다';
                    } else {
                      spec = got;
                      warning = null;
                    }
                  });
                  return KeyEventResult.handled;
                },
                child: Builder(
                  builder: (context) {
                    final scheme = Theme.of(context).colorScheme;
                    final focused = Focus.of(context).hasFocus;
                    return InkWell(
                      onTap: () => focus.requestFocus(),
                      child: Container(
                        key: const ValueKey('hotkey-recorder'),
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: focused ? scheme.primary : scheme.outlineVariant, width: focused ? 2 : 1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(spec == null ? '여기에서 키를 누르세요' : HotkeySpec.label(spec!),
                            style: spec == null ? TextStyle(color: scheme.outline) : ZaevisTheme.mono.copyWith(fontSize: 18)),
                      ),
                    );
                  },
                ),
              ),
              if (warning != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(warning!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('기본값: ${HotkeySpec.label('')}', style: Theme.of(context).textTheme.bodySmall)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
            FilledButton(onPressed: spec == null || !HotkeySpec.isValid(spec!) ? null : () => Navigator.pop(context, spec), child: const Text('저장')),
          ],
        ),
      );
    },
  );
}

/// Hugging Face browser login for speaker diarization. The token stays on the server.
class _HfLogin extends StatefulWidget {
  const _HfLogin({required this.api, this.backend});
  final WorklogApi api;
  final Backend? backend;

  @override
  State<_HfLogin> createState() => _HfLoginState();
}

class _HfLoginState extends State<_HfLogin> {
  HfStatus? _hf;
  var _hidden = false;
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
      final hf = await widget.api.hfStatus();
      if (!mounted) return;
      setState(() {
        _hf = hf;
        _hidden = hf == null;
      });
      _watch(hf);
    } on ApiException {
      if (mounted) setState(() => _hidden = true);
    }
  }

  void _watch(HfStatus? hf) {
    _poll?.cancel();
    if (hf?.loginState != 'pending') return;
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final next = await widget.api.hfStatus();
        if (!mounted) return;
        setState(() => _hf = next);
        if (next == null || next.loginState != 'pending') _poll?.cancel();
      } catch (_) {}
    });
  }

  Future<void> _login() async {
    try {
      final hf = await widget.api.hfLogin();
      if (!mounted) return;
      setState(() => _hf = hf);
      final url = hf.verificationUri;
      if (url != null) await widget.backend?.open(url);
      _watch(hf);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _openAccept() async {
    final hf = _hf;
    if (hf == null) return;
    for (final id in hf.accept) {
      await widget.backend?.open('https://huggingface.co/$id');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final hf = _hf;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pending = hf?.loginState == 'pending';
    final String subtitle;
    if (hf == null) {
      subtitle = '로그인 상태를 확인하는 중…';
    } else if (pending && hf.userCode != null) {
      subtitle = '브라우저에서 Hugging Face에 로그인하고 코드 ${hf.userCode} 를 확인하세요.';
    } else if (hf.loginError != null) {
      subtitle = hf.loginError!;
    } else if (hf.loggedIn && hf.accept.isNotEmpty) {
      subtitle = '${hf.username ?? "계정"} 으로 연결됨. 화자 모델을 쓰려면 페이지에서 사용에 동의해야 합니다.';
    } else if (hf.loggedIn) {
      subtitle = '${hf.username ?? "계정"} 으로 연결됨. 녹음 글은 먼저 저장되고, 말한 사람은 그 뒤에 같은 파일에 붙습니다.';
    } else {
      subtitle = '녹음 글은 바로 저장됩니다. 말한 사람을 나누려면 로그인하세요. 구분은 글이 저장된 뒤에 이어집니다.';
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(hf?.loggedIn == true ? Icons.check_circle_outline : Icons.record_voice_over_outlined),
      title: const Text('화자 구분'),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(subtitle, style: hf?.loginError != null ? t.bodySmall?.copyWith(color: scheme.error) : null),
        if (hf != null && hf.accept.isNotEmpty)
          Wrap(spacing: 4, children: [
            TextButton(onPressed: _openAccept, child: const Text('동의 페이지')),
            TextButton(
              onPressed: () async {
                final next = await widget.api.hfCheck();
                if (mounted) setState(() => _hf = next);
              },
              child: const Text('다시 확인'),
            ),
          ]),
      ]),
      trailing: pending
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : hf?.loggedIn == true
              ? TextButton(
                  onPressed: () async {
                    final next = await widget.api.hfLogout();
                    if (mounted) setState(() => _hf = next);
                  },
                  child: const Text('연결 해제'),
                )
              : FilledButton.tonal(onPressed: hf == null ? null : _login, child: const Text('로그인')),
    );
  }
}
