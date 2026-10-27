import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'models.dart';

/// Server address. Override at build time with
/// `--dart-define=ZAEVIS_API=http://127.0.0.1:4710`.
const _definedBase = String.fromEnvironment('ZAEVIS_API');
const defaultDesktopBase = 'http://127.0.0.1:4710';

String defaultBaseUrl() {
  if (_definedBase.isNotEmpty) return _definedBase;
  // The web build is served by the worklog server itself, so use the same origin.
  if (kIsWeb && Uri.base.scheme.startsWith('http')) return Uri.base.origin;
  return defaultDesktopBase;
}

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() => status == 0 ? message : '$message ($status)';
}

class WorklogApi {
  WorklogApi({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? defaultBaseUrl(),
        _client = client ?? http.Client();

  String baseUrl;
  final http.Client _client;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(path: '${base.path.replaceAll(RegExp(r'/$'), '')}/api$path', queryParameters: query);
  }

  Future<Json> _get(String path, [Map<String, String>? query]) async {
    final http.Response res;
    try {
      res = await _client.get(_uri(path, query));
    } catch (_) {
      throw ApiException(0, '서버에 연결할 수 없습니다: $baseUrl');
    }
    return _decode(res);
  }

  Json _decode(http.Response res) {
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode >= 400) {
      String? message;
      try {
        final j = jsonDecode(body);
        if (j is Json) message = (j['message'] ?? j['reason']) is String ? (j['message'] ?? j['reason']) as String : null;
      } catch (_) {}
      throw ApiException(res.statusCode, message ?? (res.statusCode == 404 ? '찾을 수 없습니다' : '요청이 실패했습니다'));
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiException(res.statusCode, '응답 형식이 올바르지 않습니다');
    }
    if (decoded is! Json) throw ApiException(res.statusCode, '응답 형식이 올바르지 않습니다');
    return decoded;
  }

  Future<bool> health() async {
    try {
      return (await _get('/health'))['ok'] == true;
    } on ApiException {
      return false;
    }
  }

  Future<List<String>> logMonths() async => _months(await _get('/logs'));
  Future<List<String>> summaryMonths() async => _months(await _get('/summaries'));

  List<String> _months(Json j) =>
      (j['months'] is List ? j['months'] as List : const <Object?>[]).whereType<String>().toList();

  Future<List<LogEntry>> log(String month) async {
    final j = await _get('/logs/${Uri.encodeComponent(month)}');
    final list = j['entries'] is List ? j['entries'] as List : const <Object?>[];
    return list.whereType<Json>().map(LogEntry.fromJson).toList();
  }

  /// Edits one log line, identified by its current text ([raw]). A 409 means the file changed.
  Future<String> updateLog(String month, String raw, {String? text, List<String>? tags, List<String>? projects, String? date}) async =>
      ((await _send('PUT', '/logs/${Uri.encodeComponent(month)}', {
        'raw': raw,
        if (text != null) 'text': text,
        if (tags != null) 'tags': tags,
        if (projects != null) 'projects': projects,
        if (date != null) 'date': date,
      }))['line'] as String?) ??
      raw;

  Future<void> deleteLog(String month, String raw) async {
    await _send('DELETE', '/logs/${Uri.encodeComponent(month)}', {'raw': raw});
  }

  Future<String> summary(String month) async =>
      ((await _get('/summaries/${Uri.encodeComponent(month)}'))['markdown'] as String?) ?? '';

  Future<List<Project>> projects() async {
    final j = await _get('/projects');
    final list = j['projects'] is List ? j['projects'] as List : const <Object?>[];
    return list.whereType<Json>().map(Project.fromJson).toList();
  }

  Future<Project> project(String slug) async =>
      Project.fromJson(await _get('/projects/${Uri.encodeComponent(slug)}'));

  Future<SearchResult> search(String query, {int topK = 10}) async =>
      SearchResult.fromJson(await _get('/search', {'q': query, 'topK': '$topK'}));

  Future<IndexStatus> indexStatus() async => IndexStatus.fromJson(await _get('/index'));

  // ── 질문 (answer from the top passages) ───────────────────────────────────
  Future<AskStatus> askStatus() async => AskStatus.fromJson(await _get('/ask'));

  /// Searches, then has the chosen agent answer from the passages. Takes tens of seconds; the server
  /// answers 409 (no agent / busy), 404 (no hits) or 502 (agent failed) as an [ApiException].
  /// Asks; with [conversationId] the question continues that conversation (the server keeps the turns).
  Future<AskResult> ask(String question, {int topK = 10, String? conversationId}) async =>
      AskResult.fromJson(await _send('POST', '/ask', {'q': question, 'topK': topK, if (conversationId != null) 'conversationId': conversationId}));

