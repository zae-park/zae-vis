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
  });

  factory LogEntry.fromJson(Json j) => LogEntry(
        date: _str(j['date']),
        projects: _strList(j['projects']),
        tags: _strList(j['tags']),
        text: _str(j['text']),
        source: j['source'] is String ? j['source'] as String : null,
        byClaude: j['author'] == 'claude',
      );

  final String date;
  final List<String> projects;
  final List<String> tags;
  final String text;
  final String? source;
  final bool byClaude;
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
  });

  factory SearchHit.fromJson(Json j) => SearchHit(
        number: (j['number'] as num?)?.toInt() ?? 0,
        title: _str(j['title']),
        path: _str(j['path']),
        snippet: _str(j['snippet']),
        score: (j['score'] as num?)?.toDouble(),
      );

  final int number;
  final String title;
  final String path;
  final String snippet;
  final double? score;
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
    );
  }

  final bool refreshing;
  final String state;
  final bool stale;
  final List<String> messages;
  final String? lastError;

  /// Local embedding daemon for semantic search; null when the server does not manage one.
  final EmbeddingStatus? embedding;
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
  const SourceOption({required this.key, required this.label, required this.kind});
  factory SourceOption.fromJson(Json j) =>
      SourceOption(key: _str(j['key']), label: _str(j['label']), kind: _str(j['kind']));
  final String key;
  final String label;
  final String kind; // text | path | paths | number
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
      lastDaily: d is Json ? DateTime.tryParse(_str(d['lastRun'])) : null,
    );
  }

  final String dailyAt;
  final bool indexOnInject;
  final bool localEmbedding;
  final String worklogDir;
  final bool scheduleSupported;
  final bool scheduleInstalled;
  final bool scheduleLoaded;
  final String? scheduleHint;
  final bool whisperx;
  final DateTime? lastDaily;
}
