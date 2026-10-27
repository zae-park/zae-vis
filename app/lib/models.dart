// JSON models for the zaevis server API (server/src/app.ts).

typedef Json = Map<String, dynamic>;

String _str(Object? v) => v is String ? v : '';
List<String> _strList(Object? v) =>
    v is List ? v.whereType<String>().toList() : const <String>[];

class LogEntry {
  const LogEntry({
    required this.date,
    required this.projects,
    required this.tags,
    required this.text,
    required this.source,
    required this.byClaude,
    this.raw = '',
  });

  factory LogEntry.fromJson(Json j) => LogEntry(
        date: _str(j['date']),
        projects: _strList(j['projects']),
        tags: _strList(j['tags']),
        text: _str(j['text']),
        source: j['source'] is String ? j['source'] as String : null,
        byClaude: j['author'] == 'claude',
        raw: _str(j['raw']),
      );

  final String date;
  final List<String> projects;
  final List<String> tags;
  final String text;
  final String? source;
  final bool byClaude;

  /// The line exactly as it is in log/YYYY-MM.md; identifies the line when editing or deleting.
  final String raw;
}

class Project {
  const Project({
    required this.slug,
    required this.title,
    required this.status,
    required this.repos,
    required this.currentState,
    this.markdown,
  });

  factory Project.fromJson(Json j) => Project(
        slug: _str(j['slug']),
        title: _str(j['title']),
        status: _str(j['status']),
        repos: _strList(j['repos']),
        currentState: _str(j['currentState']),
        markdown: j['markdown'] is String ? j['markdown'] as String : null,
      );

  final String slug;
  final String title;
  final String status;
  final List<String> repos;
  final String currentState;
  final String? markdown;
}

class SearchHit {
  const SearchHit({
    required this.number,
    required this.title,
    required this.path,
    required this.snippet,
    this.score,
    this.weak = false,
    this.context,
  });

  factory SearchHit.fromJson(Json j) => SearchHit(
        number: (j['number'] as num?)?.toInt() ?? 0,
        title: _str(j['title']),
        path: _str(j['path']),
        snippet: _str(j['snippet']),
        score: (j['score'] as num?)?.toDouble(),
        weak: j['weak'] == true,
        context: j['context'] is Json ? HitContext.fromJson(j['context'] as Json) : null,
      );

  final int number;
  final String title;
  final String path;
  final String snippet;
  final double? score;

  /// Scored far below the top hit: shown dimmed.
  final bool weak;

  /// Where the hit comes from (source, date, section, author) and the query terms it matched.
  final HitContext? context;
}

class HitContext {
  const HitContext({required this.kind, required this.sourceLabel, this.date, this.section, this.author, this.matched = const []});

  factory HitContext.fromJson(Json j) => HitContext(
        kind: _str(j['kind']),
        sourceLabel: _str(j['sourceLabel']),
        date: _strOrNull(j['date']),
        section: _strOrNull(j['section']),
        author: _strOrNull(j['author']),
        matched: (j['matched'] is List ? j['matched'] as List : const <Object?>[]).whereType<String>().toList(),
      );

  final String kind; // git | claude-code | shell-history | transcripts | custom | log | project | summary | inbox | other
  final String sourceLabel;
  final String? date;
  final String? section;
  final String? author;
  final List<String> matched;

  /// "2026-10-26 · git 커밋 · zaevis · 박재"
  List<String> get labels => [if (date != null) date!, sourceLabel, if (section != null) section!, if (author != null) author!];
}

/// One numbered passage the answer was written from (POST /api/ask → sources[]).
class AskSource {
  const AskSource({required this.n, required this.path, required this.label, required this.passage});
  factory AskSource.fromJson(Json j) => AskSource(n: (j['n'] as num?)?.toInt() ?? 0, path: _str(j['path']), label: _str(j['label']), passage: _str(j['passage']));
  final int n;
  final String path;

