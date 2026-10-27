import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'file_screen.dart';

const agentTitles = {'claude': 'Claude Code', 'codex': 'Codex CLI', 'gemini': 'Gemini CLI', 'openrouter': 'OpenRouter'};

/// One exchange in the thread: the question, then the answer (or the error) once the server replies.
class AskTurn {
  AskTurn(this.question, {this.result, this.error});
  final String question;
  AskResult? result;
  Object? error;
  bool get pending => result == null && error == null;
}

/// A source the user is looking at: which turn, which [n].
class SelectedSource {
  const SelectedSource(this.turn, this.n);
  final int turn;
  final int n;
}

/// The conversation state, owned by the screen so it survives switching between 검색 and 질문.
class AskController extends ChangeNotifier {
  AskController(this.api);
  final WorklogApi api;

  final List<AskTurn> turns = [];
  String? conversationId;
  late Future<AskStatus> status = api.askStatus();
  SelectedSource? selected;

  bool get busy => turns.any((t) => t.pending);

  void refreshStatus() {
    status = api.askStatus();
    notifyListeners();
  }

  /// Asks in the current conversation (a new one when there is none).
  Future<void> ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || busy) return;
    final turn = AskTurn(q);
    turns.add(turn);
    selected = null;
    notifyListeners();
    try {
      final r = await api.ask(q, conversationId: conversationId);
      turn.result = r;
      conversationId = r.conversationId.isEmpty ? conversationId : r.conversationId;
      status = api.askStatus(); // the conversation list changed
    } catch (e) {
      turn.error = e;
    }
    notifyListeners();
  }

  /// Re-asks a failed turn in place.
  Future<void> retry(AskTurn turn) async {
    if (turn.error == null || busy) return;
    turns.remove(turn);
    await ask(turn.question);
  }

  void newConversation() {
    turns.clear();
    conversationId = null;
    selected = null;
    notifyListeners();
  }

  Future<void> load(String id) async {
    final c = await api.conversation(id);
    turns
      ..clear()
      ..addAll(c.turns.map((r) => AskTurn(r.question, result: r)));
    conversationId = c.id;
    selected = null;
    notifyListeners();
  }

  Future<void> deleteCurrent() async {
    final id = conversationId;
    if (id != null) await api.deleteConversation(id);
    newConversation();
    refreshStatus();
  }

  void select(SelectedSource? s) {
    selected = s;
    notifyListeners();
  }

  AskSource? get selectedSource {
    final s = selected;
    if (s == null || s.turn >= turns.length) return null;
    final sources = turns[s.turn].result?.sources ?? const [];
    return sources.where((x) => x.n == s.n).firstOrNull;
  }
}

/// 질문 as a conversation: question and answer bubbles, a composer at the bottom, and the source
/// a citation points at in a panel on the right (wide) or a sheet from the bottom (narrow).
class AskView extends StatefulWidget {
  const AskView({super.key, required this.controller, this.focusNode, this.onOpenSettings});
  final AskController controller;
  final FocusNode? focusNode;
  final VoidCallback? onOpenSettings;

  /// Below this width the source opens as a bottom sheet instead of a side panel.
  static const panelBreakpoint = 980.0;

  @override
  State<AskView> createState() => _AskViewState();
}

class _AskViewState extends State<AskView> {
  final _composer = TextEditingController();

