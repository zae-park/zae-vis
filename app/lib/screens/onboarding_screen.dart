import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../backend/backend.dart';
import '../theme.dart';

/// First run of the packaged app: pick folders and sources, then setup + start + first collect.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.backend, required this.api, required this.onDone});
  final Backend backend;
  final WorklogApi api;
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

const _sources = [
  ('git', 'git 커밋', '코드 폴더 아래 모든 저장소의 커밋 (작성자별로 표시)'),
  ('claude-code', 'Claude Code 세션', '요청, 수정한 파일, 실행한 명령'),
  ('shell-history', '터미널 명령 이력', 'zsh 히스토리 (비밀값은 가림)'),
  ('transcripts', '회의 전사본', '전사 서비스 내보내기 폴더, 녹음 전사'),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final _worklog = TextEditingController(text: '${widget.backend.home}/worklog');
  late final _repos = TextEditingController(text: widget.backend.home);
  final Set<String> _enabled = {for (final s in _sources) s.$1};
  TimeOfDay _dailyAt = const TimeOfDay(hour: 18, minute: 30);

  /// Korean morphological tokenizer for keyword search, installed before the first index so it never needs a rebuild.
  bool _kiwi = true;

  bool _running = false;
  String? _error;
  final List<String> _log = [];
  final _scroll = ScrollController();

  @override
  void dispose() {
    _worklog.dispose();
    _repos.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pick(TextEditingController c) async {
    final dir = await FilePicker.platform.getDirectoryPath(initialDirectory: c.text);
    if (dir != null && mounted) setState(() => c.text = dir);
  }

  void _append(String line) {
    if (!mounted) return;
    setState(() => _log.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _start() async {
    String two(int n) => n.toString().padLeft(2, '0');
    final params = SetupParams(
      worklogDir: _worklog.text.trim(),
      reposRoot: _repos.text.trim(),
      dailyAt: '${two(_dailyAt.hour)}:${two(_dailyAt.minute)}',
      disabledSources: [for (final s in _sources) if (!_enabled.contains(s.$1)) s.$1],
    );
    setState(() {
      _running = true;
      _error = null;
      _log.clear();
    });
    try {
      await widget.backend.run(params.toArgs()).forEach(_append);
      if (_kiwi) {
        _append('› 한국어 형태소 분석기(Kiwi) 설치 — 첫 색인부터 조사·어미가 붙은 말도 찾습니다 (약 130MB)');
        try {
          await widget.backend.run(const ['ext', 'install', 'kiwi']).forEach(_append);
        } catch (e) {
          _append('! Kiwi 설치 실패 — 나중에 설정 → 검색에서 다시 설치할 수 있습니다: $e');
        }
      }
      _append('› 서버 시작');
      await widget.backend.ensureServer();
      _append('› 첫 수집 시작 (지난 7일치, 끝나면 검색 색인까지 백그라운드에서 이어집니다)');
      await widget.api.collect();
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = '$e';
        });
      }
    }
  }

  Widget _folder(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(child: TextField(controller: c, enabled: !_running, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: label))),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _running ? null : () => _pick(c), child: const Text('선택')),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final problem = widget.backend.problem;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(28), shrinkWrap: true, children: [
            Text('zaevis 시작하기', style: t.headlineMedium),
            const SizedBox(height: 6),
            Text('작업 기록을 어디에 모을지만 정하면 됩니다. 나머지는 앱이 알아서 설치하고 매일 모읍니다.', style: t.bodyMedium),
            if (problem != null) ...[
              const SizedBox(height: 16),
              Card(
                color: scheme.errorContainer,
                child: Padding(padding: const EdgeInsets.all(14), child: Text(problem, style: TextStyle(color: scheme.onErrorContainer))),
              ),
            ],
            const SizedBox(height: 24),
            _folder('기록을 모을 폴더 (worklog)', _worklog),
            _folder('코드 저장소들이 있는 폴더', _repos),
            const SizedBox(height: 20),
            Text('모을 데이터소스', style: t.titleMedium),
            for (final s in _sources)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled.contains(s.$1),
                onChanged: _running ? null : (v) => setState(() => v == true ? _enabled.add(s.$1) : _enabled.remove(s.$1)),
                title: Text(s.$2),
                subtitle: Text(s.$3),
              ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _kiwi,
              onChanged: _running ? null : (v) => setState(() => _kiwi = v == true),
              title: const Text('한국어 형태소 분석 (Kiwi) 설치'),
              subtitle: const Text('키워드 검색이 조사·어미가 붙은 말(인증서를)도 검색어(인증서)로 찾게 합니다. 약 130MB 다운로드, 나중에 설정에서도 설치할 수 있습니다.'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text('매일 ${_dailyAt.format(context)}에 수집하고 검색 색인 갱신'),
              trailing: TextButton(
                onPressed: _running
                    ? null
                    : () async {
                        final picked = await showTimePicker(context: context, initialTime: _dailyAt);
                        if (picked != null && mounted) setState(() => _dailyAt = picked);
                      },
                child: const Text('바꾸기'),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _running || problem != null || _worklog.text.trim().isEmpty ? null : _start,
              icon: _running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
              label: Text(_running ? '설정 중…' : '시작'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text('설정에 실패했습니다: $_error', style: TextStyle(color: scheme.error)),
            ],
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                height: 200,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                child: ListView.builder(
                  controller: _scroll,
                  itemCount: _log.length,
                  itemBuilder: (_, i) => Text(_log[i], style: ZaevisTheme.mono.copyWith(fontSize: 12)),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
