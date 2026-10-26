import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/markdown_view.dart';
import 'file_screen.dart';

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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: SearchBar(
              controller: _controller,
              autoFocus: true,
              hintText: '무엇을 했는지, 왜 그렇게 정했는지 물어보세요 (예: GA4 캠페인 매핑)',
              leading: const Icon(Icons.search),
              onSubmitted: _submit,
              trailing: [IconButton(onPressed: _submit, icon: const Icon(Icons.arrow_forward), tooltip: '검색')],
            ),
          ),
          Expanded(
            child: _result == null
                ? const EmptyPane('기록 전체를 뜻으로 찾습니다\n'
                    '로그 · 프로젝트 · 월간 정리 · 전사본 · 수집 원본을 키워드와 의미(로컬 임베딩)로 함께 검색합니다. 결과를 누르면 원문이 열립니다.', icon: Icons.manage_search)
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
                        itemBuilder: (context, i) => _HitCard(hit: r.hits[i], onOpen: () => FileScreen.open(context, widget.api, r.hits[i].path)),
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
  const _HitCard({required this.hit, required this.onOpen});
  final SearchHit hit;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ctx = hit.context;
    final labels = ctx?.labels ?? [hit.title];
    return Opacity(
      opacity: hit.weak ? 0.55 : 1,
      child: Card.outlined(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: hit.path.isEmpty ? null : onOpen,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 12, child: Text('${hit.number}', style: t.labelSmall)),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    for (var i = 0; i < labels.length; i++)
                      Text(labels[i], style: i == 0 ? t.titleSmall : t.bodyMedium?.copyWith(color: i == labels.length - 1 && ctx?.author != null ? scheme.tertiary : null)),
                    if (hit.weak) Chip(label: const Text('약한 일치'), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, labelStyle: t.labelSmall),
                  ]),
                ),
              ]),
              if (hit.snippet.isNotEmpty) ...[
                const SizedBox(height: 8),
                // minLines matters: without it SelectableText reserves the full maxLines height
                SelectableText.rich(inlineSpan(context, hit.snippet, base: t.bodyMedium, highlight: ctx?.matched ?? const []), minLines: 1, maxLines: 8),
              ],
              if (hit.path.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(hit.path, style: ZaevisTheme.mono.copyWith(fontSize: 11.5, color: scheme.outline)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

