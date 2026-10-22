import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'models.dart';

/// Server address. Override at build time with
/// `--dart-define=WORKLOG_API=http://127.0.0.1:4710`.
const _definedBase = String.fromEnvironment('WORKLOG_API');
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
    if (res.statusCode == 404) throw ApiException(404, '찾을 수 없습니다');
    if (res.statusCode >= 400) throw ApiException(res.statusCode, '요청이 실패했습니다');
    final decoded = jsonDecode(body);
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

  Future<void> refreshIndex({bool force = false}) async {
    final http.Response res;
    try {
      res = await _client.post(
        _uri('/index'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'force': force}),
      );
    } catch (_) {
      throw ApiException(0, '서버에 연결할 수 없습니다: $baseUrl');
    }
    _decode(res);
  }
}
