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

  void _reload() => setState(() => _future = widget.api.settings());

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
