import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../chat_intent.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/agent_rail.dart';
import '../widgets/common.dart';
import '../widgets/hit_card.dart';
import '../widgets/save_file.dart';
import '../recording_trail.dart';
import 'file_screen.dart';
import 'search_screen.dart';

const agentTitles = {'claude': 'Claude Code', 'codex': 'Codex CLI', 'gemini': 'Gemini CLI', 'openrouter': 'OpenRouter'};

/// "Codex CLI" or "Claude Code 할당량 → Codex CLI가 작성" when an earlier stop was skipped.
String _who(AskResult result, String fallback) {
  final skips = result.rail.where((s) => s.state == 'quota').map((s) => s.title).toList();
  final wrote = result.rail.where((s) => s.state == 'wrote').map((s) => s.title).firstOrNull ?? fallback;
  if (skips.isEmpty) return wrote;
  return '${skips.join(', ')} 할당량 → $wrote가 작성';
}

/// One exchange in the thread: the line the user sent, then what it got — hits (검색), an answer (질문),
/// or files to save (내려받기). A searched line can later get an answer too ("답 받기").
class AskTurn {
  AskTurn(this.question, {this.intent = ChatIntent.ask, this.result, this.error, this.rail = const []});
  final String question;
  ChatIntent intent;

  SearchResult? search;
  Object? searchError;
  bool searching = false;

  FileMatches? files;
  Object? filesError;
  bool finding = false;

  AskResult? result;
  Object? error;
  List<RailStop> rail;
  bool answering = false;

  /// The user pressed 멈추기 while the answer was being written.
  bool cancelled = false;

  /// "멈추기" was pressed and the server has not let go yet.
  bool stopping = false;

  /// Waiting on the server for anything.
  bool get pending => searching || finding || answering;

  /// An answer was asked for (in flight, written, failed or stopped).
  bool get asked => answering || result != null || error != null || cancelled;
}

/// A source the user is looking at: which turn, which [n].
class SelectedSource {
  const SelectedSource(this.turn, this.n);
  final int turn;
  final int n;
}

/// The chat state, owned by the screen. Answers belong to a server-side conversation; searches and file
/// requests live only here.
class AskController extends ChangeNotifier {
  AskController(this.api);
  final WorklogApi api;

  final List<AskTurn> turns = [];
  String? conversationId;
  late Future<AskStatus> status = api.askStatus();
  SelectedSource? selected;

  /// The rail of the question in flight, refreshed while the server tries the next service.
  List<RailStop> liveRail = const [];
  Timer? _poll;

  bool get busy => turns.any((t) => t.pending);
  bool get answering => turns.any((t) => t.answering);

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void refreshStatus() {
    status = api.askStatus();
    notifyListeners();
  }

