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
  const HitContext({required this.kind, required this.sourceLabel, this.datasource, this.file, this.date, this.section, this.author, this.matched = const []});

  factory HitContext.fromJson(Json j) {
    final datasource = _strOrNull(j['datasource']);
    return HitContext(
      // one filter chip per external source: "external:obsidian", "external:slack" …
      kind: datasource == null ? _str(j['kind']) : 'external:$datasource',
      sourceLabel: _str(j['sourceLabel']),
      datasource: datasource,
      file: _strOrNull(j['file']),
      date: _strOrNull(j['date']),
      section: _strOrNull(j['section']),
      author: _strOrNull(j['author']),
      matched: (j['matched'] is List ? j['matched'] as List : const <Object?>[]).whereType<String>().toList(),
    );
  }

  final String kind; // git | claude-code | shell-history | transcripts | custom | log | project | summary | inbox | external:<id> | other
  final String sourceLabel;

  /// AutoRAG external datasource the hit came from (obsidian, slack …); null for worklog hits.
  final String? datasource;

  /// Absolute path of the original behind an external hit, when it is a local file.
  final String? file;
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
  const AskResult({required this.question, required this.answer, required this.sources, required this.agent, required this.ms, this.conversationId = '', this.turn = 0, this.rail = const []});
  factory AskResult.fromJson(Json j) => AskResult(
        question: _str(j['q']),
        answer: _str(j['answer']),
        sources: (j['sources'] is List ? j['sources'] as List : const <Object?>[]).whereType<Json>().map(AskSource.fromJson).toList(),
        agent: _str(j['agent']),
        ms: (j['ms'] as num?)?.toInt() ?? 0,
        conversationId: _str(j['conversationId']),
        turn: (j['turn'] as num?)?.toInt() ?? 0,
        rail: RailStop.list(j['rail']),
      );
  final String question;
  final String answer;
  final List<AskSource> sources;
  final String agent; // claude | codex | gemini | openrouter
  final int ms;

  /// The conversation this turn belongs to and its index in it.
  final String conversationId;
  final int turn;

  /// How the answer was produced: quota skips, then the stop that wrote it.
  final List<RailStop> rail;

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
  const AskStatus({required this.agents, this.chosen, this.last, this.runningQuestion, this.conversations = const [], this.rail = const [], this.runningRail = const []});
  factory AskStatus.fromJson(Json j) {
    final running = j['running'] is Json ? j['running'] as Json : null;
    return AskStatus(
      agents: (j['agents'] is List ? j['agents'] as List : const <Object?>[]).whereType<Json>().map(AgentInfo.fromJson).toList(),
      chosen: _strOrNull(j['chosen']),
      last: j['last'] is Json ? AskResult.fromJson(j['last'] as Json) : null,
      runningQuestion: running == null ? null : _strOrNull(running['q']),
      runningRail: running == null ? const [] : RailStop.list(running['rail']),
      conversations: (j['conversations'] is List ? j['conversations'] as List : const <Object?>[]).whereType<Json>().map(ConversationSummary.fromJson).toList(),
      rail: RailStop.list(j['rail']),
    );
  }
  final List<AgentInfo> agents;
  final String? chosen;
  final AskResult? last;
  final String? runningQuestion;
  final List<ConversationSummary> conversations;

  /// The chain as it stands now: the live attempt while a question runs, otherwise who would be tried.
  final List<RailStop> rail;

  /// Stops reported on the in-flight question, including ones already skipped for quota.
  final List<RailStop> runningRail;

  AgentInfo? get chosenAgent => agents.where((a) => a.id == chosen).firstOrNull;
}

/// One collected or ingested file: the "원본" layer behind the log lines.
class OriginFile {
  const OriginFile({required this.path, required this.source, required this.kind, required this.date, required this.name, required this.bytes});
  factory OriginFile.fromJson(Json j) => OriginFile(
        path: _str(j['path']),
        source: _str(j['source']),
        kind: _str(j['kind']),
        date: _str(j['date']),
        name: _str(j['name']),
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
      );
  final String path;
  final String source; // git | agent-sessions | shell-history | <connector> | transcripts | session-notes
  final String kind; // source | inbox | processed
  final String date;
  final String name;
  final int bytes;

