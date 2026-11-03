import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import '../recording/recorder.dart';
import '../theme.dart';
import '../widgets/agent_rail.dart';
import '../widgets/common.dart';
import '../widgets/hit_card.dart';
import '../widgets/knowledge_panel.dart';
import '../widgets/input_dialogs.dart' show toast;
import '../widgets/save_file.dart';
import '../recording_trail.dart';
import 'file_screen.dart';
import 'review_screen.dart';
import 'search_screen.dart';

/// A digested record (what the weekly digest and reports write) rather than collected raw material.
bool isKnowledgePath(String path) => RegExp(r'^(log|projects|summaries|reports)/').hasMatch(path);

const agentTitles = {'claude': 'Claude Code', 'codex': 'Codex CLI', 'gemini': 'Gemini CLI', 'openrouter': 'OpenRouter'};

/// "Codex CLI" or "Claude Code 할당량 → Codex CLI가 작성" when an earlier stop was skipped.
String _who(AppLocalizations l, AskResult result, String fallback) {
  final skips = result.rail.where((s) => s.state == 'quota').map((s) => s.title).toList();
  final wrote = result.rail.where((s) => s.state == 'wrote').map((s) => s.title).firstOrNull ?? fallback;
  if (skips.isEmpty) return wrote;
  return l.askQuotaHandoff(skips.join(', '), wrote);
}

/// One exchange in the thread: the line the user sent, the search hits it found at once, and what the server made of
/// it — an answer, the files it asked for, or (Jev routed it as a lookup) nothing beyond the hits.
class AskTurn {
  AskTurn(this.question, {this.result, this.error, this.rail = const []});
  final String question;

  SearchResult? search;
  Object? searchError;
  bool searching = false;

  AskResult? result;
  Object? error;
  List<RailStop> rail;
  bool answering = false;

  /// The user pressed 멈추기 while the answer was being written.
  bool cancelled = false;

  /// "멈추기" was pressed and the server has not let go yet.
  bool stopping = false;

  /// Waiting on the server for anything.
  bool get pending => searching || answering;

  /// Jev took the line for a lookup: the hits are the reply, and "답 받기" asks for an answer anyway.
  bool get lookup => result?.route == 'search';

  /// Files handed over to save.
  List<FoundFile> get files => result?.files ?? const [];

  /// Something beyond the hits came back (or is coming): the hits then shrink to one line.
  bool get answered => answering || cancelled || error != null || (result != null && !lookup);
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

  /// Sends a line: the hits show at once, and the server decides what else it wants — an answer, files to save, or
  /// nothing more (with an OpenRouter key Jev routes; otherwise the answering agent does). Right after the agent asked
  /// back, the line is the reply to that question, so it goes straight to the agent.
  Future<void> send(String line) async {
    final q = line.trim();
    if (q.isEmpty || busy) return;
    final replying = openClarify != null;
    final shown = _shown(turns.lastOrNull);
    final turn = AskTurn(q);
    turns.add(turn);
    selected = null;
    notifyListeners();
    await Future.wait([_search(turn), _answer(turn, shown: shown, force: replying)]);
  }