  /// "2026-10-26 · git 커밋 · zaevis · 박재"
  final String label;
  final String passage;
}

/// An answer with [n] citations into [sources].
class AskResult {
  const AskResult({required this.question, required this.answer, required this.sources, required this.agent, required this.ms, this.conversationId = '', this.turn = 0});
  factory AskResult.fromJson(Json j) => AskResult(
        question: _str(j['q']),
        answer: _str(j['answer']),
        sources: (j['sources'] is List ? j['sources'] as List : const <Object?>[]).whereType<Json>().map(AskSource.fromJson).toList(),
        agent: _str(j['agent']),
        ms: (j['ms'] as num?)?.toInt() ?? 0,
        conversationId: _str(j['conversationId']),
        turn: (j['turn'] as num?)?.toInt() ?? 0,
      );
  final String question;
  final String answer;
  final List<AskSource> sources;
  final String agent; // claude | codex | gemini | openrouter
  final int ms;

  /// The conversation this turn belongs to and its index in it.
  final String conversationId;
  final int turn;

  /// The "[n]" numbers in the answer that point at an existing source.
  List<int> get cited => RegExp(r'\[(\d+)\]').allMatches(answer).map((m) => int.parse(m.group(1)!)).where((n) => n >= 1 && n <= sources.length).toSet().toList()..sort();
}

/// One row of the conversation list.
class ConversationSummary {
  const ConversationSummary({required this.id, required this.title, required this.updatedAt, required this.turns});
  factory ConversationSummary.fromJson(Json j) => ConversationSummary(
        id: _str(j['id']),
        title: _str(j['title']),
        updatedAt: DateTime.tryParse(_str(j['updatedAt'])),
        turns: (j['turns'] as num?)?.toInt() ?? 0,
      );
  final String id;
  final String title;
  final DateTime? updatedAt;
  final int turns;
}

/// GET /api/ask/:id — a conversation with every question and answer.
class Conversation {
  const Conversation({required this.id, required this.title, required this.turns});
  factory Conversation.fromJson(Json j) => Conversation(
        id: _str(j['id']),
        title: _str(j['title']),
        turns: (j['turns'] is List ? j['turns'] as List : const <Object?>[]).whereType<Json>().map(AskResult.fromJson).toList(),
      );
  final String id;
  final String title;
  final List<AskResult> turns;
}

/// GET /api/ask: which agent would answer (same choice as the weekly digest), the last answer and the conversations.
class AskStatus {
  const AskStatus({required this.agents, this.chosen, this.last, this.runningQuestion, this.conversations = const []});
  factory AskStatus.fromJson(Json j) => AskStatus(
        agents: (j['agents'] is List ? j['agents'] as List : const <Object?>[]).whereType<Json>().map(AgentInfo.fromJson).toList(),
        chosen: _strOrNull(j['chosen']),
        last: j['last'] is Json ? AskResult.fromJson(j['last'] as Json) : null,
        runningQuestion: j['running'] is Json ? _strOrNull((j['running'] as Json)['q']) : null,
        conversations: (j['conversations'] is List ? j['conversations'] as List : const <Object?>[]).whereType<Json>().map(ConversationSummary.fromJson).toList(),
      );
  final List<AgentInfo> agents;
  final String? chosen;
  final AskResult? last;
  final String? runningQuestion;
  final List<ConversationSummary> conversations;

  AgentInfo? get chosenAgent => agents.where((a) => a.id == chosen).firstOrNull;
}

class WorklogFile {
  const WorklogFile({required this.path, required this.markdown});
  factory WorklogFile.fromJson(Json j) => WorklogFile(path: _str(j['path']), markdown: _str(j['markdown']));
  final String path;
  final String markdown;
}

class SearchResult {
  const SearchResult({
    required this.ok,
    required this.hits,
    this.errorCode,
    this.errorMessage,
  });