  String get sourceLabel => switch (source) {
        'git' => 'git 커밋',
        'agent-sessions' => '에이전트 세션',
        'claude-code' => 'Claude Code 세션',
        'shell-history' => '셸 명령',
        'transcripts' => '전사본',
        'session-notes' => '세션 노트',
        _ => source,
      };
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
    this.tokenizer,
  });

  factory IndexStatus.fromJson(Json j) {
    final a = j['autorag'] is Json ? j['autorag'] as Json : const <String, dynamic>{};
    // the Kiwi warning is shown as its own row (with the install button), not as a raw English message
    final diags = (a['diagnostics'] is List ? a['diagnostics'] as List : const <Object?>[]).where((d) => d is! Json || d['code'] != TokenizerStatus.warningCode);
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
      tokenizer: j['tokenizer'] is Json ? TokenizerStatus.fromJson(j['tokenizer'] as Json) : null,
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

  /// Korean keyword tokenizer (Kiwi) state; null when the server does not report it.
  final TokenizerStatus? tokenizer;
}

/// What the BM25 index tokenizes with — Kiwi morphemes (`multilingual`) or whitespace only — and whether
/// Kiwi is installed. Mirrors `tokenizer` in GET /index and GET /settings.
class TokenizerStatus {
  const TokenizerStatus({required this.active, required this.needsReindex, required this.kiwi});

  /// AutoRAG's diagnostic code when Kiwi is missing.
  static const warningCode = 'lexical-tokenizer-unavailable';

  factory TokenizerStatus.fromJson(Json j) => TokenizerStatus(
        active: _str(j['active']),
        needsReindex: j['needsReindex'] == true,
        kiwi: j['kiwi'] is Json ? KiwiStatus.fromJson(j['kiwi'] as Json) : const KiwiStatus(installed: false),
      );

  /// 'multilingual' (Kiwi morphemes + whole words), 'whitespace', or 'unknown' (no index yet).
  final String active;

  /// Kiwi is here but the index was built without it: rebuild from scratch.
  final bool needsReindex;
  final KiwiStatus kiwi;

  bool get morphemes => active == 'multilingual';

  /// One line for the index sheet and settings.
  String get label => morphemes
      ? '형태소 분석 (Kiwi) — 인증서를 → 인증서처럼 조사·어미가 붙은 말도 찾습니다'
      : kiwi.installed
          ? (needsReindex ? 'Kiwi 설치됨 — 처음부터 다시 색인하면 형태소 분석이 켜집니다' : '아직 색인 전 — 다음 색인부터 형태소 분석')
          : '공백 기준 — 조사·어미가 붙은 말(인증서를)은 검색어(인증서)와 맞지 않습니다';
}

/// The Kiwi library + model as the server found them (`zaevis ext install kiwi` puts them in <상태 폴더>/ext/kiwi).
class KiwiStatus {
  const KiwiStatus({required this.installed, this.library, this.model, this.source, this.version, this.asset, this.downloadMb = 0});

  factory KiwiStatus.fromJson(Json j) => KiwiStatus(
        installed: j['installed'] == true,
        library: _strOrNull(j['library']),
        model: _strOrNull(j['model']),
        source: _strOrNull(j['source']),
        version: _strOrNull(j['version']),
        asset: _strOrNull(j['asset']),
        downloadMb: j['downloadMb'] is num ? (j['downloadMb'] as num).round() : 0,
      );

  final bool installed;
  final String? library;
  final String? model;

  /// 'zaevis' (our install), 'user' (~/.local/kiwi), 'system', 'env' (KIWI_* variables) or null.
  final String? source;
  final String? version;

  /// Release asset for this platform; null means no one-click install here.
  final String? asset;
  final int downloadMb;

  bool get installable => asset != null;
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
    this.tokenizer,
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
      tokenizer: j['tokenizer'] is Json ? TokenizerStatus.fromJson(j['tokenizer'] as Json) : null,
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