  /// "답 받기" on a lookup: asks the same words for an answer, past the router.
  Future<void> answer(AskTurn turn) async {
    if (busy || !turn.lookup) return;
    turn.result = null;
    await _answer(turn, force: true);
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

  /// What the last turn put on screen with numbers, so "[2] 받을래" can be resolved by the server.
  static List<({int n, String path})> _shown(AskTurn? t) {
    if (t == null) return const [];
    final r = t.result;
    if (r != null && r.sources.isNotEmpty && !t.lookup) return [for (final s in r.sources) if (s.path.isNotEmpty) (n: s.n, path: s.path)];
    if (t.files.isNotEmpty) return [for (var i = 0; i < t.files.length; i++) (n: i + 1, path: t.files[i].path)];
    return [for (final h in (t.search?.hits ?? const <SearchHit>[]).take(_SearchBubble.shown)) if (h.path.isNotEmpty) (n: h.number, path: h.path)];
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

  Future<void> _answer(AskTurn turn, {List<({int n, String path})> shown = const [], bool force = false}) async {
    turn
      ..answering = true
      ..cancelled = false
      ..stopping = false
      ..error = null;
    liveRail = const [];
    notifyListeners();
    _watchRail();
    try {
      final r = await api.ask(turn.question, conversationId: conversationId, shown: shown, force: force);
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
    await _answer(turn, force: true);
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
  const AskView({super.key, required this.controller, this.focusNode, this.onOpenSettings, this.onOpenIndex, this.index, this.inbox, this.onSent, this.recorder});
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

  /// The microphone for saying a line instead of typing it; tests pass a fake, the app uses the plugin.
  final Recorder? recorder;

  /// A spoken line longer than this is sent as it is.
  static const voiceLimit = Duration(minutes: 2);

  /// Below this width the source opens as a bottom sheet instead of a side panel.
  static const panelBreakpoint = 980.0;

  @override
  State<AskView> createState() => _AskViewState();
}

/// The composer's microphone: idle, listening, or waiting for the server's text.
enum _Voice { idle, listening, converting }

class _AskViewState extends State<AskView> {
  final _composer = TextEditingController();

  _Voice _voice = _Voice.idle;
  final List<Uint8List> _chunks = [];
  StreamSubscription<Uint8List>? _sub;
  Timer? _tick;
  DateTime? _since;
  Duration _elapsed = Duration.zero;
  Recorder? _ownRecorder;

  Recorder get _recorder => widget.recorder ?? (_ownRecorder ??= PluginRecorder());

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
    _tick?.cancel();
    unawaited(_sub?.cancel() ?? Future.value());
    if (_voice == _Voice.listening) unawaited(_recorder.stop());
    unawaited(_ownRecorder?.dispose() ?? Future.value());
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

  /// The microphone button: start listening, or stop and send what was said.
  Future<void> _toggleVoice() async {
    switch (_voice) {
      case _Voice.idle:
        await _startVoice();
      case _Voice.listening:
        await _finishVoice();
      case _Voice.converting:
        return;
    }
  }

  Future<void> _startVoice() async {
    final l = context.l10n;
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) toast(context, l.recordMicDenied, error: true);
        return;
      }
      final stream = await _recorder.startStream();
      _chunks.clear();
      _since = DateTime.now();
      _elapsed = Duration.zero;
      _sub = stream.listen(_chunks.add);
      _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        setState(() => _elapsed = DateTime.now().difference(_since!));
        if (_elapsed >= AskView.voiceLimit) _finishVoice();
      });
      if (mounted) setState(() => _voice = _Voice.listening);
    } catch (e) {
      if (mounted) toast(context, l.recordStartFailed('$e'), error: true);
    }
  }

  /// Stops listening, has the server turn the speech into text (whisper, nothing kept), and sends it as a typed line.
  Future<void> _finishVoice() async {
    if (_voice != _Voice.listening) return;
    _tick?.cancel();
    setState(() => _voice = _Voice.converting);
    await _recorder.stop(); // the plugin ends the stream here
    unawaited(_sub?.cancel() ?? Future.value());
    _sub = null;
    final wav = wavFromPcm16(_chunks);
    _chunks.clear();
    String text;
    try {
      text = await c.api.voiceToText(wav);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _voice = _Voice.idle);
        toast(context, context.l10n.voiceFailed(e.message), error: true);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _voice = _Voice.idle);
    if (text.isEmpty) {
      toast(context, context.l10n.voiceNothing);
      return;
    }
    _composer.text = text;
    await _send();
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
      Expanded(child: c.turns.isEmpty ? _Intro(status: c.status, api: c.api, onOpenSettings: widget.onOpenSettings) : _thread(context)),
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
          if (t.searching || t.search != null || t.searchError != null)
            _SearchBubble(
              turn: t,
              api: c.api,
              index: widget.index,
              inbox: widget.inbox,
              onOpenIndex: widget.onOpenIndex,
              compact: t.answered,
              onAnswer: t.lookup && !c.busy ? () => c.answer(t) : null,
            ),
          if (t.answered) const SizedBox(height: 8),
          if (t.files.isNotEmpty) _FilesBubble(turn: t, api: c.api),
          if (t.answering)
            _PendingBubble(status: c.status, rail: c.liveRail, stopping: t.stopping, onStop: c.cancel)
          else if (t.cancelled)
            _StoppedBubble(onRetry: c.busy ? null : () => c.retry(t))
          else if (t.error != null)
            _ErrorBubble(error: t.error!, rail: t.rail, onRetry: () => c.retry(t), onOpenSettings: widget.onOpenSettings)
          else if (t.result != null && !t.lookup && t.files.isEmpty)
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
            readOnly: _voice != _Voice.idle,
            decoration: InputDecoration(
              hintText: _voice == _Voice.listening
                  ? context.l10n.voiceListening('${_elapsed.inMinutes}:${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')}')
                  : _voice == _Voice.converting
                      ? context.l10n.voiceConverting
                      : c.openClarify != null
                  ? context.l10n.askHintClarify
                  : continuing
                      ? context.l10n.askHintContinue
                      : context.l10n.askHintFirst,
              prefixIcon: Icon(_voice == _Voice.idle ? Icons.search : Icons.graphic_eq, color: _voice == _Voice.listening ? scheme.error : null),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (_voice == _Voice.converting)
          const SizedBox(width: 40, height: 40, child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2)))
        else if (_voice == _Voice.listening)
          IconButton.filled(
            tooltip: context.l10n.voiceStop,
            style: IconButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
            onPressed: _toggleVoice,
            icon: const Icon(Icons.stop),
          )
        else
          IconButton.filledTonal(tooltip: context.l10n.voiceStart, onPressed: c.busy ? null : _toggleVoice, icon: const Icon(Icons.mic_none)),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: c.busy || _voice != _Voice.idle ? null : _send,
          icon: c.busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
          label: Text(c.answering ? context.l10n.askAnswering : c.busy ? context.l10n.askSearching : context.l10n.askSend),
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
            c.turns.isEmpty ? context.l10n.askNewConversation : c.turns.first.question,
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
              tooltip: context.l10n.askHistory,
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
                      subtitle: Text(context.l10n.askConversationMeta(cv.turns, cv.updatedAt?.toLocal().toString().split('.').first ?? '')),
                      trailing: cv.id == c.conversationId ? Icon(Icons.check, color: scheme.primary, size: 18) : null,
                    ),
                  ),
              ],
            );
          },
        ),
        if (c.conversationId != null)
          IconButton(tooltip: context.l10n.askDeleteConversation, icon: const Icon(Icons.delete_outline), onPressed: c.busy ? null : c.deleteCurrent),
        TextButton.icon(onPressed: c.turns.isEmpty || c.busy ? null : c.newConversation, icon: const Icon(Icons.add_comment_outlined, size: 18), label: Text(context.l10n.askNewConversation)),
      ]),
    );
  }
}