  factory SearchResult.fromJson(Json j) {
    final err = j['error'];
    return SearchResult(
      ok: j['ok'] == true,
      hits: (j['hits'] is List ? j['hits'] as List : const <Object?>[])
          .whereType<Json>()
          .map(SearchHit.fromJson)
          .toList(),
      errorCode: err is Json ? _str(err['code']) : null,
      errorMessage: err is Json ? _str(err['message']) : null,
    );
  }

  final bool ok;
  final List<SearchHit> hits;
  final String? errorCode;
  final String? errorMessage;

  bool get needsRefresh => errorCode == 'index-not-ready';
}

class IndexStatus {
  const IndexStatus({
    required this.refreshing,
    required this.state,
    required this.stale,
    required this.messages,
    this.lastError,
    this.embedding,
    this.progress,
  });

  factory IndexStatus.fromJson(Json j) {
    final a = j['autorag'] is Json ? j['autorag'] as Json : const <String, dynamic>{};
    final diags = a['diagnostics'] is List ? a['diagnostics'] as List : const <Object?>[];
    final last = j['lastRefresh'];
    String? lastError = _str(a['lastError']).isEmpty ? null : _str(a['lastError']);
    if (last is Json && last['ok'] == false) lastError = _str(last['error']);
    return IndexStatus(
      refreshing: j['refreshing'] == true || a['inFlight'] == true,
      state: _str(a['state']),
      stale: a['stale'] == true,
      messages: diags.whereType<Json>().map((d) => _str(d['message'])).where((m) => m.isNotEmpty).toList(),
      lastError: lastError,
      embedding: j['embedding'] is Json ? EmbeddingStatus.fromJson(j['embedding'] as Json) : null,
      progress: a['progress'] is Json ? IndexProgress.fromJson(a['progress'] as Json) : null,
    );
  }

  final bool refreshing;
  final String state;
  final bool stale;
  final List<String> messages;
  final String? lastError;

  /// Local embedding daemon for semantic search; null when the server does not manage one.
  final EmbeddingStatus? embedding;

  /// Phase and counts while a refresh runs.
  final IndexProgress? progress;
}

/// `minsync serve` (local Qwen3 embedding model) as reported by GET /index.
class EmbeddingStatus {
  const EmbeddingStatus({required this.enabled, required this.state, required this.available, this.model, this.device, this.error});

  factory EmbeddingStatus.fromJson(Json j) => EmbeddingStatus(
        enabled: j['enabled'] == true,
        state: _str(j['state']),
        available: j['available'] != false,
        model: _strOrNull(j['model']),
        device: _strOrNull(j['device']),
        error: _strOrNull(j['error']),
      );

  final bool enabled;
  final String state; // off | starting | ready | failed
  final bool available;
  final String? model;
  final String? device;
  final String? error;

  String get label => switch (state) {
        'ready' => '켜짐 — ${model ?? '로컬 모델'} (${device ?? 'cpu'})',
        'starting' => '시작 중… 처음에는 모델(1.1GB)을 내려받습니다',
        'failed' => '실패: ${error ?? ''}',
        _ => available ? '꺼짐 — 키워드 검색만' : '사용 불가 (minsync 없음)',
      };
}

bool? _boolOrNull(Object? v) => v is bool ? v : null;
String? _strOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;

class SourceOption {
  const SourceOption({required this.key, required this.label, required this.kind, this.help});
  factory SourceOption.fromJson(Json j) =>
      SourceOption(key: _str(j['key']), label: _str(j['label']), kind: _str(j['kind']), help: _strOrNull(j['help']));
  final String key;
  final String label;
  final String kind; // text | path | paths | number | bool
  final String? help;
}

class SourceInfo {
  const SourceInfo({
    required this.name,
    required this.title,
    required this.description,
    required this.builtin,
    required this.enabled,
    required this.settings,
    required this.options,
    this.lastRun,
    this.lastOk,
    this.lastError,
    this.lastNote,
  });

