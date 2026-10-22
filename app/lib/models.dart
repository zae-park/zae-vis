// JSON models for the worklog-kit server API (server/src/app.ts).

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
    );
  }

  final bool refreshing;
  final String state;
  final bool stale;
  final List<String> messages;
  final String? lastError;
}
