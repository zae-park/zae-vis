import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/markdown_view.dart';
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

const agentTitles = {'claude': 'Claude Code', 'codex': 'Codex CLI', 'gemini': 'Gemini CLI', 'openrouter': 'OpenRouter'};

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
  Future<AskStatus>? _askStatus;
  Future<AskResult>? _answer;
  String _question = '';
  int? _focusedSource;
  final _sourceKeys = <int, GlobalKey>{};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? _]) {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      if (_mode == SearchMode.ask) {
        _question = q;
        _focusedSource = null;
        // FutureBuilder subscribes a frame later; a quick 409 must not count as an unhandled error
        _answer = widget.api.ask(q)..ignore();
      } else {
        _query = q;
        // ask for more than fits one screen: the filters below narrow it on the client
        _result = widget.api.search(q, topK: 40);
      }
    });
  }

  void _setMode(SearchMode m) {
    setState(() {
      _mode = m;
      if (m == SearchMode.ask) _askStatus ??= widget.api.askStatus();
    });
    widget.focusNode?.requestFocus();
  }

  /// Scrolls the source card [n] into view and outlines it.
  void _showSource(int n) {
    setState(() => _focusedSource = n);
    final ctx = _sourceKeys[n]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), alignment: 0.1);
  }

  @override
  Widget build(BuildContext context) {
    return Readable(
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
                child: SearchBar(
                  controller: _controller,
                  focusNode: widget.focusNode,
                  autoFocus: true,
                  hintText: _mode == SearchMode.ask ? '기록을 근거로 답합니다 (예: GA4 매핑은 왜 미뤘지?)' : '무엇을 했는지, 왜 그렇게 정했는지 물어보세요 (예: GA4 캠페인 매핑)',
                  leading: Icon(_mode.icon),
                  onSubmitted: _submit,
                  trailing: [IconButton(onPressed: _submit, icon: const Icon(Icons.arrow_forward), tooltip: _mode == SearchMode.ask ? '답 만들기' : '검색')],
                ),
              ),
            ]),
          ),
          Expanded(child: _mode == SearchMode.ask ? _askBody() : _searchBody()),
        ],
      ),
    );
  }

  Widget _askBody() {
    if (_answer == null) return _AskIntro(status: _askStatus!, onOpenSettings: widget.onOpenSettings);
    return FutureBuilder<AskResult>(
      future: _answer,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return _AskProgress(question: _question, status: _askStatus!);
        if (snap.hasError) {
          final e = snap.error!;
          final noAgent = e is ApiException && e.status == 409 && e.message.contains('에이전트가 없');
          return _AskError(error: e, onRetry: noAgent ? null : _submit, onOpenSettings: noAgent ? widget.onOpenSettings : null);
        }
        final r = snap.data!;
        for (final s in r.sources) {
          _sourceKeys.putIfAbsent(s.n, GlobalKey.new);
        }
        final agent = agentTitles[r.agent] ?? r.agent;
        // not lazy on purpose: every source card must exist so [n] can scroll to it
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _AnswerCard(result: r, agent: agent, onCite: _showSource),
            const SizedBox(height: 12),
            SectionHeader('근거 ${r.sources.length}개', subtitle: '답의 [번호]를 누르면 해당 발췌로 갑니다. 발췌를 누르면 원문이 열립니다.'),
            for (final s in r.sources) ...[
              const SizedBox(height: 8),
              _SourceCard(key: _sourceKeys[s.n], source: s, focused: _focusedSource == s.n, onOpen: () => FileScreen.open(context, widget.api, s.path)),
            ],
          ],
        );
      },
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