  AskController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void didUpdateWidget(AskView old) {
    super.didUpdateWidget(old);
    if (old.controller != c) {
      old.controller.removeListener(_changed);
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _composer.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _send([String? _]) {
    final q = _composer.text.trim();
    if (q.isEmpty || c.busy) return;
    _composer.clear();
    c.ask(q);
    widget.focusNode?.requestFocus();
  }

  void _cite(int turn, int n) {
    final wide = MediaQuery.sizeOf(context).width >= AskView.panelBreakpoint;
    c.select(SelectedSource(turn, n));
    if (!wide) _showSheet();
  }

  Future<void> _showSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => AnimatedBuilder(
        animation: c,
        builder: (context, _) => SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: _SourcePanel(controller: c, api: c.api, onClose: () => Navigator.pop(context), inSheet: true),
        ),
      ),
    );
    c.select(null);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AskView.panelBreakpoint;
    final thread = Column(children: [
      Expanded(child: c.turns.isEmpty ? _Intro(status: c.status, onOpenSettings: widget.onOpenSettings) : _thread(context)),
      _composerBar(context),
    ]);
    if (!wide || c.selectedSource == null) return thread;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: thread),
      SizedBox(width: 380, child: _SourcePanel(controller: c, api: c.api, onClose: () => c.select(null))),
    ]);
  }

  Widget _thread(BuildContext context) {
    // reversed so the newest exchange sits at the bottom and the list stays pinned there
    final items = <Widget>[];
    for (var i = c.turns.length - 1; i >= 0; i--) {
      final t = c.turns[i];
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _QuestionBubble(text: t.question),
          const SizedBox(height: 8),
          if (t.pending)
            _PendingBubble(status: c.status)
          else if (t.error != null)
            _ErrorBubble(error: t.error!, onRetry: () => c.retry(t), onOpenSettings: widget.onOpenSettings)
          else
            _AnswerBubble(result: t.result!, selected: c.selected?.turn == i ? c.selected!.n : null, onCite: (n) => _cite(i, n)),
        ]),
      ));
    }
    return ListView(reverse: true, padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), children: items);
  }

  Widget _composerBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final continuing = c.turns.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: TextField(
            controller: _composer,
            focusNode: widget.focusNode,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: _send,
            decoration: InputDecoration(
              hintText: continuing ? '이어서 질문… ("그건 왜?"처럼 짧게 이어도 됩니다)' : '기록을 근거로 답합니다 (예: GA4 매핑은 왜 미뤘지?)',
              prefixIcon: const Icon(Icons.question_answer_outlined),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: c.busy ? null : _send,
          icon: c.busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
          label: Text(c.busy ? '답하는 중' : '보내기'),
        ),
      ]),
    );
  }
}

/// The header controls for the 질문 mode: new conversation, previous conversations, delete.
class AskHeader extends StatelessWidget {
  const AskHeader({super.key, required this.controller});
  final AskController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => Row(children: [
        Expanded(
          child: Text(
            c.turns.isEmpty ? '새 대화' : c.turns.first.question,
            style: t.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        FutureBuilder<AskStatus>(
          future: c.status,
          builder: (context, snap) {
            final convs = snap.data?.conversations ?? const <ConversationSummary>[];
            return PopupMenuButton<String>(
              tooltip: '이전 대화',
              enabled: convs.isNotEmpty,
              icon: const Icon(Icons.history),
              onSelected: c.load,
              itemBuilder: (_) => [
                for (final cv in convs.take(20))
                  PopupMenuItem(
                    value: cv.id,
                    child: ListTile(
                      dense: true,
                      title: Text(cv.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${cv.turns}턴 · ${cv.updatedAt?.toLocal().toString().split('.').first ?? ''}'),
                      trailing: cv.id == c.conversationId ? Icon(Icons.check, color: scheme.primary, size: 18) : null,
                    ),
                  ),
              ],
            );
          },
        ),
        if (c.conversationId != null)
          IconButton(tooltip: '이 대화 지우기', icon: const Icon(Icons.delete_outline), onPressed: c.busy ? null : c.deleteCurrent),
        TextButton.icon(onPressed: c.turns.isEmpty || c.busy ? null : c.newConversation, icon: const Icon(Icons.add_comment_outlined, size: 18), label: const Text('새 대화')),
      ]),
    );
  }
}

/// Before the first question: what will answer, or how to get an agent.
class _Intro extends StatelessWidget {
  const _Intro({required this.status, this.onOpenSettings});
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
              '질문으로 기록을 검색하고, 상위 문단을 이 맥에 있는 에이전트(Claude Code·Codex·Gemini CLI)나 OpenRouter에 넣어 출처 [번호]가 달린 답을 받습니다. '
              '이어서 물으면 앞의 대화를 기억합니다. 에이전트는 파일을 읽기만 합니다.', icon: Icons.question_answer_outlined),
          if (agent != null) Text('답은 ${agent.title}가 씁니다 · ${agent.detail}', style: t.bodySmall?.copyWith(color: scheme.outline)),
          for (final a in st?.agents.where((a) => a.needsLogin) ?? const <AgentInfo>[])
            Text('${a.title}: ${a.loginNote}', style: t.bodySmall?.copyWith(color: scheme.error), textAlign: TextAlign.center),
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

class _QuestionBubble extends StatelessWidget {
  const _QuestionBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14), bottomLeft: Radius.circular(14), bottomRight: Radius.circular(4)),
          ),
          child: SelectableText(text, style: t.bodyLarge?.copyWith(color: scheme.onPrimary), minLines: 1),
        ),
      ),
    );
  }
}