  factory SourceInfo.fromJson(Json j) => SourceInfo(
        name: _str(j['name']),
        title: _str(j['title']),
        description: _str(j['description']),
        builtin: j['builtin'] == true,
        enabled: j['enabled'] != false,
        settings: j['settings'] is Json ? j['settings'] as Json : const <String, dynamic>{},
        options: (j['options'] is List ? j['options'] as List : const <Object?>[])
            .whereType<Json>()
            .map(SourceOption.fromJson)
            .toList(),
        lastRun: _strOrNull(j['lastRun']) == null ? null : DateTime.tryParse(j['lastRun'] as String),
        lastOk: _boolOrNull(j['lastOk']),
        lastError: _strOrNull(j['lastError']),
        lastNote: _strOrNull(j['lastNote']),
      );

  final String name;
  final String title;
  final String description;
  final bool builtin;
  final bool enabled;
  final Json settings;
  final List<SourceOption> options;
  final DateTime? lastRun;
  final bool? lastOk;
  final String? lastError;
  final String? lastNote;

  /// Value of an option as editable text ("paths" become one path per line).
  String optionText(SourceOption o) {
    final v = settings[o.key];
    if (v is List) return v.whereType<String>().join('\n');
    return v == null ? '' : '$v';
  }
}

class SourcesState {
  const SourcesState({required this.sources, required this.collecting, this.lastCollectAt, this.lastCollectError});
  factory SourcesState.fromJson(Json j) {
    final last = j['lastCollect'];
    return SourcesState(
      sources: (j['sources'] is List ? j['sources'] as List : const <Object?>[])
          .whereType<Json>()
          .map(SourceInfo.fromJson)
          .toList(),
      collecting: j['collecting'] == true,
      lastCollectAt: last is Json ? DateTime.tryParse(_str(last['finishedAt'])) : null,
      lastCollectError: last is Json ? _strOrNull(last['error']) : null,
    );
  }
  final List<SourceInfo> sources;
  final bool collecting;
  final DateTime? lastCollectAt;
  final String? lastCollectError;
}

class InboxFile {
  const InboxFile({required this.name, required this.size, this.modified});
  factory InboxFile.fromJson(Json j) => InboxFile(
        name: _str(j['name']),
        size: (j['size'] as num?)?.toInt() ?? 0,
        modified: DateTime.tryParse(_str(j['modified'])),
      );
  final String name;
  final int size;
  final DateTime? modified;
}

class TranscribeJob {
  const TranscribeJob({required this.file, required this.state, this.result, this.error});
  factory TranscribeJob.fromJson(Json j) => TranscribeJob(
        file: _str(j['file']),
        state: _str(j['state']),
        result: _strOrNull(j['result']),
        error: _strOrNull(j['error']),
      );
  final String file;
  final String state; // queued | running | done | failed
  final String? result;
  final String? error;
}

class Inbox {
  const Inbox({required this.transcripts, required this.sessions, required this.audio, required this.jobs});
  factory Inbox.fromJson(Json j) {
    List<InboxFile> files(String k) =>
        (j[k] is List ? j[k] as List : const <Object?>[]).whereType<Json>().map(InboxFile.fromJson).toList();
    return Inbox(
      transcripts: files('transcripts'),
      sessions: files('sessions'),
      audio: files('audio'),
      jobs: (j['jobs'] is List ? j['jobs'] as List : const <Object?>[])
          .whereType<Json>()
          .map(TranscribeJob.fromJson)
          .toList(),
    );
  }
  final List<InboxFile> transcripts;
  final List<InboxFile> sessions;
  final List<InboxFile> audio;
  final List<TranscribeJob> jobs;

  bool get transcribing => jobs.any((j) => j.state == 'queued' || j.state == 'running');
}