  /// Korean morphological tokenizer (Kiwi); null when the server does not report it.
  final TokenizerStatus? tokenizer;
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
  const AgentInfo({required this.id, required this.title, required this.available, required this.detail, this.loggedIn, this.loginHint});
  factory AgentInfo.fromJson(Json j) => AgentInfo(
        id: _str(j['id']),
        title: _str(j['title']),
        available: j['available'] == true,
        detail: _str(j['detail']),
        loggedIn: _boolOrNull(j['loggedIn']),
        loginHint: _strOrNull(j['loginHint']),
      );
  final String id; // claude | codex | gemini | openrouter
  final String title;
  final bool available;
  final String detail;

  /// A CLI's sign-in state: false = installed but it would answer "Not logged in"; null = unknown / not a CLI.
  final bool? loggedIn;
  final String? loginHint;

  /// Installed, but the server found it signed out — the digest, 질문 and reports skip it until the user logs in.
  bool get needsLogin => available && loggedIn == false;

  /// "로그인 필요: 터미널에서 claude login"
  String get loginNote => '로그인 필요: ${loginHint ?? '터미널에서 로그인'}';
}

/// One stop on the agent rail: ready, writing, skipped for quota, or the one that wrote.
class RailStop {
  const RailStop({required this.id, required this.title, required this.state, this.metered = false, this.reason});
  factory RailStop.fromJson(Json j) => RailStop(
        id: _str(j['id']),
        title: _str(j['title']),
        state: _str(j['state']).isEmpty ? 'off' : _str(j['state']),
        metered: j['metered'] == true,
        reason: _strOrNull(j['reason']),
      );
  static List<RailStop> list(Object? raw) => raw is List ? raw.whereType<Json>().map(RailStop.fromJson).toList() : const [];

  final String id;
  final String title;

  /// off | login | ready | running | quota | wrote | error
  final String state;
  final bool metered;
  final String? reason;
}

class DigestRun {
  const DigestRun({required this.at, required this.agent, required this.ok, required this.report, this.proposalId, this.rail = const []});
  factory DigestRun.fromJson(Json j) => DigestRun(
        at: DateTime.tryParse(_str(j['lastRun'])),
        agent: _str(j['agent']),
        ok: j['ok'] == true,
        report: _str(j['report']),
        proposalId: _strOrNull(j['proposalId']),
        rail: RailStop.list(j['rail']),
      );
  final DateTime? at;
  final String agent;
  final bool ok;
  final String report;

  /// Set when the run was held for review instead of being written to the worklog.
  final String? proposalId;
  final List<RailStop> rail;
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
    this.rail = const [],
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
      rail: RailStop.list(j['rail']),
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

  /// Who would run, or the live attempt while a digest is in progress.
  final List<RailStop> rail;

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

// ── external AutoRAG datasources (GET /api/datasources) ──────────────────────

class DatasourceField {
  const DatasourceField({required this.key, required this.label, required this.kind, this.required = false, this.help, this.placeholder, this.defaultValue});
  factory DatasourceField.fromJson(Json j) => DatasourceField(
        key: _str(j['key']),
        label: _str(j['label']),
        kind: _str(j['kind']),
        required: j['required'] == true,
        help: _strOrNull(j['help']),
        placeholder: _strOrNull(j['placeholder']),
        defaultValue: _strOrNull(j['defaultValue']),
      );
  final String key;
  final String label;
  final String kind; // text | path | list | env
  final bool required;
  final String? help;
  final String? placeholder;
  final String? defaultValue;
}

/// What the server knows about one CLI-backed or built-in AutoRAG datasource template (plus its connection, if any).
class ExternalDatasource {
  const ExternalDatasource({
    required this.name,
    required this.template,
    required this.title,
    required this.description,
    required this.fields,
    required this.configured,
    required this.enabled,
    required this.connector,
    this.cliBin,
    this.install,
    this.homepage,
    this.auth,
    this.installKind,
    this.external,
    this.installed,
    this.archive,
    this.env = const [],
    this.unavailable,
    this.note,
    this.autoragStatus,
    this.lastSync,
    this.lastOk,
    this.lastError,
    this.chunks,
  });

