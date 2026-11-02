import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../recording_trail.dart';
import '../widgets/common.dart';
import '../widgets/hit_card.dart';
import '../widgets/record_dialog.dart';
import '../widgets/recording_trail_strip.dart';
import '../widgets/save_file.dart';
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

/// One chat for everything: each line is searched at once, questions also get an answer, and file requests get
/// download buttons (see chat_intent.dart). The full, filterable result list is a page behind "모두 보기".
class _SearchScreenState extends State<SearchScreen> {
  Inbox? _inbox;
  IndexStatus? _index;
  Timer? _trailTimer;
  late final AskController _chat = AskController(widget.api);

  @override
  void initState() {
    super.initState();
    _loadTrail();
  }

  @override
  void dispose() {
    _trailTimer?.cancel();
    _chat.dispose();
    super.dispose();
  }

  Future<void> _loadTrail() async {
    try {
      final inbox = await widget.api.inbox();
      final index = await widget.api.indexStatus();
      if (!mounted) return;
      setState(() {
        _inbox = inbox;
        _index = index;
      });
      _trailTimer?.cancel();
      if (inbox.transcribing) _trailTimer = Timer(const Duration(seconds: 2), _loadTrail);
    } catch (_) {}
  }

  void _openTrail(RecordingTrail item) {
    if (item.watch) {
      showRecordDialog(context, widget.api, watch: item.file);
      return;
    }
    final path = item.openPath;
    if (path != null) FileScreen.open(context, widget.api, path);
  }

  @override
  Widget build(BuildContext context) {
    return Readable(
      // results use the whole width; the conversation's source panel needs it too
      child: Column(
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 10, 8, 6), child: AskHeader(controller: _chat)),
          RecordingTrailStrip(items: _trails, onOpen: _openTrail),
          Expanded(
            child: AskView(
              controller: _chat,
              focusNode: widget.focusNode,
              onOpenSettings: widget.onOpenSettings,
              onOpenIndex: widget.onOpenIndex,
              index: _index,
              inbox: _inbox,
              onSent: _loadTrail,
            ),
          ),
        ],
      ),
    );
  }

  List<RecordingTrail> get _trails => _inbox == null ? const [] : recordingTrails(inbox: _inbox!, index: _index);
}

/// Every hit of one search with the source and period filters, opened from a search answer in the chat.
class SearchResultsScreen extends StatefulWidget {
  const SearchResultsScreen({super.key, required this.api, required this.query, required this.result, this.index, this.inbox});
  final WorklogApi api;
  final String query;
  final SearchResult result;
  final IndexStatus? index;
  final Inbox? inbox;

  static Future<void> open(BuildContext context, WorklogApi api, String query, SearchResult result, {IndexStatus? index, Inbox? inbox}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SearchResultsScreen(api: api, query: query, result: result, index: index, inbox: inbox)));

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  final Set<String> _kinds = {};
  SearchPeriod _period = SearchPeriod.all;

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
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
    return Scaffold(
      appBar: AppBar(title: Text('"${widget.query}" 검색 결과')),
      body: Readable(
        child: Column(children: [
          const SizedBox(height: 8),
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
                ? _emptyNote(total: r.hits.length, filtered: _kinds.isNotEmpty || _period != SearchPeriod.all)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: shown.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => HitCard(
                      hit: shown[i],
                      onOpen: () => FileScreen.open(context, widget.api, shown[i].path),
                      onDownload: () => saveWorklogFile(context, widget.api, shown[i].path),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _emptyNote({required int total, required bool filtered}) {
    final note = emptySearchNote(query: widget.query, total: total, shown: 0, filtered: filtered, index: widget.index, inbox: widget.inbox);
    final clear = filtered && total > 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(note, textAlign: TextAlign.center),
          if (clear) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() {
                _kinds.clear();
                _period = SearchPeriod.all;
              }),
              child: const Text('필터 지우기'),
            ),
          ],
        ]),
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

/// Why a search failed (no index yet, AutoRAG error) and the way to the index sheet.
class SearchErrorNote extends StatelessWidget {
  const SearchErrorNote({super.key, required this.result, this.onOpenIndex});
  final SearchResult result;
  final VoidCallback? onOpenIndex;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(result.needsRefresh ? '아직 색인이 없습니다. 색인을 먼저 만들어 주세요.' : (result.errorMessage ?? '검색에 실패했습니다')),
      if (onOpenIndex != null) ...[
        const SizedBox(height: 10),
        FilledButton.tonalIcon(onPressed: onOpenIndex, icon: const Icon(Icons.sync, size: 18), label: const Text('색인 상태 열기')),
      ],
    ]);
  }
}