class AppSettings {
  const AppSettings({
    required this.dailyAt,
    required this.indexOnInject,
    required this.worklogDir,
    required this.scheduleSupported,
    required this.scheduleInstalled,
    required this.scheduleLoaded,
    required this.whisperx,
    this.localEmbedding = true,
    this.notifications = true,
    this.hotkey = '',
    this.rerank,
    this.scheduleHint,
    this.lastDaily,
  });

  factory AppSettings.fromJson(Json j) {
    final s = j['schedule'] is Json ? j['schedule'] as Json : const <String, dynamic>{};
    final d = j['lastDaily'];
    return AppSettings(
      dailyAt: _str(j['dailyAt']).isEmpty ? '18:30' : _str(j['dailyAt']),
      indexOnInject: j['indexOnInject'] == true,
      worklogDir: _str(j['worklogDir']),
      scheduleSupported: s['supported'] == true,
      scheduleInstalled: s['installed'] == true,
      scheduleLoaded: s['loaded'] == true,
      scheduleHint: _strOrNull(s['hint']),
      whisperx: j['whisperx'] == true,
      localEmbedding: j['localEmbedding'] != false,
      notifications: j['notifications'] != false,
      hotkey: _str(j['hotkey']),
      rerank: j['rerank'] is Json ? RerankStatus.fromJson(j['rerank'] as Json) : null,
      lastDaily: d is Json ? DateTime.tryParse(_str(d['lastRun'])) : null,
    );
  }

  final String dailyAt;
  final bool indexOnInject;
  final bool localEmbedding;
  final bool notifications;

  /// Global quick-capture hotkey as "meta+shift+space"; empty = platform default.
  final String hotkey;

  /// Optional OpenRouter re-ranking; null when the server does not offer it.
  final RerankStatus? rerank;
  final String worklogDir;
  final bool scheduleSupported;
  final bool scheduleInstalled;
  final bool scheduleLoaded;
  final String? scheduleHint;
  final bool whisperx;
  final DateTime? lastDaily;
}

/// Search re-ranking through OpenRouter: the one external model AutoRAG Lite can use. Off by default.
class RerankStatus {
  const RerankStatus({required this.enabled, required this.hasKey, required this.model, required this.external, this.keyHint});

  factory RerankStatus.fromJson(Json j) => RerankStatus(
        enabled: j['enabled'] == true,
        hasKey: j['hasKey'] == true,
        keyHint: _strOrNull(j['keyHint']),
        model: _str(j['model']),
        external: _str(j['external']),
      );

  final bool enabled;
  final bool hasKey;
  final String? keyHint;
  final String model;

  /// What leaves the machine, in plain words ("없음 — …" or "검색어와 상위 25개 문단이 …").
  final String external;

  bool get active => enabled && hasKey;
}

class KeyCheck {
  const KeyCheck({required this.ok, required this.message});
  factory KeyCheck.fromJson(Json j) => KeyCheck(ok: j['ok'] == true, message: _str(j['message']));
  final bool ok;
  final String message;
}

/// An agent the weekly digest can run with: a CLI on this Mac (user's own subscription) or the OpenRouter key.
class AgentInfo {
  const AgentInfo({required this.id, required this.title, required this.available, required this.detail});
  factory AgentInfo.fromJson(Json j) =>
      AgentInfo(id: _str(j['id']), title: _str(j['title']), available: j['available'] == true, detail: _str(j['detail']));
  final String id; // claude | codex | gemini | openrouter
  final String title;
  final bool available;
  final String detail;
}

class DigestRun {
  const DigestRun({required this.at, required this.agent, required this.ok, required this.report, this.proposalId});
  factory DigestRun.fromJson(Json j) => DigestRun(
        at: DateTime.tryParse(_str(j['lastRun'])),
        agent: _str(j['agent']),
        ok: j['ok'] == true,
        report: _str(j['report']),
        proposalId: _strOrNull(j['proposalId']),
      );
  final DateTime? at;
  final String agent;
  final bool ok;
  final String report;

  /// Set when the run was held for review instead of being written to the worklog.
  final String? proposalId;
}