/// Before the first question: what will answer, or how to get an agent.
class _Intro extends StatelessWidget {
  const _Intro({required this.status, required this.api, this.onOpenSettings});
  final Future<AskStatus> status;
  final WorklogApi api;
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
          EmptyPane(context.l10n.askIntro, icon: Icons.forum_outlined),
          if (agent != null) Text(context.l10n.askAnswerBy(agent.title, agent.detail), style: t.bodySmall?.copyWith(color: scheme.outline)),
          if (st != null && st.rail.isNotEmpty) AgentRail(stops: st.rail),
          for (final a in st?.agents.where((a) => a.needsLogin) ?? const <AgentInfo>[])
            Text('${a.title}: ${a.loginNote}', style: t.bodySmall?.copyWith(color: scheme.error), textAlign: TextAlign.center),
          if (noAgent) ...[
            Text(context.l10n.askNoAgent, style: t.bodySmall?.copyWith(color: scheme.error), textAlign: TextAlign.center),
            if (onOpenSettings != null) Padding(padding: const EdgeInsets.only(top: 10), child: FilledButton.tonalIcon(onPressed: onOpenSettings, icon: const Icon(Icons.settings_outlined), label: Text(context.l10n.askOpenSettings))),
          ],
          // where the records stand, so an empty chat also says what to do next (a review, a digest)
          KnowledgePanel(api: api, compact: true, onReview: (id) => ReviewScreen.open(context, api, id), onOpenSettings: onOpenSettings),
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
                stopping ? context.l10n.askStopping : context.l10n.askWriting(snap.data?.chosenAgent?.title ?? context.l10n.askAgentFallback),
                style: t.bodyMedium),
          ),
          if (onStop != null) ...[
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: stopping ? null : onStop,
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: Text(context.l10n.askStop),
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
            FilledButton.tonalIcon(onPressed: onOpenSettings, icon: const Icon(Icons.settings_outlined, size: 18), label: Text(context.l10n.askOpenSettings))
          else
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 18), label: Text(context.l10n.commonRetry)),
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
            Text(context.l10n.askClarifyTitle, style: t.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
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
          Text(onChoose == null ? context.l10n.askClarifyDone(_who(context.l10n, result, agent)) : context.l10n.askClarifyPrompt(_who(context.l10n, result, agent)),
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
          Text(context.l10n.askSources, style: t.labelSmall?.copyWith(color: scheme.outline)),
          for (final s in result.sources) _SourceChip(source: s, selected: selected == s.n, onTap: () => onCite(s.n)),
        ]),
        if (result.sources.isNotEmpty) ...[
          const SizedBox(height: 6),
          // digested records (log, projects, summaries, reports) against raw collected material
          Text(
            [
              context.l10n.askBasis(result.sources.where((s) => isKnowledgePath(s.path)).length, result.sources.where((s) => !isKnowledgePath(s.path)).length),
              if (!result.sources.any((s) => isKnowledgePath(s.path))) context.l10n.askBasisRawOnly,
            ].join(' · '),
            style: t.labelSmall?.copyWith(color: scheme.outline),
          ),
        ],
        const SizedBox(height: 6),
        Text(context.l10n.askAnswerMeta(_who(context.l10n, result, agent), (result.ms / 1000).toStringAsFixed(1), result.sources.length), style: t.labelSmall?.copyWith(color: scheme.outline)),
      ]),
    );
  }
}