  void _watchRail() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final s = await api.askStatus();
        final next = s.runningRail.isNotEmpty ? s.runningRail : s.rail;
        if (next.isEmpty) return;
        liveRail = next;
        status = Future.value(s);
        notifyListeners();
      } catch (_) {}
    });
  }

  /// The agent's open question back, when the last thing in the chat is one.
  Clarify? get openClarify => turns.isEmpty ? null : turns.last.result?.clarify;

  /// Sends a line: searches it, answers it when it reads as a question, or finds the files it asks for.
  /// Right after the agent asked back, a line is the reply to it (an answer), unless it asks for a file.
  Future<void> send(String line) async {
    final q = line.trim();
    if (q.isEmpty || busy) return;
    var intent = chatIntent(q);
    if (openClarify != null && intent != ChatIntent.download) intent = ChatIntent.ask;
    final turn = AskTurn(q, intent: intent);
    turns.add(turn);
    selected = null;
    notifyListeners();
    switch (turn.intent) {
      case ChatIntent.download:
        await _findFiles(turn);
      case ChatIntent.search:
        await _search(turn);
      case ChatIntent.ask:
        await _answer(turn);
    }
  }

  /// "답 받기" on a searched line: asks the same words in the current conversation.
  Future<void> answer(AskTurn turn) async {
    if (busy || turn.asked) return;
    turn.intent = ChatIntent.ask;
    await _answer(turn);
  }

  Future<void> _search(AskTurn turn) async {
    turn.searching = true;
    notifyListeners();
    try {
      // more than the chat shows: "모두 보기" filters the rest
      turn.search = await api.search(turn.question, topK: 40);
    } catch (e) {
      turn.searchError = e;
    } finally {
      turn.searching = false;
    }
    notifyListeners();
  }

  Future<void> _findFiles(AskTurn turn) async {
    final earlier = _pointedFiles(turn);
    if (earlier != null) {
      turn.files = FileMatches(files: earlier, by: 'chat');
      notifyListeners();
      return;
    }
    turn.finding = true;
    notifyListeners();
    try {
      turn.files = await api.findFiles(turn.question);
    } catch (e) {
      turn.filesError = e;
    } finally {
      turn.finding = false;
    }
    notifyListeners();
  }

  /// Files the line points at in what the chat already showed: "[2] 내려받기" or "이거 txt로 받을래".
  List<FoundFile>? _pointedFiles(AskTurn turn) {
    final before = turns.takeWhile((t) => t != turn).toList().reversed;
    FoundFile ref(String path, String kind) => FoundFile(path: path, name: path.split('/').last, bytes: 0, kind: kind);
    final n = citedNumber(turn.question);
    if (n != null) {
      for (final t in before) {
        final src = t.result?.sources.where((s) => s.n == n).firstOrNull;
        if (src != null && src.path.isNotEmpty) return [ref(src.path, src.label)];
        final hit = t.search?.hits.where((h) => h.number == n).firstOrNull;
        if (hit != null && hit.path.isNotEmpty) return [ref(hit.path, hit.context?.sourceLabel ?? hit.title)];
      }
      return null;
    }
    if (!pointsBack(turn.question)) return null;
    for (final t in before) {
      final files = t.files?.files ?? const <FoundFile>[];
      if (files.isNotEmpty) return files;
      final paths = <String, String>{};
      for (final s in t.result?.sources ?? const <AskSource>[]) {
        if (s.path.isNotEmpty) paths.putIfAbsent(s.path, () => s.label);
      }
      for (final h in (t.search?.hits ?? const <SearchHit>[]).where((h) => !h.weak).take(3)) {
        if (h.path.isNotEmpty) paths.putIfAbsent(h.path, () => h.context?.sourceLabel ?? h.title);
      }
      if (paths.isNotEmpty) return [for (final e in paths.entries) ref(e.key, e.value)];
    }
    return null;
  }

  /// 멈추기: asks the server to stop the agent; the waiting answer comes back as cancelled.
  Future<void> cancel() async {
    final turn = turns.where((t) => t.answering).firstOrNull;
    if (turn == null || turn.stopping) return;
    turn.stopping = true;
    notifyListeners();
    try {
      await api.cancelAsk();
    } catch (_) {
      turn.stopping = false;
      notifyListeners();
    }
  }

  Future<void> _answer(AskTurn turn) async {
    turn
      ..answering = true
      ..cancelled = false
      ..stopping = false
      ..error = null;
    liveRail = const [];
    notifyListeners();
    _watchRail();
    try {
      final r = await api.ask(turn.question, conversationId: conversationId);
      turn.result = r;
      turn.rail = r.rail;
      conversationId = r.conversationId.isEmpty ? conversationId : r.conversationId;
      status = api.askStatus(); // the conversation list changed
    } catch (e) {
      if (e is ApiException && e.code == 'cancelled') {
        turn.cancelled = true;
      } else {
        turn.error = e;
        turn.rail = e is ApiException && e.rail.isNotEmpty ? e.rail : liveRail;
      }
    } finally {
      turn.answering = false;
      turn.stopping = false;
      _poll?.cancel();
      _poll = null;
    }
    notifyListeners();
  }

  /// Re-asks a failed or stopped answer in place.
  Future<void> retry(AskTurn turn) async {
    if ((turn.error == null && !turn.cancelled) || busy) return;
    await _answer(turn);
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
    final sources = turns[s.turn].result?.sources ?? const <AskSource>[];
    return sources.where((x) => x.n == s.n).firstOrNull;
  }
}