/// GET /api/digest: detected agents, the setting, what would run, and the last run.
class DigestStatus {
  const DigestStatus({
    required this.running,
    required this.agent,
    required this.model,
    required this.weekly,
    required this.agents,
    this.review = true,
    this.chosen,
    this.runningAgent,
    this.last,
    this.nextWeekly,
  });

  factory DigestStatus.fromJson(Json j) {
    final s = j['setting'] is Json ? j['setting'] as Json : const <String, dynamic>{};
    return DigestStatus(
      running: j['running'] == true,
      runningAgent: _strOrNull(j['agent']),
      agent: _str(s['agent']).isEmpty ? 'auto' : _str(s['agent']),
      model: _str(s['model']),
      weekly: s['weekly'] != false,
      review: s['review'] != false,
      agents: (j['agents'] is List ? j['agents'] as List : const <Object?>[]).whereType<Json>().map(AgentInfo.fromJson).toList(),
      chosen: _strOrNull(j['chosen']),
      last: j['last'] is Json ? DigestRun.fromJson(j['last'] as Json) : null,
      nextWeekly: _strOrNull(j['nextWeekly']),
    );
  }

  final bool running;
  final String? runningAgent;
  final String agent; // auto | claude | codex | gemini | openrouter
  final String model;
  final bool weekly;
  final List<AgentInfo> agents;

  /// The agent "auto" (or the explicit choice) resolves to right now; null when nothing can run.
  final String? chosen;
  final DigestRun? last;
  final String? nextWeekly;

  /// Review before apply: a run leaves a proposal instead of writing the worklog directly.
  final bool review;
}

/// One row of GET /api/digest/proposals.
class ProposalSummary {
  const ProposalSummary({required this.id, required this.createdAt, required this.agent, required this.status, required this.lines, required this.projects, required this.summaries, required this.processed});
  factory ProposalSummary.fromJson(Json j) => ProposalSummary(
        id: _str(j['id']),
        createdAt: DateTime.tryParse(_str(j['createdAt'])),
        agent: _str(j['agent']),
        status: _str(j['status']),
        lines: (j['lines'] as num?)?.toInt() ?? 0,
        projects: (j['projects'] as num?)?.toInt() ?? 0,
        summaries: (j['summaries'] as num?)?.toInt() ?? 0,
        processed: (j['processed'] as num?)?.toInt() ?? 0,
      );
  final String id;
  final DateTime? createdAt;
  final String agent;
  final String status; // pending | applied | dismissed
  final int lines;
  final int projects;
  final int summaries;
  final int processed;
  bool get pending => status == 'pending';
}

class ProposedLine {
  const ProposedLine({required this.month, required this.line, required this.entry});
  factory ProposedLine.fromJson(Json j) => ProposedLine(
        month: _str(j['month']),
        line: _str(j['line']),
        entry: j['entry'] is Json ? LogEntry.fromJson(j['entry'] as Json) : LogEntry(date: '', projects: const [], tags: const [], text: _str(j['line']), source: null, byClaude: true),
      );
  final String month;
  final String line;
  final LogEntry entry;
}

class ProposedProject {
  const ProposedProject({required this.slug, required this.before, required this.after});
  factory ProposedProject.fromJson(Json j) => ProposedProject(slug: _str(j['slug']), before: j['before'] is String ? j['before'] as String : null, after: _str(j['after']));
  final String slug;
  final String? before;
  final String after;
  bool get isNew => before == null;
}

class ProposedFile {
  const ProposedFile({required this.path, required this.before, required this.after});
  factory ProposedFile.fromJson(Json j) => ProposedFile(path: _str(j['path']), before: j['before'] is String ? j['before'] as String : null, after: _str(j['after']));
  final String path;
  final String? before;
  final String after;
}