/// The hits for a line: the first few as cards, then "모두 보기" (filters) and, when no answer was asked, "답 받기".
class _SearchBubble extends StatelessWidget {
  const _SearchBubble({required this.turn, required this.api, this.index, this.inbox, this.onOpenIndex, this.onAnswer, this.compact = false});
  final AskTurn turn;
  final WorklogApi api;
  final IndexStatus? index;
  final Inbox? inbox;
  final VoidCallback? onOpenIndex;
  final VoidCallback? onAnswer;

  /// An answer or files are the reply: the hits shrink to one line with "모두 보기".
  final bool compact;

  static const shown = 4;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (turn.searching) {
      return _Bubble(child: Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Text(context.l10n.askSearchingEllipsis, style: t.bodyMedium),
      ]));
    }
    final err = turn.searchError;
    if (err != null) return _Bubble(color: scheme.errorContainer.withValues(alpha: 0.35), child: Text(err is ApiException ? err.message : '$err'));
    final r = turn.search!;
    if (!r.ok) return compact ? const SizedBox.shrink() : _Bubble(child: SearchErrorNote(result: r, onOpenIndex: onOpenIndex));
    final hits = r.hits;
    if (compact) {
      if (hits.isEmpty) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => SearchResultsScreen.open(context, api, turn.question, r, index: index, inbox: inbox),
          icon: const Icon(Icons.filter_list, size: 16),
          label: Text(context.l10n.askSeeAllFound(hits.length)),
        ),
      );
    }
    return _Bubble(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(hits.isEmpty ? emptySearchNote(query: turn.question, total: 0, shown: 0, filtered: false, index: index, inbox: inbox) : context.l10n.askFound(hits.length),
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
              FilledButton.tonalIcon(onPressed: onAnswer, icon: const Icon(Icons.question_answer_outlined, size: 18), label: Text(context.l10n.askGetAnswer)),
            if (hits.length > 1)
              OutlinedButton.icon(
                onPressed: () => SearchResultsScreen.open(context, api, turn.question, r, index: index, inbox: inbox),
                icon: const Icon(Icons.filter_list, size: 18),
                label: Text(context.l10n.askSeeAll(hits.length)),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// The files a line asked for, each with 열기 and 내려받기.
class _FilesBubble extends StatelessWidget {
  const _FilesBubble({required this.turn, required this.api});
  final AskTurn turn;
  final WorklogApi api;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final files = turn.files;
    return _Bubble(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(files.length == 1 ? context.l10n.askOneFile : context.l10n.askFiles(files.length), style: t.labelMedium?.copyWith(color: scheme.outline)),
        for (final f in files) ...[
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
        TextButton(onPressed: () => FileScreen.open(context, api, file.path), child: Text(context.l10n.askOpen)),
        const SizedBox(width: 4),
        FilledButton.icon(onPressed: () => saveWorklogFile(context, api, file.path), icon: const Icon(Icons.download, size: 18), label: Text(context.l10n.commonDownload)),
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
        Text(context.l10n.askStopped, style: t.bodyMedium?.copyWith(color: scheme.outline)),
        const SizedBox(width: 12),
        TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 18), label: Text(context.l10n.askAskAgain)),
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
    TextSpan(text: '\n\n${context.l10n.askTooltipMore}', style: TextStyle(fontSize: 11, color: scheme.onInverseSurface.withValues(alpha: 0.7))),
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
              if (isKnowledgePath(source.path)) ...[
                const SizedBox(width: 4),
                Icon(Icons.bookmark, size: 12, color: scheme.primary, semanticLabel: context.l10n.askSourceKnowledge),
              ],
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
          Expanded(child: Text(context.l10n.askSourceIndex(idx + 1, sources.length), style: t.titleSmall)),
          IconButton(tooltip: context.l10n.askPrevSource, icon: const Icon(Icons.chevron_left), onPressed: idx > 0 ? () => go(-1) : null, visualDensity: VisualDensity.compact),
          IconButton(tooltip: context.l10n.askNextSource, icon: const Icon(Icons.chevron_right), onPressed: idx < sources.length - 1 ? () => go(1) : null, visualDensity: VisualDensity.compact),
          IconButton(tooltip: context.l10n.commonClose, icon: const Icon(Icons.close), onPressed: onClose, visualDensity: VisualDensity.compact),
        ]),
        const SizedBox(height: 6),
        Text(s.label, style: t.titleSmall?.copyWith(color: scheme.primary)),
        if (s.path.isNotEmpty) Text(s.path, style: ZaevisTheme.mono.copyWith(fontSize: 11.5, color: scheme.outline)),
        const Divider(height: 18),
        Expanded(
          child: SingleChildScrollView(
            child: SelectableText(s.passage.isEmpty ? context.l10n.askNoExcerpt : s.passage, style: t.bodyMedium, minLines: 1),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          FilledButton.tonalIcon(
            onPressed: s.path.isEmpty ? null : () => FileScreen.open(context, api, s.path),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(context.l10n.askOpenOriginal),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: s.path.isEmpty ? null : () => saveWorklogFile(context, api, s.path),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: Text(context.l10n.commonDownload),
          ),
        ]),
      ]),
    );
  }
}