  Future<Conversation> conversation(String id) async => Conversation.fromJson(await _get('/ask/${Uri.encodeComponent(id)}'));

  Future<void> deleteConversation(String id) async {
    await _send('DELETE', '/ask/${Uri.encodeComponent(id)}');
  }

  /// A markdown file inside the worklog (the original behind a search hit).
  Future<WorklogFile> file(String path) async => WorklogFile.fromJson(await _get('/file', {'path': path}));

  static const _mutating = {'content-type': 'application/json', 'x-zaevis': '1'};

  Future<Json> _send(String method, String path, [Object? body]) async {
    final http.Response res;
    try {
      final req = http.Request(method, _uri(path))
        ..headers.addAll(_mutating)
        ..body = jsonEncode(body ?? const <String, dynamic>{});
      res = await http.Response.fromStream(await _client.send(req));
    } catch (_) {
      throw ApiException(0, '서버에 연결할 수 없습니다: $baseUrl');
    }
    return _decode(res);
  }

  Future<void> refreshIndex({bool force = false}) async {
    await _send('POST', '/index', {'force': force});
  }

  // ── input (real time) ────────────────────────────────────────────────────
  Future<String> addLog(String text, {List<String> tags = const [], List<String> projects = const []}) async =>
      ((await _send('POST', '/logs', {'text': text, 'tags': tags, 'projects': projects}))['line'] as String?) ?? '';

  Future<Inbox> inbox() async => Inbox.fromJson(await _get('/inbox'));

  Future<String> pasteTranscript(String name, String text) async =>
      ((await _send('POST', '/inbox/transcripts', {'name': name, 'text': text}))['file'] as String?) ?? name;

  /// Uploads a recording; the server queues it for whisperX. Pass [bytes] (web) or [stream] (desktop).
  Future<String> uploadAudio({required String name, required int size, List<int>? bytes, Stream<List<int>>? stream}) async {
    final req = http.StreamedRequest('POST', _uri('/inbox/audio', {'name': name}))
      ..headers['x-zaevis'] = '1'
      ..headers['content-type'] = 'application/octet-stream'
      ..contentLength = size;
    final http.Response res;
    try {
      final sending = _client.send(req);
      unawaited(sending.then((_) {}, onError: (Object _) {})); // errors are surfaced by the await below
      if (bytes != null) {
        req.sink.add(bytes);
      } else if (stream != null) {
        await req.sink.addStream(stream);
      }
      unawaited(req.sink.close()); // completes only once the body is read; don't block on it
      res = await http.Response.fromStream(await sending);
    } catch (_) {
      throw ApiException(0, '업로드에 실패했습니다: $baseUrl');
    }
    return (_decode(res)['file'] as String?) ?? name;
  }

  // ── data sources (batch) ─────────────────────────────────────────────────
  Future<SourcesState> sources() async => SourcesState.fromJson(await _get('/sources'));

  Future<void> setSourceEnabled(String name, bool enabled) async {
    await _send('PUT', '/sources/${Uri.encodeComponent(name)}', {'enabled': enabled});
  }

  Future<void> saveSourceSettings(String name, Map<String, Object?> settings) async {
    await _send('PUT', '/sources/${Uri.encodeComponent(name)}', {'settings': settings});
  }

  Future<void> addSource(String name, String command, {String? description}) async {
    await _send('POST', '/sources', {'name': name, 'command': command, if (description != null) 'description': description});
  }

  Future<void> removeSource(String name) async {
    await _send('DELETE', '/sources/${Uri.encodeComponent(name)}');
  }

  Future<void> collect({List<String>? only}) async {
    await _send('POST', '/collect', {if (only != null) 'sources': only});
  }

  // ── external AutoRAG datasources (Slack, Obsidian, GitHub …) ─────────────
  /// Templates with their probe (installed? archive?) and connection state. An older server answers
  /// 404, which reads as "none".
  Future<DatasourcesState> datasources() async {
    try {
      return DatasourcesState.fromJson(await _get('/datasources'));
    } on ApiException catch (e) {
      if (e.status == 404) return const DatasourcesState(datasources: [], syncing: false);
      rethrow;
    }
  }