/// The chat: the user's lines and what each got, a composer at the bottom, and the source a citation
/// points at in a panel on the right (wide) or a sheet from the bottom (narrow).
class AskView extends StatefulWidget {
  const AskView({super.key, required this.controller, this.focusNode, this.onOpenSettings, this.onOpenIndex, this.index, this.inbox, this.onSent});
  final AskController controller;
  final FocusNode? focusNode;
  final VoidCallback? onOpenSettings;

  /// Opens the index sheet from a search that failed for want of an index.
  final VoidCallback? onOpenIndex;

  /// For the note under an empty search ("색인 중", "방금 넣은 전사본은 아직…").
  final IndexStatus? index;
  final Inbox? inbox;

  /// After each line is handled (the screen refreshes its recording trail).
  final VoidCallback? onSent;

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

  Future<void> _send([String? _]) async {
    final q = _composer.text.trim();
    if (q.isEmpty || c.busy) return;
    _composer.clear();
    widget.focusNode?.requestFocus();
    await c.send(q);
    widget.onSent?.call();
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
          if (t.intent == ChatIntent.download) _FilesBubble(turn: t, api: c.api),
          if (t.searching || t.search != null || t.searchError != null)
            _SearchBubble(
              turn: t,
              api: c.api,
              index: widget.index,
              inbox: widget.inbox,
              onOpenIndex: widget.onOpenIndex,
              onAnswer: t.asked || c.busy ? null : () => c.answer(t),
            ),
          if (t.asked && (t.search != null || t.searchError != null)) const SizedBox(height: 8),
          if (t.answering)
            _PendingBubble(status: c.status, rail: c.liveRail, stopping: t.stopping, onStop: c.cancel)
          else if (t.cancelled)
            _StoppedBubble(onRetry: c.busy ? null : () => c.retry(t))
          else if (t.error != null)
            _ErrorBubble(error: t.error!, rail: t.rail, onRetry: () => c.retry(t), onOpenSettings: widget.onOpenSettings)
          else if (t.result != null)
            _AnswerBubble(
              result: t.result!,
              selected: c.selected?.turn == i ? c.selected!.n : null,
              onCite: (n) => _cite(i, n),
              // only the newest question back takes a reply
              onChoose: i == c.turns.length - 1 && !c.busy ? (choice) => c.send(choice) : null,
            ),
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
              hintText: c.openClarify != null
                  ? '위 질문에 답해 주세요 (고르거나 직접 적기)'
                  : continuing
                      ? '이어서… ("그건 왜?", "[2] 내려받기"처럼 짧게 이어도 됩니다)'
                      : '찾을 말, 질문, 또는 "11월 2일 전사본 내려받기"',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: c.busy ? null : _send,
          icon: c.busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
          label: Text(c.answering ? '답하는 중' : c.busy ? '찾는 중' : '보내기'),
        ),
      ]),
    );
  }
}

/// The chat's header: its title, new conversation, previous conversations, delete.
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
          const EmptyPane('기록에 말을 거세요\n'
              '단어를 넣으면 로그 · 프로젝트 · 리포트 · 전사본 · 수집 원본에서 바로 찾습니다. '
              '"색인은 왜 미뤘지?"처럼 물으면 찾은 문단만 근거로 에이전트가 출처 [번호]를 달아 답합니다. '
              '"11월 2일 전사본 내려받기"처럼 말하면 그 파일을 내려받을 수 있습니다. 에이전트는 파일을 읽기만 합니다.', icon: Icons.forum_outlined),
          if (agent != null) Text('답은 ${agent.title}가 씁니다 · ${agent.detail}', style: t.bodySmall?.copyWith(color: scheme.outline)),
          if (st != null && st.rail.isNotEmpty) AgentRail(stops: st.rail),
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
  const _PendingBubble({required this.status, required this.rail, this.stopping = false, this.onStop});
  final Future<AskStatus> status;
  final List<RailStop> rail;
  final bool stopping;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _Bubble(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (rail.isNotEmpty) AgentRail(stops: rail),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          FutureBuilder<AskStatus>(
            future: status,
            builder: (context, snap) => Text(
                stopping ? '멈추는 중…' : '${snap.data?.chosenAgent?.title ?? '에이전트'}가 기록을 읽고 답을 쓰는 중… (수십 초)',
                style: t.bodyMedium),
          ),
          if (onStop != null) ...[
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: stopping ? null : onStop,
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: const Text('멈추기'),
            ),
          ],
        ]),
      ]),
    );
  }
}