/// Before the first question: what will answer, or how to get an agent.
class _AskIntro extends StatelessWidget {
  const _AskIntro({required this.status, this.onOpenSettings});
  final Future<AskStatus> status;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<AskStatus>(
      future: status,
      builder: (context, snap) {
        final st = snap.data;
        final agent = st?.chosenAgent;
        final noAgent = snap.connectionState == ConnectionState.done && !snap.hasError && st?.chosen == null;
        return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const EmptyPane('검색한 문단만 근거로 답을 씁니다\n'
              '질문으로 기록을 검색하고, 상위 문단을 이 맥에 있는 에이전트(Claude Code·Codex·Gemini CLI)나 OpenRouter에 넣어 출처 [번호]가 달린 답을 받습니다. 에이전트는 파일을 읽기만 합니다.', icon: Icons.question_answer_outlined),
          if (agent != null) Text('답은 ${agent.title}가 씁니다 · ${agent.detail}', style: t.bodySmall?.copyWith(color: scheme.outline)),
          if (noAgent) ...[
            Text('답을 쓸 에이전트가 없습니다. Claude Code·Codex·Gemini CLI 중 하나를 설치하거나 설정에서 OpenRouter 키를 저장하세요.', style: t.bodySmall?.copyWith(color: scheme.error), textAlign: TextAlign.center),
            if (onOpenSettings != null) Padding(padding: const EdgeInsets.only(top: 10), child: FilledButton.tonalIcon(onPressed: onOpenSettings, icon: const Icon(Icons.settings_outlined), label: const Text('설정 열기'))),
          ],
          const SizedBox(height: 24),
        ]);
      },
    );
  }
}

class _AskProgress extends StatelessWidget {
  const _AskProgress({required this.question, required this.status});
  final String question;
  final Future<AskStatus> status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        FutureBuilder<AskStatus>(
          future: status,
          builder: (context, snap) => Text('${snap.data?.chosenAgent?.title ?? '에이전트'}가 기록을 읽고 답을 쓰는 중… (수십 초)', style: t.bodyMedium),
        ),
        const SizedBox(height: 4),
        Text(question, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
      ]),
    );
  }
}

class _AskError extends StatelessWidget {
  const _AskError({required this.error, this.onRetry, this.onOpenSettings});
  final Object error;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (onOpenSettings == null) return ErrorPane(error: error, onRetry: onRetry);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.smart_toy_outlined, size: 40),
          const SizedBox(height: 12),
          Text((error as ApiException).message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: onOpenSettings, icon: const Icon(Icons.settings_outlined), label: const Text('설정 열기')),
        ]),
      ),
    );
  }
}

/// The question, the answer with tappable [n] marks, and which agent wrote it.
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.result, required this.agent, required this.onCite});
  final AskResult result;
  final String agent;
  final ValueChanged<int> onCite;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(result.question, style: t.titleSmall),
          const SizedBox(height: 10),
          SelectableText.rich(citationSpan(context, result.answer, sources: result.sources.length, base: t.bodyLarge, onCite: onCite), minLines: 1, maxLines: 60),
          const SizedBox(height: 10),
          Text('$agent · ${(result.ms / 1000).toStringAsFixed(1)}초 · 발췌 ${result.sources.length}개만 근거로 썼습니다', style: t.labelSmall?.copyWith(color: scheme.outline)),
        ]),
      ),
    );
  }
}

/// [text] with every "[n]" (1 ≤ n ≤ [sources]) rendered as a small tappable mark.
TextSpan citationSpan(BuildContext context, String text, {required int sources, TextStyle? base, required ValueChanged<int> onCite}) {
  final scheme = Theme.of(context).colorScheme;
  final children = <InlineSpan>[];
  var last = 0;
  for (final m in RegExp(r'\[(\d+)\]').allMatches(text)) {
    final n = int.parse(m.group(1)!);
    if (n < 1 || n > sources) continue;
    if (m.start > last) children.add(TextSpan(text: text.substring(last, m.start)));
    children.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: InkWell(
          onTap: () => onCite(n),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Text('$n', style: TextStyle(fontSize: (base?.fontSize ?? 14) - 3, fontWeight: FontWeight.w700, color: scheme.primary)),
          ),
        ),
      ),
    ));
    last = m.end;
  }
  if (last < text.length) children.add(TextSpan(text: text.substring(last)));
  return TextSpan(style: base, children: children);
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({super.key, required this.source, required this.focused, required this.onOpen});
  final AskSource source;
  final bool focused;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      shape: focused ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.primary, width: 1.5)) : null,
      child: InkWell(
        onTap: source.path.isEmpty ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 12, backgroundColor: focused ? scheme.primary : null, child: Text('${source.n}', style: t.labelSmall?.copyWith(color: focused ? scheme.onPrimary : null))),
              const SizedBox(width: 10),
              Expanded(child: Text(source.label, style: t.titleSmall)),
            ]),
            if (source.passage.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(source.passage, style: t.bodyMedium, minLines: 1, maxLines: 14),
            ],
            if (source.path.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(source.path, style: ZaevisTheme.mono.copyWith(fontSize: 11.5, color: scheme.outline)),
            ],
          ]),
        ),
      ),
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