class _PendingBubble extends StatelessWidget {
  const _PendingBubble({required this.status});
  final Future<AskStatus> status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _Bubble(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        FutureBuilder<AskStatus>(
          future: status,
          builder: (context, snap) => Text('${snap.data?.chosenAgent?.title ?? '에이전트'}가 기록을 읽고 답을 쓰는 중… (수십 초)', style: t.bodyMedium),
        ),
      ]),
    );
  }
}

class _ErrorBubble extends StatelessWidget {
  const _ErrorBubble({required this.error, required this.onRetry, this.onOpenSettings});
  final Object error;
  final VoidCallback onRetry;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final e = error;
    final noAgent = e is ApiException && e.status == 409 && e.message.contains('에이전트가 없');
    final message = e is ApiException ? e.message : '$e';
    return _Bubble(
      color: scheme.errorContainer.withValues(alpha: 0.35),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(message, style: t.bodyMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          if (noAgent && onOpenSettings != null)
            FilledButton.tonalIcon(onPressed: onOpenSettings, icon: const Icon(Icons.settings_outlined, size: 18), label: const Text('설정 열기'))
          else
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 18), label: const Text('다시 시도')),
        ]),
      ]),
    );
  }
}

/// The answer with tappable [n] marks, then a row of every source as a chip (hover = passage, tap = panel).
class _AnswerBubble extends StatelessWidget {
  const _AnswerBubble({required this.result, required this.selected, required this.onCite});
  final AskResult result;
  final int? selected;
  final ValueChanged<int> onCite;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final agent = agentTitles[result.agent] ?? result.agent;
    return _Bubble(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SelectableText.rich(citationSpan(context, result.answer, sources: result.sources, base: t.bodyLarge, selected: selected, onCite: onCite), minLines: 1, maxLines: 80),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('근거', style: t.labelSmall?.copyWith(color: scheme.outline)),
          for (final s in result.sources) _SourceChip(source: s, selected: selected == s.n, onTap: () => onCite(s.n)),
        ]),
        const SizedBox(height: 6),
        Text('$agent · ${(result.ms / 1000).toStringAsFixed(1)}초 · 발췌 ${result.sources.length}개만 근거로 썼습니다', style: t.labelSmall?.copyWith(color: scheme.outline)),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.child, this.color});
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: color ?? scheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(14), bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A rich tooltip for a source: its label, then the first lines of the passage.
InlineSpan sourceTooltip(BuildContext context, AskSource s) {
  final scheme = Theme.of(context).colorScheme;
  final preview = s.passage.length > 280 ? '${s.passage.substring(0, 280).trimRight()}…' : s.passage;
  return TextSpan(children: [
    TextSpan(text: '[${s.n}] ${s.label}\n', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onInverseSurface)),
    TextSpan(text: preview, style: TextStyle(color: scheme.onInverseSurface.withValues(alpha: 0.9))),
    TextSpan(text: '\n\n누르면 전체 발췌와 원문', style: TextStyle(fontSize: 11, color: scheme.onInverseSurface.withValues(alpha: 0.7))),
  ]);
}

