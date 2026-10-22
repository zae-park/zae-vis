import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';

/// Shows AutoRAG index health and lets the user rebuild it. Polls while a refresh runs.
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
      setState(() {
        _status = s;
        _error = null;
      });
      _poll?.cancel();
      if (s.refreshing) _poll = Timer(const Duration(seconds: 3), _fetch);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _refresh({bool force = false}) async {
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
                    _row('상태', s.refreshing ? '색인 중…' : _stateLabel(s.state)),
                    _row('최신 여부', s.stale ? '새 파일이 있음 — 다시 색인 필요' : '최신'),
                    if (s.lastError != null) _row('마지막 오류', s.lastError!),
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
                    if (s.refreshing) const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      FilledButton.icon(
                        onPressed: s.refreshing ? null : () => _refresh(),
                        icon: const Icon(Icons.sync),
                        label: const Text('색인 갱신'),
                      ),
                      OutlinedButton(
                        onPressed: s.refreshing ? null : () => _refresh(force: true),
                        child: const Text('처음부터 다시'),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text('처음 색인은 임베딩을 만드느라 몇 분 걸릴 수 있습니다.', style: t.bodySmall),
                  ]),
      ),
    );
  }

  String _stateLabel(String state) => switch (state) {
        'fresh' || 'ready' || 'succeeded' || 'completed' => '준비됨',
        'failed' => '실패',
        'never' || '' => '아직 색인 안 함',
        'idle' => '대기',
        'not-configured' => 'AutoRAG 미설정',
        'unavailable' => '연결 실패',
        'running' || 'refreshing' => '색인 중…',
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