class _ErrorBubble extends StatelessWidget {
  const _ErrorBubble({required this.error, required this.onRetry, this.rail = const [], this.onOpenSettings});
  final Object error;
  final List<RailStop> rail;
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
        if (rail.isNotEmpty) AgentRail(stops: rail),
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
  const _AnswerBubble({required this.result, required this.selected, required this.onCite, this.onChoose});
  final AskResult result;
  final int? selected;
  final ValueChanged<int> onCite;

  /// Sends a choice as the reply to a question back; null once the chat has moved on.
  final ValueChanged<String>? onChoose;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final agent = agentTitles[result.agent] ?? result.agent;
    final clarify = result.clarify;
    if (clarify != null) {
      return _Bubble(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.help_outline, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Text('되묻기', style: t.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          SelectableText(clarify.question, style: t.bodyLarge, minLines: 1),
          if (clarify.options.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final o in clarify.options) ActionChip(label: Text(o), onPressed: onChoose == null ? null : () => onChoose!(o)),
            ]),
          ],
          const SizedBox(height: 8),
          Text(onChoose == null ? '${_who(result, agent)} · 기록이 여러 갈래라 되물었습니다' : '고르거나 아래에 직접 적어 주세요 · ${_who(result, agent)}',
              style: t.labelSmall?.copyWith(color: scheme.outline)),
        ]),
      );
    }
    return _Bubble(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (result.rail.isNotEmpty) AgentRail(stops: result.rail),
        SelectableText.rich(citationSpan(context, result.answer, sources: result.sources, base: t.bodyLarge, selected: selected, onCite: onCite), minLines: 1, maxLines: 80),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('근거', style: t.labelSmall?.copyWith(color: scheme.outline)),
          for (final s in result.sources) _SourceChip(source: s, selected: selected == s.n, onTap: () => onCite(s.n)),
        ]),
        const SizedBox(height: 6),
        Text('${_who(result, agent)} · ${(result.ms / 1000).toStringAsFixed(1)}초 · 발췌 ${result.sources.length}개만 근거로 썼습니다', style: t.labelSmall?.copyWith(color: scheme.outline)),
      ]),
    );
  }
}

/// The hits for a line: the first few as cards, then "모두 보기" (filters) and, when no answer was asked, "답 받기".
class _SearchBubble extends StatelessWidget {
  const _SearchBubble({required this.turn, required this.api, this.index, this.inbox, this.onOpenIndex, this.onAnswer});
  final AskTurn turn;
  final WorklogApi api;
  final IndexStatus? index;
  final Inbox? inbox;
  final VoidCallback? onOpenIndex;
  final VoidCallback? onAnswer;