  /// Creates or updates a connection; the server then syncs the external sources. Only env-var
  /// names go in [connector] — the server refuses token values (400 → [ApiException]).
  Future<void> saveDatasource(String name, {bool? enabled, String? description, Map<String, Object?>? connector, String? type, Map<String, String>? secrets}) async {
    await _send('PUT', '/datasources/${Uri.encodeComponent(name)}', {
      if (enabled != null) 'enabled': enabled,
      if (description != null) 'description': description,
      if (connector != null) 'connector': connector,
      if (type != null) 'type': type,
      // token values by env-var name; the server keeps them in secrets.json (0600) and never returns them
      if (secrets != null && secrets.isNotEmpty) 'secrets': secrets,
    });
  }

  Future<void> removeDatasource(String name) async {
    await _send('DELETE', '/datasources/${Uri.encodeComponent(name)}');
  }

  /// Syncs every enabled external connection (AutoRAG has no per-connection refresh). 409 while busy.
  Future<void> syncDatasources(String name) async {
    await _send('POST', '/datasources/${Uri.encodeComponent(name)}/sync', {});
  }

  // ── settings ─────────────────────────────────────────────────────────────
  /// Saves re-ranking settings; an empty [apiKey] removes the stored key. The key is never returned.
  Future<RerankStatus> updateRerank({bool? enabled, String? apiKey, String? model}) async => RerankStatus.fromJson(
        await _send('PUT', '/settings/rerank', {
          if (enabled != null) 'enabled': enabled,
          if (apiKey != null) 'apiKey': apiKey,
          if (model != null) 'model': model,
        }),
      );

  /// Asks the server to check a key with OpenRouter (the stored key when [apiKey] is null).
  Future<KeyCheck> testRerankKey([String? apiKey]) async =>
      KeyCheck.fromJson(await _send('POST', '/settings/rerank/test', {if (apiKey != null) 'apiKey': apiKey}));

  // ── weekly digest ────────────────────────────────────────────────────────
  Future<DigestStatus> digest() async => DigestStatus.fromJson(await _get('/digest'));

  Future<DigestStatus> updateDigest({String? agent, String? model, bool? weekly, bool? review}) async => DigestStatus.fromJson(
        await _send('PUT', '/digest', {
          if (agent != null) 'agent': agent,
          if (model != null) 'model': model,
          if (weekly != null) 'weekly': weekly,
          if (review != null) 'review': review,
        }),
      );

  // ── review of a digest run ───────────────────────────────────────────────
  /// Pending/applied/dismissed digest runs, newest first. An older server without the review flow
  /// answers 404, which reads as "none".
  Future<List<ProposalSummary>> proposals() async {
    final Json j;
    try {
      j = await _get('/digest/proposals');
    } on ApiException catch (e) {
      if (e.status == 404) return const [];
      rethrow;
    }
    final list = j['proposals'] is List ? j['proposals'] as List : const <Object?>[];
    return list.whereType<Json>().map(ProposalSummary.fromJson).toList();
  }

  Future<Proposal> proposal(String id) async => Proposal.fromJson(await _get('/digest/proposals/${Uri.encodeComponent(id)}'));

  /// Writes the chosen parts of a proposal into the worklog. Null selections mean "everything".
  Future<void> applyProposal(String id, {List<int>? lines, List<String>? projects, bool? summaries, bool? processed}) async {
    await _send('POST', '/digest/proposals/${Uri.encodeComponent(id)}', {
      'action': 'apply',
      if (lines != null) 'lines': lines,
      if (projects != null) 'projects': projects,
      if (summaries != null) 'summaries': summaries,
      if (processed != null) 'processed': processed,
    });
  }

  Future<void> dismissProposal(String id) async {
    await _send('POST', '/digest/proposals/${Uri.encodeComponent(id)}', {'action': 'dismiss'});
  }

  /// Starts a digest run; the server answers 409 (an [ApiException]) when nothing can run.
  Future<void> runDigest() async {
    await _send('POST', '/digest/run', {});
  }

  Future<AppSettings> settings() async => AppSettings.fromJson(await _get('/settings'));

  Future<AppSettings> updateSettings({String? dailyAt, bool? indexOnInject, bool? localEmbedding, bool? notifications, String? hotkey}) async =>
      AppSettings.fromJson(
        await _send('PUT', '/settings', {
          if (dailyAt != null) 'dailyAt': dailyAt,
          if (indexOnInject != null) 'indexOnInject': indexOnInject,
          if (localEmbedding != null) 'localEmbedding': localEmbedding,
          if (notifications != null) 'notifications': notifications,
          if (hotkey != null) 'hotkey': hotkey,
        }),
      );
}