/// A digest run's changes, waiting for the user to pick what to keep.
class Proposal {
  const Proposal({
    required this.id,
    required this.createdAt,
    required this.agent,
    required this.report,
    required this.status,
    required this.logLines,
    required this.removedLines,
    required this.projects,
    required this.summaries,
    required this.processed,
  });

  factory Proposal.fromJson(Json j) {
    List<T> list<T>(String k, T Function(Json) f) => (j[k] is List ? j[k] as List : const <Object?>[]).whereType<Json>().map(f).toList();
    return Proposal(
      id: _str(j['id']),
      createdAt: DateTime.tryParse(_str(j['createdAt'])),
      agent: _str(j['agent']),
      report: _str(j['report']),
      status: _str(j['status']),
      logLines: list('logLines', ProposedLine.fromJson),
      removedLines: list('removedLines', ProposedLine.fromJson),
      projects: list('projects', ProposedProject.fromJson),
      summaries: list('summaries', ProposedFile.fromJson),
      processed: list('processed', (m) => (from: _str(m['from']), to: _str(m['to']))),
    );
  }

  final String id;
  final DateTime? createdAt;
  final String agent;
  final String report;
  final String status;
  final List<ProposedLine> logLines;
  final List<ProposedLine> removedLines;
  final List<ProposedProject> projects;
  final List<ProposedFile> summaries;
  final List<({String from, String to})> processed;
  bool get pending => status == 'pending';
}

/// Progress of a running index refresh, from AutoRAG's progress file. Phases run in order:
/// parsed (read every file) → minsync (embed + index) → datasources → jikji → everything → fsearch → finalizing.
class IndexProgress {
  const IndexProgress({required this.phase, this.total, this.scanned, this.written, this.synced});
  factory IndexProgress.fromJson(Json j) {
    final src = j['sourceFiles'] is Json ? j['sourceFiles'] as Json : const <String, dynamic>{};
    final counts = j['parsedCounts'] is Json ? j['parsedCounts'] as Json : const <String, dynamic>{};
    final ms = j['minsync'] is Json ? j['minsync'] as Json : const <String, dynamic>{};
    return IndexProgress(
      phase: _str(j['phase']),
      total: (src['total'] as num?)?.toInt(),
      scanned: (counts['scanned'] as num?)?.toInt(),
      written: (counts['written'] as num?)?.toInt(),
      synced: (ms['synced'] as num?)?.toInt(),
    );
  }
  final String phase;
  final int? total;
  final int? scanned;
  final int? written;
  final int? synced;

  static const _order = ['parsed', 'minsync', 'datasources', 'jikji', 'everything', 'fsearch', 'finalizing'];

  /// Overall 0..1: reading files is the first 60%, embedding the next 30%, the rest the last 10%.
  /// Null (indeterminate) before the first count arrives.
  double? get fraction {
    final i = _order.indexOf(phase);
    if (i < 0) return null;
    if (phase == 'parsed') {
      if (total == null || total! <= 0 || scanned == null) return null;
      return 0.6 * (scanned! / total!).clamp(0, 1);
    }
    if (phase == 'minsync') {
      if (total == null || total! <= 0 || synced == null) return 0.6;
      return 0.6 + 0.3 * (synced! / total!).clamp(0, 1);
    }
    return 0.9 + 0.1 * ((i - 1) / (_order.length - 2)); // datasources … finalizing → 0.92 … 1.0
  }

  /// "본문 읽는 중 12/40 파일"
  String get label {
    final files = total != null && scanned != null ? ' $scanned/$total 파일' : '';
    final emb = synced != null ? ' $synced개' : '';
    return switch (phase) {
      'parsed' => '본문 읽는 중$files',
      'minsync' => '임베딩·색인 중$emb',
      'datasources' => '커넥터 색인 중',
      'jikji' => '키워드 색인 정리 중',
      'everything' || 'fsearch' => '파일 이름 색인 중',
      'finalizing' => '마무리 중',
      '' => '준비 중',
      _ => phase,
    };
  }
}