  static const shown = 4;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (turn.searching) {
      return _Bubble(child: Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Text('찾는 중…', style: t.bodyMedium),
      ]));
    }
    final err = turn.searchError;
    if (err != null) return _Bubble(color: scheme.errorContainer.withValues(alpha: 0.35), child: Text(err is ApiException ? err.message : '$err'));
    final r = turn.search!;
    if (!r.ok) return _Bubble(child: SearchErrorNote(result: r, onOpenIndex: onOpenIndex));
    final hits = r.hits;
    return _Bubble(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(hits.isEmpty ? emptySearchNote(query: turn.question, total: 0, shown: 0, filtered: false, index: index, inbox: inbox) : '찾은 기록 ${hits.length}건',
            style: hits.isEmpty ? t.bodyMedium : t.labelMedium?.copyWith(color: scheme.outline)),
        for (final h in hits.take(shown)) ...[
          const SizedBox(height: 8),
          HitCard(
            hit: h,
            maxLines: 4,
            onOpen: () => FileScreen.open(context, api, h.path),
            onDownload: () => saveWorklogFile(context, api, h.path),
          ),
        ],
        if (hits.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (onAnswer != null && hits.isNotEmpty)
              FilledButton.tonalIcon(onPressed: onAnswer, icon: const Icon(Icons.question_answer_outlined, size: 18), label: const Text('답 받기')),
            if (hits.length > 1)
              OutlinedButton.icon(
                onPressed: () => SearchResultsScreen.open(context, api, turn.question, r, index: index, inbox: inbox),
                icon: const Icon(Icons.filter_list, size: 18),
                label: Text('모두 보기 (${hits.length}건)'),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// The files a line asked for, each with 열기 and 내려받기; or why none were found.
class _FilesBubble extends StatelessWidget {
  const _FilesBubble({required this.turn, required this.api});
  final AskTurn turn;
  final WorklogApi api;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (turn.finding) {
      return _Bubble(child: Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Text('파일을 찾는 중…', style: t.bodyMedium),
      ]));
    }
    final err = turn.filesError;
    if (err != null) return _Bubble(color: scheme.errorContainer.withValues(alpha: 0.35), child: Text(err is ApiException ? err.message : '$err'));
    final m = turn.files;
    if (m == null || m.files.isEmpty) {
      return const _Bubble(
        child: Text('그 파일을 찾지 못했습니다. 날짜와 종류("11월 2일 전사본", "어제 git 커밋")나 파일 이름으로 말해 주세요. '
            '검색이나 답에 나온 것이면 "[2] 내려받기"처럼 번호로 가리켜도 됩니다.'),
      );
    }
    final note = switch (m.by) {
      'search' => '이름이나 날짜로 딱 맞는 파일이 없어, 검색에서 찾은 파일입니다.',
      'chat' => '위에 나온 파일입니다.',
      _ => m.files.length == 1 ? '이 파일을 찾았습니다.' : '파일 ${m.files.length}개를 찾았습니다.',
    };
    return _Bubble(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(note, style: t.labelMedium?.copyWith(color: scheme.outline)),
        for (final f in m.files) ...[
          const SizedBox(height: 8),
          _FileRow(file: f, api: api),
        ],
      ]),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.api});
  final FoundFile file;
  final WorklogApi api;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final meta = [if (file.kind.isNotEmpty) file.kind, if (file.bytes > 0) file.size].join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: scheme.outlineVariant)),
      child: Row(children: [
        Icon(file.name.endsWith('.txt') ? Icons.description_outlined : Icons.article_outlined, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(file.name, style: t.titleSmall),
            Text(meta.isEmpty ? file.path : '$meta · ${file.path}', style: ZaevisTheme.mono.copyWith(fontSize: 11.5, color: scheme.outline), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: 8),
        TextButton(onPressed: () => FileScreen.open(context, api, file.path), child: const Text('열기')),
        const SizedBox(width: 4),
        FilledButton.icon(onPressed: () => saveWorklogFile(context, api, file.path), icon: const Icon(Icons.download, size: 18), label: const Text('내려받기')),
      ]),
    );
  }
}

/// A question the user stopped: no answer, and a way to ask it again.
class _StoppedBubble extends StatelessWidget {
  const _StoppedBubble({this.onRetry});
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return _Bubble(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.stop_circle_outlined, size: 18, color: scheme.outline),
        const SizedBox(width: 8),
        Text('멈췄습니다', style: t.bodyMedium?.copyWith(color: scheme.outline)),
        const SizedBox(width: 12),
        TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 18), label: const Text('다시 묻기')),
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
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: s.path.isEmpty ? null : () => saveWorklogFile(context, api, s.path),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('내려받기'),
          ),
        ]),
      ]),
    );
  }
}