  factory ExternalDatasource.fromJson(Json j) {
    final cli = j['cli'] is Json ? j['cli'] as Json : null;
    final probe = j['probe'] is Json ? j['probe'] as Json : const <String, dynamic>{};
    final autorag = j['autorag'] is Json ? j['autorag'] as Json : null;
    final sync = j['sync'] is Json ? j['sync'] as Json : null;
    return ExternalDatasource(
      name: _str(j['name']),
      template: _str(j['template']),
      title: _str(j['title']),
      description: _str(j['description']),
      fields: (j['fields'] is List ? j['fields'] as List : const <Object?>[]).whereType<Json>().map(DatasourceField.fromJson).toList(),
      configured: j['configured'] == true,
      enabled: j['enabled'] == true,
      connector: j['connector'] is Json ? j['connector'] as Json : const <String, dynamic>{},
      cliBin: cli == null ? null : _strOrNull(cli['bin']),
      install: cli == null ? null : _strOrNull(cli['install']),
      homepage: cli == null ? null : _strOrNull(cli['homepage']),
      external: _strOrNull(j['external']),
      installed: _boolOrNull(probe['installed']),
      archive: _boolOrNull(probe['archive']),
      env: (probe['env'] is List ? probe['env'] as List : const <Object?>[])
          .whereType<Json>()
          .map((e) => (name: _str(e['name']), set: e['set'] == true, stored: e['stored'] == true))
          .toList(),
      auth: cli == null ? null : _strOrNull(cli['auth']),
      installKind: cli == null ? null : (cli['npm'] is String ? 'npm' : cli['brew'] is String ? 'brew' : null),
      unavailable: _strOrNull(probe['unavailable']),
      note: _strOrNull(j['note']),
      autoragStatus: autorag == null ? null : _strOrNull(autorag['status']),
      lastSync: sync == null ? null : DateTime.tryParse(_str(sync['lastSync'])),
      lastOk: sync == null ? null : _boolOrNull(sync['ok']),
      lastError: sync == null ? null : _strOrNull(sync['error']),
      chunks: sync == null ? null : (sync['chunks'] is num ? (sync['chunks'] as num).toInt() : null),
    );
  }

  final String name;
  final String template;
  final String title;
  final String description;
  final List<DatasourceField> fields;
  final bool configured;
  final bool enabled;
  final Json connector;
  final String? cliBin;
  final String? install;
  final String? homepage;

  /// What the user still has to do inside the tool (login, token) — zaevis never collects those.
  final String? auth;

  /// "npm" | "brew" when `zaevis ext install <cliBin>` can do the install; null = terminal only.
  final String? installKind;

  /// What leaves the machine, if anything.
  final String? external;

  /// null when the template needs no CLI.
  final bool? installed;
  final bool? archive;
  final List<({String name, bool set, bool stored})> env;
  final String? unavailable;
  final String? note;
  final String? autoragStatus;
  final DateTime? lastSync;
  final bool? lastOk;
  final String? lastError;
  final int? chunks;

  /// Needs a CLI that is not on this machine.
  bool get needsInstall => installed == false;

  /// Value of a connector field as editable text (lists one item per line).
  String fieldText(DatasourceField f) {
    final v = connector[f.key];
    if (v is List) return v.map((e) => '$e').join('\n');
    if (v == null) return f.kind == 'env' ? (f.defaultValue ?? '') : '';
    return '$v';
  }
}

class DatasourcesState {
  const DatasourcesState({required this.datasources, required this.syncing});
  factory DatasourcesState.fromJson(Json j) => DatasourcesState(
        datasources: (j['datasources'] is List ? j['datasources'] as List : const <Object?>[]).whereType<Json>().map(ExternalDatasource.fromJson).toList(),
        syncing: j['syncing'] == true,
      );
  final List<ExternalDatasource> datasources;
  final bool syncing;
}

// ── reports (daily / weekly / monthly) ─────────────────────────────────────

const reportKinds = ['daily', 'weekly', 'monthly'];
const weekdayCodes = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const weekdayPresets = {
  'weekdays': ['mon', 'tue', 'wed', 'thu', 'fri'],
  'weekend': ['sat', 'sun'],
  'everyday': weekdayCodes,
};

String reportKindLabel(String kind) => switch (kind) { 'daily' => '일간', 'weekly' => '주간', 'monthly' => '월간', _ => kind };

String weekdayLabel(String code) =>
    const {'mon': '월', 'tue': '화', 'wed': '수', 'thu': '목', 'fri': '금', 'sat': '토', 'sun': '일'}[code] ?? code;

/// ISO week (Mon–Sun) of a day: the Thursday of the week decides the year.
({int year, int week}) isoWeekOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day, 12);
  final thursday = day.add(Duration(days: 3 - (day.weekday - 1)));
  final jan4 = DateTime(thursday.year, 1, 4, 12);
  final week = 1 + ((thursday.difference(jan4).inDays - 3 + (jan4.weekday - 1)) / 7).round();
  return (year: thursday.year, week: week);
}

