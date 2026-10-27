import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';

/// Shows AutoRAG index health and lets the user rebuild it. Polls while a refresh runs and shows
/// the phase and file counts as a progress bar.
class IndexSheet extends StatefulWidget {
  const IndexSheet({super.key, required this.api});
  final WorklogApi api;

  static Future<void> show(BuildContext context, WorklogApi api) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => IndexSheet(api: api),
      );

  @override
  State<IndexSheet> createState() => _IndexSheetState();
}

class _IndexSheetState extends State<IndexSheet> {
  IndexStatus? _status;
  Object? _error;
  Timer? _poll;
  DateTime? _startedAt;
  bool _justFinished = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final s = await widget.api.indexStatus();
      if (!mounted) return;
      final wasRefreshing = _status?.refreshing ?? false;
      setState(() {
        _status = s;
        _error = null;
        if (wasRefreshing && !s.refreshing) _justFinished = true;
        if (s.refreshing) _startedAt ??= DateTime.now();
        if (!s.refreshing) _startedAt = null;
      });
      _poll?.cancel();
      if (s.refreshing || s.embedding?.state == 'starting') _poll = Timer(const Duration(seconds: 2), _fetch);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _refresh({bool force = false}) async {
    setState(() {
      _justFinished = false;
      _startedAt = DateTime.now();
    });
    try {
      await widget.api.refreshIndex(force: force);
      await _fetch();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final s = _status;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: _error != null
            ? ErrorPane(error: _error!, onRetry: _fetch)
            : s == null
                ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
                : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('검색 색인 (AutoRAG Lite)', style: t.titleLarge),
                    const SizedBox(height: 12),
                    if (s.refreshing) _Progress(status: s, startedAt: _startedAt) else ...[
                      _row('상태', _justFinished ? '색인 완료' : _stateLabel(s.state)),
                      _row('최신 여부', s.stale ? '새 파일이 있음 — 다시 색인 필요' : '최신'),
                    ],
                    if (s.embedding != null) _row('의미 검색', s.embedding!.label),
                    if (s.lastError != null && !s.refreshing) _row('마지막 오류', s.lastError!),
                    for (final m in s.messages.take(4))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('· $m', style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    if (s.messages.length > 4)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('· 외 ${s.messages.length - 4}건', style: t.bodySmall),
                      ),
                    const SizedBox(height: 16),
                    Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      FilledButton.icon(
                        onPressed: s.refreshing ? null : () => _refresh(),
                        icon: s.refreshing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.sync),
                        label: Text(s.refreshing ? '색인 중…' : '색인 갱신'),
                      ),
                      OutlinedButton(
                        onPressed: s.refreshing ? null : () => _refresh(force: true),
                        child: const Text('처음부터 다시'),
                      ),
                      if (_justFinished) Icon(Icons.check_circle, color: scheme.primary, size: 20),
                    ]),
                    const SizedBox(height: 8),
                    Text(s.refreshing ? '창을 닫아도 색인은 계속됩니다.' : '처음 색인은 임베딩을 만드느라 몇 분 걸릴 수 있습니다.', style: t.bodySmall),
                  ]),
      ),
    );
  }

  String _stateLabel(String state) => switch (state) {
        'fresh' || 'ready' || 'succeeded' || 'completed' || 'success' => '준비됨',
        'failed' => '실패',
        'never' || '' => '아직 색인 안 함',
        'idle' => '대기',
        'not-configured' => 'AutoRAG 미설정',
        'unavailable' => '연결 실패',
        'running' || 'refreshing' || 'indexing' => '색인 중…',
        _ => state,
      };

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 96, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: SelectableText(v)),
        ]),
      );
}

/// Phase label, elapsed time and a bar that fills as files are read and embedded.
class _Progress extends StatelessWidget {
  const _Progress({required this.status, required this.startedAt});
  final IndexStatus status;
  final DateTime? startedAt;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = status.progress;
    final fraction = p?.fraction;
    final elapsed = startedAt == null ? null : DateTime.now().difference(startedAt!);
    final elapsedText = elapsed == null ? '' : elapsed.inMinutes >= 1 ? ' · ${elapsed.inMinutes}분 ${elapsed.inSeconds % 60}초' : ' · ${elapsed.inSeconds}초';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(p?.label ?? '색인 시작 중', style: t.titleSmall)),
          Text(fraction == null ? elapsedText.replaceFirst(' · ', '') : '${(fraction * 100).round()}%$elapsedText', style: t.labelMedium),
        ]),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: fraction, minHeight: 8)),
        const SizedBox(height: 8),
        Text(_steps(p?.phase ?? ''), style: t.bodySmall),
      ]),
    );
  }

  /// "본문 읽기 → 임베딩·색인 → 마무리" with the current step marked.
  String _steps(String phase) {
    const steps = [('parsed', '본문 읽기'), ('minsync', '임베딩·색인'), ('finalizing', '마무리')];
    final current = switch (phase) {
      'parsed' || '' => 0,
      'minsync' => 1,
      _ => 2,
    };
    return [for (var i = 0; i < steps.length; i++) i == current ? '▶ ${steps[i].$2}' : steps[i].$2].join('  →  ');
  }
}