/// A small [n] mark: hover shows the passage, tap opens it.
class _CitationMark extends StatelessWidget {
  const _CitationMark({required this.source, required this.selected, required this.onTap, this.fontSize = 11});
  final AskSource source;
  final bool selected;
  final VoidCallback onTap;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      richMessage: sourceTooltip(context, source),
      waitDuration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints(maxWidth: 420),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: selected ? scheme.primary : scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
          child: Text('${source.n}', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: selected ? scheme.onPrimary : scheme.primary)),
        ),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source, required this.selected, required this.onTap});
  final AskSource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final label = source.label.length > 38 ? '${source.label.substring(0, 38)}…' : source.label;
    return Tooltip(
      richMessage: sourceTooltip(context, source),
      waitDuration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints(maxWidth: 420),
      child: Material(
        color: selected ? scheme.primary.withValues(alpha: 0.14) : scheme.surface,
        shape: StadiumBorder(side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${source.n}', style: t.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary)),
              const SizedBox(width: 6),
              Text(label, style: t.labelSmall),
            ]),
          ),
        ),
      ),
    );
  }
}

/// [text] with every "[n]" that points at one of [sources] rendered as a mark with a tooltip.
TextSpan citationSpan(BuildContext context, String text, {required List<AskSource> sources, TextStyle? base, int? selected, required ValueChanged<int> onCite}) {
  final children = <InlineSpan>[];
  var last = 0;
  for (final m in RegExp(r'\[(\d+)\]').allMatches(text)) {
    final n = int.parse(m.group(1)!);
    final src = sources.where((s) => s.n == n).firstOrNull;
    if (src == null) continue;
    if (m.start > last) children.add(TextSpan(text: text.substring(last, m.start)));
    children.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: _CitationMark(source: src, selected: selected == n, onTap: () => onCite(n), fontSize: (base?.fontSize ?? 14) - 3),
      ),
    ));
    last = m.end;
  }
  if (last < text.length) children.add(TextSpan(text: text.substring(last)));
  return TextSpan(style: base, children: children);
}

/// The selected source in full: label, passage, path, "원문 열기", and arrows through that turn's sources.
class _SourcePanel extends StatelessWidget {
  const _SourcePanel({required this.controller, required this.api, required this.onClose, this.inSheet = false});
  final AskController controller;
  final WorklogApi api;
  final VoidCallback onClose;
  final bool inSheet;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final sel = controller.selected;
    final s = controller.selectedSource;
    if (sel == null || s == null) return const SizedBox.shrink();
    final sources = controller.turns[sel.turn].result?.sources ?? const <AskSource>[];
    final idx = sources.indexOf(s);
    void go(int d) {
      final next = idx + d;
      if (next >= 0 && next < sources.length) controller.select(SelectedSource(sel.turn, sources[next].n));
    }
    return Container(
      decoration: inSheet ? null : BoxDecoration(color: scheme.surfaceContainerLow, border: Border(left: BorderSide(color: scheme.outlineVariant))),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 12, backgroundColor: scheme.primary, child: Text('${s.n}', style: t.labelSmall?.copyWith(color: scheme.onPrimary))),
          const SizedBox(width: 8),
          Expanded(child: Text('근거 ${idx + 1} / ${sources.length}', style: t.titleSmall)),
          IconButton(tooltip: '이전 근거', icon: const Icon(Icons.chevron_left), onPressed: idx > 0 ? () => go(-1) : null, visualDensity: VisualDensity.compact),
          IconButton(tooltip: '다음 근거', icon: const Icon(Icons.chevron_right), onPressed: idx < sources.length - 1 ? () => go(1) : null, visualDensity: VisualDensity.compact),
          IconButton(tooltip: '닫기', icon: const Icon(Icons.close), onPressed: onClose, visualDensity: VisualDensity.compact),
        ]),
        const SizedBox(height: 6),
        Text(s.label, style: t.titleSmall?.copyWith(color: scheme.primary)),
        if (s.path.isNotEmpty) Text(s.path, style: ZaevisTheme.mono.copyWith(fontSize: 11.5, color: scheme.outline)),
        const Divider(height: 18),
        Expanded(
          child: SingleChildScrollView(
            child: SelectableText(s.passage.isEmpty ? '(발췌 없음)' : s.passage, style: t.bodyMedium, minLines: 1),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          FilledButton.tonalIcon(
            onPressed: s.path.isEmpty ? null : () => FileScreen.open(context, api, s.path),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('원문 열기'),
          ),
        ]),
      ]),
    );
  }
}