String _two(int n) => n.toString().padLeft(2, '0');
String dailyPeriod(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String weeklyPeriod(DateTime d) {
  final w = isoWeekOf(d);
  return '${w.year}-W${_two(w.week)}';
}

String monthlyPeriod(DateTime d) => '${d.year}-${_two(d.month)}';

/// The "지금 만들기" choices: a kind and the period it means on day [now].
class ReportChoice {
  const ReportChoice(this.label, this.kind, this.period);
  final String label;
  final String kind;
  final String period;

  static List<ReportChoice> forNow(DateTime now) {
    final yesterday = now.subtract(const Duration(days: 1));
    final lastWeek = now.subtract(const Duration(days: 7));
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    return [
      ReportChoice('오늘', 'daily', dailyPeriod(now)),
      ReportChoice('어제', 'daily', dailyPeriod(yesterday)),
      ReportChoice('이번 주', 'weekly', weeklyPeriod(now)),
      ReportChoice('지난주', 'weekly', weeklyPeriod(lastWeek)),
      ReportChoice('이번 달', 'monthly', monthlyPeriod(now)),
      ReportChoice('지난달', 'monthly', monthlyPeriod(lastMonth)),
    ];
  }
}

/// One report on disk, as GET /api/reports lists them per kind.
class ReportEntry {
  const ReportEntry({required this.kind, required this.period, required this.path, this.createdAt, this.agent});
  factory ReportEntry.fromJson(Json j) => ReportEntry(
        kind: _str(j['kind']),
        period: _str(j['period']),
        path: _str(j['path']),
        createdAt: DateTime.tryParse(_str(j['createdAt'])),
        agent: _strOrNull(j['agent']),
      );
  final String kind;
  final String period;
  final String path;
  final DateTime? createdAt;

  /// Null for a monthly summary the weekly digest wrote (no front matter).
  final String? agent;
}

/// GET /api/reports/:kind/:period.
class Report {
  const Report({required this.kind, required this.period, required this.path, required this.markdown, this.createdAt, this.agent, this.rangeLabel});
  factory Report.fromJson(Json j) {
    final range = j['range'] is Json ? j['range'] as Json : const <String, dynamic>{};
    return Report(
      kind: _str(j['kind']),
      period: _str(j['period']),
      path: _str(j['path']),
      markdown: _str(j['markdown']),
      createdAt: DateTime.tryParse(_str(j['createdAt'])),
      agent: _strOrNull(j['agent']),
      rangeLabel: _strOrNull(range['label']),
    );
  }
  final String kind;
  final String period;
  final String path;
  final String markdown;
  final DateTime? createdAt;
  final String? agent;
  final String? rangeLabel;
}

/// The last run of one kind (state.json), successful or not.
class ReportRun {
  const ReportRun({required this.kind, required this.period, required this.ok, this.at, this.agent, this.error, this.path, this.rail = const []});
  factory ReportRun.fromJson(Json j) => ReportRun(
        kind: _str(j['kind']),
        period: _str(j['period']),
        ok: j['ok'] == true,
        at: DateTime.tryParse(_str(j['at'])),
        agent: _strOrNull(j['agent']),
        error: _strOrNull(j['error']),
        path: _strOrNull(j['path']),
        rail: RailStop.list(j['rail']),
      );
  final String kind;
  final String period;
  final bool ok;
  final DateTime? at;
  final String? agent;
  final String? error;
  final String? path;
  final List<RailStop> rail;
}

/// config.reports: when the daily job writes which report.
class ReportSettings {
  const ReportSettings({
    this.dailyEnabled = false,
    this.dailyDays = const ['mon', 'tue', 'wed', 'thu', 'fri'],
    this.weeklyEnabled = false,
    this.weeklyDay = 'mon',
    this.monthlyEnabled = true,
    this.monthlyDay = 1,
  });
  factory ReportSettings.fromJson(Json j) {
    final d = j['daily'] is Json ? j['daily'] as Json : const <String, dynamic>{};
    final w = j['weekly'] is Json ? j['weekly'] as Json : const <String, dynamic>{};
    final m = j['monthly'] is Json ? j['monthly'] as Json : const <String, dynamic>{};
    return ReportSettings(
      dailyEnabled: d['enabled'] == true,
      dailyDays: d['days'] is List ? _strList(d['days']) : const ['mon', 'tue', 'wed', 'thu', 'fri'],
      weeklyEnabled: w['enabled'] == true,
      weeklyDay: _str(w['day']).isEmpty ? 'mon' : _str(w['day']),
      monthlyEnabled: m['enabled'] != false,
      monthlyDay: m['day'] is int ? m['day'] as int : 1,
    );
  }
  final bool dailyEnabled;
  final List<String> dailyDays;
  final bool weeklyEnabled;
  final String weeklyDay;
  final bool monthlyEnabled;
  final int monthlyDay;

  /// Which preset the chosen days are, or null for a custom set.
  String? get dailyPreset {
    for (final e in weekdayPresets.entries) {
      if (e.value.length == dailyDays.length && e.value.every(dailyDays.contains)) return e.key;
    }
    return null;
  }
}

/// GET /api/reports.
class ReportsStatus {
  const ReportsStatus({required this.settings, required this.reports, this.running, this.lastRun = const {}, this.defaults = const {}, this.agents = const [], this.chosen, this.rail = const []});
  factory ReportsStatus.fromJson(Json j) {
    final r = j['reports'] is Json ? j['reports'] as Json : const <String, dynamic>{};
    final last = j['lastRun'] is Json ? j['lastRun'] as Json : const <String, dynamic>{};
    final run = j['running'];
    final defaults = j['defaults'] is Json ? j['defaults'] as Json : const <String, dynamic>{};
    return ReportsStatus(
      settings: ReportSettings.fromJson(j['setting'] is Json ? j['setting'] as Json : const <String, dynamic>{}),
      reports: {
        for (final k in reportKinds) k: (r[k] is List ? r[k] as List : const <Object?>[]).whereType<Json>().map(ReportEntry.fromJson).toList(),
      },
      running: run is Json ? ReportRunning(kind: _str(run['kind']), period: _str(run['period']), agent: _strOrNull(run['agent']), rail: RailStop.list(run['rail'])) : null,
      rail: RailStop.list(j['rail']),
      lastRun: {for (final e in last.entries) if (e.value is Json) e.key: ReportRun.fromJson(e.value as Json)},
      defaults: {for (final e in defaults.entries) e.key: _str(e.value)},
      agents: (j['agents'] is List ? j['agents'] as List : const <Object?>[]).whereType<Json>().map(AgentInfo.fromJson).toList(),
      chosen: _strOrNull(j['chosen']),
    );
  }
  final ReportSettings settings;
  final Map<String, List<ReportEntry>> reports;
  final ReportRunning? running;
  final Map<String, ReportRun> lastRun;

  /// The agents the server found (same list as the digest) and which one would write a report now.
  final List<AgentInfo> agents;
  final String? chosen;
  final List<RailStop> rail;
  AgentInfo? get chosenAgent => agents.where((a) => a.id == chosen).firstOrNull;

  /// What a run without a period would make now, per kind.
  final Map<String, String> defaults;

  List<ReportEntry> of(String kind) => reports[kind] ?? const [];
}

class ReportRunning {
  const ReportRunning({required this.kind, required this.period, this.agent, this.rail = const []});
  final String kind;
  final String period;
  final String? agent;
  final List<RailStop> rail;
}
