import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.api, required this.onOpenIndex});
  final WorklogApi api;
  final VoidCallback onOpenIndex;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Future<SearchResult>? _result;
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? _]) {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _query = q;
      _result = widget.api.search(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Readable(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SearchBar(
              controller: _controller,
              hintText: '회의, 결정, 작업 내용을 검색 (예: GA4 캠페인 매핑)',
              leading: const Icon(Icons.search),
              onSubmitted: _submit,
              trailing: [IconButton(onPressed: _submit, icon: const Icon(Icons.arrow_forward), tooltip: '검색')],
            ),
          ),
          Expanded(
            child: _result == null
                ? const EmptyPane('worklog 폴더 전체(로그, 프로젝트, 요약, 전사본)를 AutoRAG로 검색합니다.\n'
                    '한국어는 형태소 단위로 찾습니다.', icon: Icons.manage_search)
                : FutureBuilder<SearchResult>(
                    future: _result,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) return ErrorPane(error: snap.error!, onRetry: _submit);
                      final r = snap.data!;
                      if (!r.ok) {
                        return _SearchError(result: r, onOpenIndex: widget.onOpenIndex);
                      }
                      if (r.hits.isEmpty) return EmptyPane('"$_query"에 대한 결과가 없습니다.');
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: r.hits.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _HitCard(hit: r.hits[i]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.result, required this.onOpenIndex});
  final SearchResult result;
  final VoidCallback onOpenIndex;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.info_outline, size: 40),
          const SizedBox(height: 12),
          Text(result.needsRefresh ? '아직 색인이 없습니다. 색인을 먼저 만들어 주세요.' : (result.errorMessage ?? '검색에 실패했습니다'),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: onOpenIndex, icon: const Icon(Icons.sync), label: const Text('색인 상태 열기')),
        ]),
      ),
    );
  }
}

class _HitCard extends StatelessWidget {
  const _HitCard({required this.hit});
  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 12, child: Text('${hit.number}', style: t.labelSmall)),
            const SizedBox(width: 10),
            Expanded(child: Text(hit.title, style: t.titleSmall, overflow: TextOverflow.ellipsis)),
          ]),
          if (hit.path.isNotEmpty) ...[
            const SizedBox(height: 4),
            SelectableText(hit.path, style: t.bodySmall?.copyWith(color: scheme.outline, fontFamily: 'monospace')),
          ],
          if (hit.snippet.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(hit.snippet, maxLines: 6, style: t.bodyMedium),
          ],
        ]),
      ),
    );
  }
}
