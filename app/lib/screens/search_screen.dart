import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/markdown_view.dart';
import 'ask_view.dart';
import 'file_screen.dart';

/// Period filter for search hits, by the date in the hit's path.
enum SearchPeriod {
  all('전체'),
  week('7일'),
  month('30일'),
  thisMonth('이번 달');

  const SearchPeriod(this.label);
  final String label;

  /// Whether a hit dated [date] ("YYYY-MM-DD" or "YYYY-MM"; null = undated) passes, as of [now].
  bool accepts(String? date, DateTime now) {
    if (this == all) return true;
    if (date == null) return false;
    if (this == thisMonth) return date.startsWith('${now.year}-${now.month.toString().padLeft(2, '0')}');
    final parts = date.split('-').map(int.tryParse).toList();
    if (parts.length < 2 || parts[0] == null || parts[1] == null) return false;
    // a monthly file counts by its last day, so a current month's log is "recent"
    final d = parts.length >= 3 && parts[2] != null ? DateTime(parts[0]!, parts[1]!, parts[2]!) : DateTime(parts[0]!, parts[1]! + 1, 0);
    return !d.isBefore(now.subtract(Duration(days: this == week ? 7 : 30)));
  }
}

/// 검색: ranked passages. 질문: the same search, then an agent writes an answer from the passages.
enum SearchMode {
  search('검색', Icons.search),
  ask('질문', Icons.question_answer_outlined);

  const SearchMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.api, required this.onOpenIndex, this.onOpenSettings, this.focusNode});
  final WorklogApi api;
  final VoidCallback onOpenIndex;

  /// Where to send the user when no agent can answer (null hides the button).
  final VoidCallback? onOpenSettings;

  /// Owned by the shell so ⌘K can focus the field from anywhere.
  final FocusNode? focusNode;

  /// The clock the period filter uses; tests pin it.
  static DateTime Function() clock = DateTime.now;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Future<SearchResult>? _result;
  String _query = '';
  final Set<String> _kinds = {};
  SearchPeriod _period = SearchPeriod.all;
  SearchMode _mode = SearchMode.search;
  // the conversation lives here so switching to 검색 and back keeps it
  late final AskController _ask = AskController(widget.api);

  @override
  void dispose() {
    _controller.dispose();
    _ask.dispose();
    super.dispose();
  }

  void _submit([String? _]) {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _query = q;
      // ask for more than fits one screen: the filters below narrow it on the client
      _result = widget.api.search(q, topK: 40);
    });
  }

  void _setMode(SearchMode m) {
    setState(() => _mode = m);
    widget.focusNode?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final ask = _mode == SearchMode.ask;
    return Readable(
      // the conversation's source panel needs the width: no reading-column limit in 질문 mode
      maxWidth: ask ? double.infinity : 860,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              SegmentedButton<SearchMode>(
                segments: [for (final m in SearchMode.values) ButtonSegment(value: m, label: Text(m.label), icon: Icon(m.icon, size: 18))],
                selected: {_mode},
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                onSelectionChanged: (s) => _setMode(s.first),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ask
                    ? AskHeader(controller: _ask)
                    : SearchBar(
                        controller: _controller,
                        focusNode: ask ? null : widget.focusNode,
                        autoFocus: true,
                        hintText: '무엇을 했는지, 왜 그렇게 정했는지 물어보세요 (예: GA4 캠페인 매핑)',
                        leading: const Icon(Icons.search),
                        onSubmitted: _submit,
                        trailing: [IconButton(onPressed: _submit, icon: const Icon(Icons.arrow_forward), tooltip: '검색')],
                      ),
              ),
            ]),
          ),
          Expanded(
            child: ask ? AskView(controller: _ask, focusNode: widget.focusNode, onOpenSettings: widget.onOpenSettings) : _searchBody(),
          ),
        ],
      ),
    );
  }

  Widget _searchBody() {
    return _result == null
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
                      final now = SearchScreen.clock();
                      final kinds = <String, (String, int)>{};
                      for (final h in r.hits) {
                        final c = h.context;
                        if (c == null) continue;
                        kinds.update(c.kind, (v) => (v.$1, v.$2 + 1), ifAbsent: () => (c.sourceLabel, 1));
                      }
                      final shown = r.hits
                          .where((h) => _kinds.isEmpty || (h.context != null && _kinds.contains(h.context!.kind)))
                          .where((h) => _period.accepts(h.context?.date, now))
                          .toList();
                      return Column(children: [
                        _Filters(
                          kinds: kinds,
                          selected: _kinds,
                          period: _period,
                          onKind: (k, on) => setState(() => on ? _kinds.add(k) : _kinds.remove(k)),
                          onPeriod: (p) => setState(() => _period = p),
                          shown: shown.length,
                          total: r.hits.length,
                        ),
                        Expanded(
                          child: shown.isEmpty
                              ? const EmptyPane('필터에 맞는 결과가 없습니다. 출처나 기간을 넓혀 보세요.', icon: Icons.filter_alt_off_outlined)
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                  itemCount: shown.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (context, i) => _HitCard(hit: shown[i], onOpen: () => FileScreen.open(context, widget.api, shown[i].path)),
                                ),
                        ),
                      ]);
                    },
                  );
  }
}

/// Chips: one per source kind in the results (with its count) and the period.
class _Filters extends StatelessWidget {
  const _Filters({required this.kinds, required this.selected, required this.period, required this.onKind, required this.onPeriod, required this.shown, required this.total});
  final Map<String, (String, int)> kinds;
  final Set<String> selected;
  final SearchPeriod period;
  final void Function(String kind, bool on) onKind;
  final ValueChanged<SearchPeriod> onPeriod;
  final int shown;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final e in kinds.entries)
              FilterChip(
                label: Text('${e.value.$1} ${e.value.$2}'),
                selected: selected.contains(e.key),
                visualDensity: VisualDensity.compact,
                onSelected: (on) => onKind(e.key, on),
              ),
            if (kinds.isNotEmpty) Container(width: 1, height: 20, color: scheme.outlineVariant, margin: const EdgeInsets.symmetric(horizontal: 4)),
            for (final p in SearchPeriod.values)
              ChoiceChip(
                label: Text(p.label),
                selected: period == p,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onPeriod(p),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 8),
          child: Text(shown == total ? '$total건' : '$shown / $total건', style: t.labelMedium?.copyWith(color: scheme.outline)),
        ),
      ]),
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
