import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaevis/api.dart';
import 'package:zaevis/backend/backend.dart';
import 'package:zaevis/main.dart';
import 'package:zaevis/recording/recorder.dart';
import 'package:zaevis/screens/onboarding_screen.dart';
import 'package:zaevis/screens/search_screen.dart';
import 'package:zaevis/shortcuts.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

final posted = <http.Request>[];
int indexPolls = 0;
String mockHotkey = '';
bool mockObsidianConfigured = false;
String? mockAskAgent = 'claude';
List<Object>? mockAskRail;
List<Object>? mockAskStatusRail;
List<Object>? mockDigestRail;
bool mockKiwiInstalled = false;

/// `tokenizer` as GET /settings and GET /index report it (see server/src/kiwi.ts).
Map<String, Object?> _tokenizer() => {
      'active': 'whitespace',
      'needsReindex': mockKiwiInstalled,
      'kiwi': mockKiwiInstalled
          ? {'installed': true, 'library': '/s/ext/kiwi/lib/libkiwi.dylib', 'model': '/s/ext/kiwi/models/cong/base', 'source': 'zaevis', 'version': '0.24.1', 'asset': 'kiwi_mac_arm64_v0.24.1.tgz', 'downloadMb': 129}
          : {'installed': false, 'library': null, 'model': null, 'source': null, 'version': null, 'asset': 'kiwi_mac_arm64_v0.24.1.tgz', 'downloadMb': 129},
    };

/// Records every `zaevis …` the app asks the bundled backend to run.
class _FakeBackend implements Backend {
  _FakeBackend({this.configured = true});
  final bool configured;
  final ran = <List<String>>[];
  List<List<String>> get runs => ran;
  @override
  bool get managed => true;
  @override
  String? get problem => null;
  @override
  String get home => '/Users/me';
  @override
  bool get isConfigured => configured;
  @override
  Stream<String> run(List<String> args) {
    ran.add(args);
    if (args.join(' ') == 'ext install kiwi') {
      mockKiwiInstalled = true;
      return Stream.fromIterable(['› Kiwi 0.24.1 내려받는 중 (129 MB)', '✓ Kiwi 0.24.1 설치 완료']);
    }
    return Stream.fromIterable(['✓ ${args.first}']);
  }

  @override
  Future<void> ensureServer() async {}
  @override
  Future<void> open(String target) async {}
}

WorklogApi _fakeApi() => WorklogApi(
      baseUrl: 'http://127.0.0.1:4710',
      client: MockClient((req) async {
        switch (req.url.path) {
          case '/api/logs' when req.method == 'GET':
            return _json({'months': ['2026-10']});
          case '/api/logs/2026-10' when req.method == 'GET':
            return _json({
              'month': '2026-10',
              'entries': [
                {'date': '10-06', 'projects': ['databricks-poc'], 'tags': ['done'], 'text': 'MCP 연결 완료', 'source': null, 'author': 'me', 'raw': '- 10-06 [[databricks-poc]] #done MCP 연결 완료'},
                {'date': '10-08', 'projects': ['roas'], 'tags': ['blocked'], 'text': 'GA4 매핑 누락', 'source': '2026-10-09_회의', 'author': 'claude', 'raw': '- 10-08 [[roas]] #blocked GA4 매핑 누락 (src: 2026-10-09_회의)'},
              ],
            });
          case '/api/logs/2026-10' when req.method == 'PUT' || req.method == 'DELETE':
            posted.add(req);
            return _json(req.method == 'PUT' ? {'line': '- 10-08 [[roas]] #done 고친 줄 (src: 2026-10-09_회의)'} : {'ok': true});
          case '/api/search':
            return _json({
              'ok': true,
              'query': req.url.queryParameters['q'],
              'hits': [
                {
                  'number': 1, 'title': 'ROAS 주간회의', 'path': 'sources/git/2026-10-09.md', 'snippet': 'GA4 캠페인 매핑이 빠져서', 'score': 1.0, 'weak': false,
                  'context': {'kind': 'git', 'sourceLabel': 'git 커밋', 'date': '2026-10-09', 'section': 'roas', 'author': '박재', 'matched': ['ga4', '매핑']},
                },
                {'number': 2, 'title': 'x', 'path': 'log/2026-10.md', 'snippet': '무관한 줄', 'score': 0.05, 'weak': true,
                  'context': {'kind': 'log', 'sourceLabel': '한 줄 기록', 'date': '2026-10', 'matched': <Object>[]}},
              ],
            });
          case '/api/ask/20261027-120000' when req.method == 'GET':
            return _json({
              'id': '20261027-120000', 'title': '예전 대화', 'createdAt': '2026-10-27T03:00:00Z', 'updatedAt': '2026-10-27T03:00:00Z',
              'turns': [
                {'q': '예전 질문', 'answer': '예전 답 [1]', 'agent': 'claude', 'ms': 1000, 'conversationId': '20261027-120000', 'turn': 0,
                  'sources': [{'n': 1, 'path': 'log/2026-10.md', 'label': '2026-10 · 한 줄 기록', 'passage': '옛 발췌'}]},
              ],
            });
          case '/api/ask/20261027-120000' when req.method == 'DELETE':
            posted.add(req);
            return _json({'ok': true});
          case '/api/ask' when req.method == 'GET':
            return _json({
              'running': null, 'last': null, 'chosen': mockAskAgent,
              if (mockAskStatusRail != null) 'rail': mockAskStatusRail,
              'conversations': [{'id': '20261027-120000', 'title': '예전 대화', 'updatedAt': '2026-10-27T03:00:00Z', 'turns': 1}],
              'setting': {'agent': 'auto', 'model': ''},
              'agents': [
                {'id': 'claude', 'title': 'Claude Code', 'available': mockAskAgent != null, 'detail': '2.1.304', 'loggedIn': mockAskAgent != null ? true : null},
                {'id': 'codex', 'title': 'Codex CLI', 'available': true, 'detail': 'codex-cli 0.9.0', 'loggedIn': false, 'loginHint': '터미널에서 codex login'},
                {'id': 'openrouter', 'title': 'OpenRouter API', 'available': false, 'detail': '키 없음'},
              ],
            });
          case '/api/ask' when req.method == 'POST':
            posted.add(req);
            if (mockAskAgent == null) return _json({'error': 'no_agent', 'message': '답을 쓸 에이전트가 없습니다. Claude Code·Codex·Gemini CLI 중 하나를 설치하세요.'}, 409);
            final askBody = jsonDecode(req.body) as Map<String, dynamic>;
            return _json({
              'q': askBody['q'], 'agent': 'claude', 'ms': 12345,
              'conversationId': askBody['conversationId'] ?? '20261027-120000', 'turn': askBody['conversationId'] == null ? 0 : 1,
              'answer': 'GA4 매핑은 캠페인 매핑이 빠져 막혔다 [1]. 수동으로 채우기로 정했다 [2].',
              if (mockAskRail != null) 'rail': mockAskRail,
              'sources': [
                {'n': 1, 'path': 'sources/git/2026-10-09.md', 'label': '2026-10-09 · git 커밋 · roas · 박재', 'passage': 'GA4 캠페인 매핑이 빠져서'},
                {'n': 2, 'path': 'log/2026-10.md', 'label': '2026-10 · 한 줄 기록', 'passage': '매핑 테이블을 수동으로 채우기로'},
              ],
            });
          case '/api/file':
            return _json({'path': req.url.queryParameters['path'], 'markdown': '# git · 2026-10-09\n\n## roas\n\n- GA4 캠페인 매핑이 빠져서 — 박재'});
          case '/api/sources' when req.method == 'GET':
            return _json({
              'collecting': false,
              'sources': [
                {'name': 'git', 'title': 'git 커밋', 'description': 'd', 'builtin': true, 'enabled': true, 'settings': {'reposRoot': '~/jaepark'}, 'options': [{'key': 'reposRoot', 'label': '저장소 상위 폴더', 'kind': 'path'}], 'lastRun': '2026-10-23T09:00:00Z', 'lastOk': true, 'lastNote': '커밋 3개'},
                {'name': 'shell-history', 'title': '셸 명령 이력', 'description': 'd', 'builtin': true, 'enabled': true, 'settings': {}, 'options': [], 'lastOk': false, 'lastError': 'EXTENDED_HISTORY 필요'},
              ],
            });
          case '/api/inbox':
            return _json({
              'transcripts': [{'name': '2026-10-23_회의.txt', 'size': 2048, 'modified': '2026-10-23T09:00:00Z'}],
              'sessions': <Object>[],
              'audio': <Object>[],
              'jobs': <Object>[],
            });
          case '/api/settings' when req.method == 'GET':
            return _json({
              'dailyAt': '18:30', 'indexOnInject': false, 'worklogDir': '/w', 'whisperx': false, 'localEmbedding': true, 'hotkey': mockHotkey,
              'schedule': {'supported': true, 'installed': true, 'loaded': true},
              'tokenizer': _tokenizer(),
              'rerank': {'enabled': false, 'hasKey': false, 'keyHint': null, 'model': 'voyageai/rerank-3-lite', 'external': '없음 — 모든 검색은 이 맥 안에서 처리됩니다.'},
            });
          case '/api/digest' when req.method == 'GET':
            return _json({
              'running': false, 'nextWeekly': '2026-11-02', 'chosen': 'claude',
              if (mockDigestRail != null) 'rail': mockDigestRail,
              'setting': {'agent': 'auto', 'model': '', 'weekly': true},
              'agents': [
                {'id': 'claude', 'title': 'Claude Code', 'available': true, 'detail': '2.1.304 (Claude Code)', 'loggedIn': true, 'loginHint': '터미널에서 claude login'},
                {'id': 'codex', 'title': 'Codex CLI', 'available': true, 'detail': 'codex-cli 0.9.0', 'loggedIn': false, 'loginHint': '터미널에서 codex login'},
                {'id': 'gemini', 'title': 'Gemini CLI', 'available': false, 'detail': '설치되지 않음'},
                {'id': 'openrouter', 'title': 'OpenRouter API', 'available': false, 'detail': '키 없음'},
              ],
              'last': {
                'lastRun': '2026-10-26T12:00:00Z', 'agent': 'claude', 'ok': true, 'report': '로그 3줄 추가, inbox 1개 처리',
                if (mockDigestRail != null) 'rail': mockDigestRail,
              },
            });
          case '/api/digest/run':
            posted.add(req);
            return _json({'started': true}, 202);
          case '/api/origins':
            return _json({
              'files': [
                {'path': 'sources/git/2026-10-09.md', 'source': 'git', 'kind': 'source', 'date': '2026-10-09', 'name': '2026-10-09.md', 'bytes': 2048},
                {'path': 'processed/transcripts/2026-10-09_회의.txt', 'source': 'transcripts', 'kind': 'processed', 'date': '2026-10-09', 'name': '2026-10-09_회의.txt', 'bytes': 4096},
                {'path': 'sources/agent-sessions/2026-10-08.md', 'source': 'agent-sessions', 'kind': 'source', 'date': '2026-10-08', 'name': '2026-10-08.md', 'bytes': 1024},
              ],
            });
          case '/api/origin':
            return _json({'src': req.url.queryParameters['src'], 'paths': ['processed/transcripts/2026-10-09_회의.txt']});
          case '/api/projects':
            return _json({'projects': [{'slug': 'roas', 'title': 'ROAS', 'status': '', 'repos': <Object>[], 'currentState': ''}]});
          case '/api/inbox/audio':
            posted.add(req);
            return _json({'file': req.url.queryParameters['name']}, 201);
          case '/api/logs' when req.method == 'POST':
            posted.add(req);
            return _json({'month': '2026-10', 'line': '- 10-23 #done x'}, 201);
          case '/api/digest/proposals':
            return _json({
              'proposals': [
                {'id': '20261027-100000', 'createdAt': '2026-10-27T01:00:00Z', 'agent': 'claude', 'status': 'pending', 'lines': 2, 'projects': 1, 'summaries': 0, 'processed': 1},
              ],
            });
          case '/api/digest/proposals/20261027-100000' when req.method == 'GET':
            return _json({
              'id': '20261027-100000', 'createdAt': '2026-10-27T01:00:00Z', 'agent': 'claude', 'status': 'pending', 'report': '로그 2줄',
              'logLines': [
                {'month': '2026-10', 'line': '- 10-26 [[roas]] #done 채점 분리 (src: s1)', 'entry': {'date': '10-26', 'projects': ['roas'], 'tags': ['done'], 'text': '채점 분리', 'source': 's1', 'author': 'claude', 'raw': ''}},
                {'month': '2026-10', 'line': '- 10-27 #learned 토큰 상한', 'entry': {'date': '10-27', 'projects': <Object>[], 'tags': ['learned'], 'text': '토큰 상한', 'source': null, 'author': 'claude', 'raw': ''}},
              ],
              'removedLines': <Object>[],
              'projects': [{'slug': 'roas', 'before': '# ROAS\n\n옛 상태', 'after': '# ROAS\n\n새 상태'}],
              'summaries': <Object>[],
              'processed': [{'from': 'inbox/transcripts/a.txt', 'to': 'processed/transcripts/a.txt'}],
            });
          case '/api/digest/proposals/20261027-100000' when req.method == 'POST':
            posted.add(req);
            return _json({'ok': true, 'applied': {'lines': 1}});
          case '/api/settings' when req.method == 'PUT':
            posted.add(req);
            mockHotkey = (jsonDecode(req.body) as Map<String, dynamic>)['hotkey'] as String? ?? mockHotkey;
            return _json({
              'dailyAt': '18:30', 'indexOnInject': false, 'worklogDir': '/w', 'whisperx': false, 'localEmbedding': true,
              'notifications': false, 'hotkey': 'meta+shift+j',
              'schedule': {'supported': true, 'installed': true, 'loaded': true},
            });
          case '/api/index' when req.method == 'GET':
            indexPolls++;
            return _json(indexPolls == 1
                ? {
                    'refreshing': true,
                    'autorag': {'state': 'indexing', 'inFlight': true, 'stale': true, 'diagnostics': <Object>[],
                      'progress': {'phase': 'parsed', 'sourceFiles': {'total': 40}, 'parsedCounts': {'scanned': 20, 'written': 3, 'deleted': 0, 'skipped': 0}}},
                  }
                : {
                    'refreshing': false, 'lastRefresh': {'ok': true},
                    'autorag': {'state': 'success', 'inFlight': false, 'stale': false, 'diagnostics': [
                      {'code': 'lexical-tokenizer-unavailable', 'severity': 'warning', 'message': 'The "multilingual" BM25 tokenizer needs the Kiwi native library and model, which were not found'},
                    ]},
                    'tokenizer': _tokenizer(),
                  });
          case '/api/index' when req.method == 'POST':
            posted.add(req);
            return _json({'refreshing': true}, 202);
          case '/api/sources' when req.method == 'POST':
            posted.add(req);
            return _json({'ok': true}, 201);
          case '/api/sources/shell-history/enable-timestamps':
            posted.add(req);
            return _json({'ok': true, 'file': '/h/.zshrc', 'changed': true});
          case '/api/collect':
            posted.add(req);
            return _json({'started': true}, 202);
          case '/api/datasources' when req.method == 'GET':
            return _json({
              'syncing': false,
              'datasources': [
                {
                  'name': 'obsidian', 'template': 'obsidian', 'title': 'Obsidian 볼트', 'description': '볼트의 노트를 색인합니다.',
                  'fields': [{'key': 'vaultPath', 'label': '볼트 폴더', 'kind': 'path', 'required': true, 'placeholder': '/Users/me/Vault'}],
                  'cli': null, 'external': '없음', 'probe': {'installed': null, 'binPath': null, 'archive': null, 'env': <Object>[], 'unavailable': null},
                  'configured': mockObsidianConfigured, 'enabled': true, 'note': null, 'connector': mockObsidianConfigured ? {'vaultPath': '/tmp/vault'} : <String, Object>{},
                  'channels': null, 'autorag': mockObsidianConfigured ? {'datasourceId': 'obsidian', 'status': 'active'} : null,
                  'sync': mockObsidianConfigured ? {'lastSync': '2026-10-27T05:48:02Z', 'ok': true, 'chunks': 2} : null,
                },
                {
                  'name': 'slack', 'template': 'slack', 'title': 'Slack', 'description': 'slacrawl 아카이브를 검색합니다.',
                  'fields': [{'key': 'workspace', 'label': '워크스페이스(팀) ID', 'kind': 'text', 'required': true}],
                  'cli': {'bin': 'slacrawl', 'install': 'npm install -g slacrawl', 'homepage': 'https://github.com/openclaw/slacrawl'},
                  'external': null, 'probe': {'installed': false, 'binPath': null, 'archive': false, 'env': <Object>[], 'unavailable': null},
                  'configured': false, 'enabled': false, 'note': null, 'connector': <String, Object>{}, 'channels': null, 'autorag': null, 'sync': null,
                },
                {
                  'name': 'github', 'template': 'github', 'title': 'GitHub 이슈·PR', 'description': 'REST API로 이슈·PR을 가져옵니다.',
                  'fields': [
                    {'key': 'repos', 'label': '저장소', 'kind': 'list', 'required': true},
                    {'key': 'tokenEnv', 'label': '토큰 환경 변수 이름', 'kind': 'env', 'defaultValue': 'GITHUB_TOKEN'},
                  ],
                  'cli': null, 'external': 'api.github.com에 요청', 'probe': {'installed': null, 'binPath': null, 'archive': null, 'env': [{'name': 'GITHUB_TOKEN', 'set': false}], 'unavailable': null},
                  'configured': false, 'enabled': false, 'note': null, 'connector': <String, Object>{}, 'channels': null, 'autorag': null, 'sync': null,
                },
              ],
            });
          case '/api/datasources/obsidian' || '/api/datasources/github' when req.method == 'PUT' || req.method == 'DELETE':
            posted.add(req);
            if (req.method == 'PUT') mockObsidianConfigured = true;
            return _json({'ok': true, 'syncing': true});
          case '/api/datasources/obsidian/sync':
            posted.add(req);
            return _json({'syncing': true}, 202);
          default:
            return _json({'error': 'not_found'}, 404);
        }
      }),
    );

/// Emits two PCM chunks, then waits to be stopped.
class _FakeRecorder implements Recorder {
  bool permission = true;
  bool stopped = false;
  final _ctrl = StreamController<Uint8List>();

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<Stream<Uint8List>> startStream({int sampleRate = kSampleRate}) async {
    _ctrl.add(Uint8List.fromList([1, 0, 2, 0]));
    _ctrl.add(Uint8List.fromList([3, 0]));
    return _ctrl.stream;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    await _ctrl.close();
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('search shows numbered hits', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.enterText(find.byType(TextField), 'GA4 매핑');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('2026-10-09'), findsOneWidget);
    expect(find.text('git 커밋'), findsOneWidget);
    expect(find.text('roas'), findsOneWidget);
    expect(find.text('박재'), findsOneWidget);
    expect(find.text('약한 일치'), findsOneWidget);
    expect(find.text('sources/git/2026-10-09.md'), findsOneWidget);

    await tester.tap(find.text('git 커밋'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-09.md'), findsOneWidget); // file screen title
    expect(find.textContaining('GA4 캠페인 매핑이 빠져서 — 박재'), findsWidgets);
  });

  testWidgets('질문 mode is a conversation: bubbles, a follow-up carries the conversation id, [n] opens the source panel and the file', (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    posted.clear();

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('질문'));
    await tester.pumpAndSettle();
    expect(find.text('검색한 문단만 근거로 답을 씁니다'), findsOneWidget);
    expect(find.textContaining('답은 Claude Code가 씁니다'), findsOneWidget);
    expect(find.text('새 대화'), findsWidgets); // header title + button

    await tester.enterText(find.byType(TextField), 'GA4 매핑은 왜 막혔지?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    var asks = posted.where((r) => r.url.path == '/api/ask').toList();
    expect(jsonDecode(asks.single.body), {'q': 'GA4 매핑은 왜 막혔지?', 'topK': 10});
    expect(find.text('GA4 매핑은 왜 막혔지?'), findsWidgets); // question bubble (and the header title)
    expect(find.textContaining('캠페인 매핑이 빠져 막혔다'), findsOneWidget);
    expect(find.text('2026-10-09 · git 커밋 · roas · 박재'), findsOneWidget); // source chip
    expect(find.textContaining('Claude Code · 12.3초'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget, reason: 'the composer stays at the bottom');

    // hover a [2] mark: the tooltip previews the passage
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.widgetWithText(InkWell, '2').first));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.textContaining('[2] 2026-10 · 한 줄 기록'), findsOneWidget);
    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();

    // tapping it opens the side panel (wide layout) with the full passage and a way to the file
    await tester.tap(find.widgetWithText(InkWell, '2').first);
    await tester.pumpAndSettle();
    expect(find.text('근거 2 / 2'), findsOneWidget);
    expect(find.text('매핑 테이블을 수동으로 채우기로'), findsOneWidget);
    await tester.tap(find.byTooltip('이전 근거'));
    await tester.pumpAndSettle();
    expect(find.text('근거 1 / 2'), findsOneWidget);
    await tester.tap(find.text('원문 열기'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-09.md'), findsOneWidget); // file screen title
    await tester.pageBack();
    await tester.pumpAndSettle();

    // a follow-up stays in the same conversation
    await tester.enterText(find.byType(TextField), '그건 왜?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    asks = posted.where((r) => r.url.path == '/api/ask').toList();
    expect(jsonDecode(asks.last.body), {'q': '그건 왜?', 'topK': 10, 'conversationId': '20261027-120000'});
    expect(find.text('그건 왜?'), findsOneWidget);
    expect(find.textContaining('캠페인 매핑이 빠져 막혔다'), findsNWidgets(2));

    // 새 대화 clears the thread; 이전 대화 brings one back
    await tester.tap(find.byIcon(Icons.add_comment_outlined)); // the 새 대화 button (TextButton.icon is not a TextButton)
    await tester.pumpAndSettle();
    expect(find.text('그건 왜?'), findsNothing);
    await tester.tap(find.byTooltip('이전 대화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('예전 대화'));
    await tester.pumpAndSettle();
    expect(find.text('예전 질문'), findsWidgets);
    expect(find.textContaining('예전 답'), findsOneWidget);
    await tester.tap(find.byTooltip('이 대화 지우기'));
    await tester.pumpAndSettle();
    expect(posted.last.method, 'DELETE');
    expect(find.text('예전 질문'), findsNothing);
  });

  testWidgets('질문 mode on a narrow window opens the source as a bottom sheet', (tester) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('질문'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'GA4?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InkWell, '1').first);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('근거 1 / 2'), findsOneWidget);
    expect(find.text('GA4 캠페인 매핑이 빠져서'), findsOneWidget);
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('질문 rail names the quota skip and who wrote', (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    mockAskStatusRail = [
      {'id': 'claude', 'title': 'Claude Code', 'state': 'ready'},
      {'id': 'codex', 'title': 'Codex CLI', 'state': 'ready'},
      {'id': 'openrouter', 'title': 'OpenRouter API', 'state': 'ready', 'metered': true},
    ];
    mockAskRail = [
      {'id': 'claude', 'title': 'Claude Code', 'state': 'quota', 'reason': 'You have hit your usage limit'},
      {'id': 'codex', 'title': 'Codex CLI', 'state': 'wrote'},
      {'id': 'openrouter', 'title': 'OpenRouter API', 'state': 'ready', 'metered': true},
    ];
    addTearDown(() {
      mockAskRail = null;
      mockAskStatusRail = null;
    });

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('질문'));
    await tester.pumpAndSettle();
    expect(find.text('서비스 순서'), findsOneWidget);
    expect(find.text('OpenRouter API · 사용량'), findsOneWidget);
    expect(find.text('Claude Code · 할당량'), findsNothing);

    await tester.enterText(find.byType(TextField), '누가 썼지?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.text('Claude Code · 할당량'), findsOneWidget);
    expect(find.text('Codex CLI · 작성'), findsOneWidget);
    expect(find.textContaining('Claude Code 할당량 → Codex CLI가 작성 · 12.3초'), findsOneWidget);
  });

  testWidgets('설정 정리 shows the rail and names a quota skip on the last run', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    mockDigestRail = [
      {'id': 'claude', 'title': 'Claude Code', 'state': 'quota', 'reason': 'You have hit your usage limit'},
      {'id': 'codex', 'title': 'Codex CLI', 'state': 'wrote'},
    ];
    addTearDown(() => mockDigestRail = null);

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('지금 정리하기'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('서비스 순서'), findsOneWidget);
    expect(find.text('Claude Code · 할당량'), findsOneWidget);
    expect(find.text('Codex CLI · 작성'), findsOneWidget);
    expect(find.textContaining('Claude Code 할당량으로 건너뜀'), findsOneWidget);
  });

  testWidgets('질문 mode without an agent explains and offers the settings', (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    mockAskAgent = null;
    addTearDown(() => mockAskAgent = 'claude');

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('질문'));
    await tester.pumpAndSettle();
    expect(find.textContaining('답을 쓸 에이전트가 없습니다'), findsOneWidget);
    expect(find.text('Codex CLI: 로그인 필요: 터미널에서 codex login'), findsOneWidget);
    expect(find.text('설정 열기'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'x');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.textContaining('Claude Code·Codex·Gemini CLI 중 하나를 설치하세요'), findsOneWidget);
    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();
    expect(find.text('정리 (지식화)'), findsOneWidget); // settings opened
  });

  testWidgets('settings shows the OpenRouter re-ranking section, off and local by default', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();

    expect(find.text('의미 검색 (로컬 임베딩)'), findsOneWidget);
    expect(find.text('검색 결과 재정렬 (OpenRouter)'), findsOneWidget);
    expect(find.textContaining('지금 외부로 나가는 요청: 없음'), findsOneWidget);
    expect(find.text('키 삭제'), findsNothing);

    // the digest section lists detected agents, marks the one that will run, shows the last report
    await tester.scrollUntilVisible(find.text('지금 정리하기'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Claude Code'), findsOneWidget);
    expect(find.text('Codex CLI'), findsOneWidget);
    expect(find.text('사용'), findsOneWidget);
    // an installed but signed-out CLI says what to do
    expect(find.textContaining('로그인 필요: 터미널에서 codex login'), findsOneWidget);
    expect(find.textContaining('로그 3줄 추가'), findsOneWidget);
    await tester.ensureVisible(find.text('지금 정리하기'));
    await tester.pumpAndSettle();
    // FilledButton.icon builds a private subclass, so match by predicate rather than exact type
    await tester.tap(find.ancestor(of: find.text('지금 정리하기'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
    await tester.pumpAndSettle();
    expect(posted.where((r) => r.url.path == '/api/digest/run').length, 1);
    // nothing to save yet: the save button stays disabled until a key is typed
    final save = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '저장'));
    expect(save.onPressed, isNull);
  });

  testWidgets('record button records, stops, and uploads a WAV to the inbox', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    posted.clear();
    final rec = _FakeRecorder();

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi(), recorder: rec));
    await tester.tap(find.byTooltip('녹음'));
    await tester.pumpAndSettle();
    expect(find.text('눌러서 녹음 시작'), findsOneWidget);

    await tester.tap(find.text('녹음 시작'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('중지하고 올리기'), findsOneWidget);

    await tester.tap(find.text('중지하고 올리기'));
    await tester.pumpAndSettle();
    expect(rec.stopped, isTrue);
    final up = posted.singleWhere((r) => r.url.path == '/api/inbox/audio');
    expect(up.url.queryParameters['name'], endsWith('_녹음.wav'));
    expect(up.bodyBytes.length, 44 + 6); // WAV header + 3 samples
    expect(find.textContaining('전사 대기열에 넣었습니다'), findsOneWidget);
  });

  testWidgets('record button explains a denied microphone', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rec = _FakeRecorder()..permission = false;

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi(), recorder: rec));
    await tester.tap(find.byTooltip('녹음'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('녹음 시작'));
    await tester.pumpAndSettle();
    expect(find.textContaining('마이크 접근이 허용되지 않았습니다'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('눌러서 녹음 시작'), findsNothing, reason: 'dialog closed');
  });

  testWidgets('keyboard shortcuts: ⌘2 switches tab, ⌘K returns to search and focuses it, ⌘N opens 한 줄 기록', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.pumpAndSettle();
    // In-app chords are ⌘ on macOS and Ctrl elsewhere (AppShortcuts.mod).
    final mod = AppShortcuts.nativeMenu ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
    Future<void> cmd(LogicalKeyboardKey key, {bool shift = false}) async {
      await tester.sendKeyDownEvent(mod);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(mod);
      await tester.pumpAndSettle();
    }

    await cmd(LogicalKeyboardKey.digit2);
    expect(find.text('기록 · 하루 · 프로젝트 상태 · 수집된 원본 — 이 앱이 아는 것 전부'), findsOneWidget, reason: 'memory tab header');

    await cmd(LogicalKeyboardKey.keyK);
    expect(find.text('기록 전체를 뜻과 단어로 찾습니다'), findsOneWidget, reason: 'back on search');
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.focusNode?.hasFocus, isTrue, reason: 'search field focused');

    await cmd(LogicalKeyboardKey.keyN);
    expect(find.text('한 줄 기록'), findsWidgets);
    expect(find.text('무엇을 했고, 왜 그렇게 했는지'), findsOneWidget, reason: 'the add-log dialog is open');
  });

  testWidgets('log line menu edits a line (PUT with its raw text) and deletes one after confirming', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    posted.clear();

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('메모리').first);
    await tester.pumpAndSettle();

    // newest first: the 10-08 line (written by the digest) is on top
    await tester.tap(find.byTooltip('줄 메뉴').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('편집'));
    await tester.pumpAndSettle();
    expect(find.text('줄 편집'), findsOneWidget);
    expect(find.textContaining('출처(2026-10-09_회의)는 그대로'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'GA4 매핑 누락'), '고친 줄');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    final put = posted.singleWhere((r) => r.method == 'PUT');
    final body = jsonDecode(utf8.decode(put.bodyBytes)) as Map<String, dynamic>;
    expect(body['raw'], '- 10-08 [[roas]] #blocked GA4 매핑 누락 (src: 2026-10-09_회의)');
    expect(body['text'], '고친 줄');
    expect(body['date'], '10-08');
    expect(find.text('줄을 고쳤습니다'), findsOneWidget);

    await tester.tap(find.byTooltip('줄 메뉴').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();
    expect(find.text('이 줄을 지울까요?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '지우기'));
    await tester.pumpAndSettle();
    final del = posted.singleWhere((r) => r.method == 'DELETE');
    expect((jsonDecode(utf8.decode(del.bodyBytes)) as Map<String, dynamic>)['raw'], contains('GA4 매핑 누락'));
  });

  testWidgets('log tab lists newest first and filters to my lines', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('메모리').first);
    await tester.pumpAndSettle();

    expect(find.text('GA4 매핑 누락'), findsOneWidget);
    expect(find.text('MCP 연결 완료'), findsOneWidget);
    expect(find.textContaining('출처 2026-10-09_회의'), findsOneWidget); // the digest's line links to its origin
    expect(find.text('내 기록'), findsOneWidget);
    expect(find.text('정리'), findsOneWidget);

    await tester.tap(find.text('내가 쓴 줄만'));
    await tester.pumpAndSettle();
    expect(find.text('GA4 매핑 누락'), findsNothing);
    expect(find.text('MCP 연결 완료'), findsOneWidget);
  });

  testWidgets('narrow layout uses a bottom navigation bar', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('collect tab shows sources with status and the inbox', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('연결').first);
    await tester.pumpAndSettle();

    expect(find.text('git 커밋'), findsOneWidget);
    expect(find.textContaining('커밋 3개'), findsOneWidget);
    expect(find.text('EXTENDED_HISTORY 필요'), findsOneWidget);
    expect(find.text('지금 수집'), findsOneWidget);
    expect(find.text('전사본 (1)'), findsOneWidget);
  });

  testWidgets('collect tab: the shell-history card turns zsh timestamps on after confirming', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    posted.clear();

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('연결').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('셸 명령 이력'));
    await tester.pumpAndSettle();
    expect(find.text('시각 기록 켜기'), findsOneWidget);
    expect(find.text('git 커밋'), findsOneWidget);

    // cancel: nothing is sent
    await tester.tap(find.text('시각 기록 켜기'));
    await tester.pumpAndSettle();
    expect(find.text('셸 설정에 한 줄 추가'), findsOneWidget);
    expect(find.textContaining('setopt EXTENDED_HISTORY  # zaevis'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(posted, isEmpty);

    // confirm: one POST, and the card says when it takes effect
    await tester.tap(find.text('시각 기록 켜기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();
    expect(posted.map((r) => '${r.method} ${r.url.path}').toList(), ['POST /api/sources/shell-history/enable-timestamps']);
    expect(find.text('/h/.zshrc에 추가했습니다. 새 터미널부터 모입니다.'), findsWidgets);
  });

  testWidgets('onboarding: sources match today\'s connectors; after setup it lists what to do next and opens the app', (tester) async {
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    posted.clear();
    addTearDown(() => mockKiwiInstalled = false);
    final backend = _FakeBackend();
    var done = false;

    await tester.pumpWidget(MaterialApp(home: OnboardingScreen(backend: backend, api: _fakeApi(), onDone: () => done = true)));
    await tester.pumpAndSettle();
    expect(find.text('에이전트 세션'), findsOneWidget);
    expect(find.text('Claude Code 세션'), findsNothing);
    expect(find.textContaining('근거를 달아 묻고(질문)'), findsOneWidget);

    await tester.tap(find.text('터미널 명령 이력'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작'));
    await tester.pumpAndSettle();

    expect(backend.runs.first, containsAllInOrder(['setup', '--yes', '--disable', 'shell-history']));
    expect(backend.runs.first, isNot(contains('claude-code')));
    expect(posted.map((r) => r.url.path).toList(), ['/api/collect']);
    expect(find.text('준비됐습니다'), findsOneWidget);
    expect(find.text('다음에 할 것'), findsOneWidget);
    expect(find.text('연결 탭에서 소스 확인'), findsOneWidget);
    expect(find.text('메모리 탭에서 기록'), findsOneWidget);
    expect(find.text('리포트 켜기'), findsOneWidget);
    expect(find.text('시작'), findsNothing);
    expect(done, isFalse);
    await tester.tap(find.text('앱 열기'));
    expect(done, isTrue);
  });

  testWidgets('log tab FAB adds a line with tag and project', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    posted.clear();

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('메모리').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('한 줄 기록'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'README 정리');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('결정')));
    await tester.tap(find.widgetWithText(ActionChip, 'roas'));
    await tester.pump();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('저장')));
    await tester.pumpAndSettle();

    expect(posted, hasLength(1));
    final body = jsonDecode(posted.single.body) as Map<String, dynamic>;
    expect(body['text'], 'README 정리');
    expect(body['tags'], ['decision']);
    expect(body['projects'], ['roas']);
    expect(posted.single.headers['x-zaevis'], '1');
  });

  testWidgets('log tab shows the pending proposal; the review screen applies only the chosen lines', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    posted.clear();

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('메모리').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('정리 제안 1건이 검토를 기다립니다'), findsOneWidget);

    await tester.tap(find.text('검토하기'));
    await tester.pumpAndSettle();
    expect(find.text('정리 결과 검토'), findsOneWidget);
    expect(find.text('채점 분리'), findsOneWidget);
    expect(find.text('토큰 상한'), findsOneWidget);
    expect(find.text('로그 줄 (2/2)'), findsOneWidget);
    expect(find.text('새 상태'), findsNothing); // project diff is collapsed until expanded

    // drop the second line, keep the project and the inbox move
    await tester.tap(find.text('토큰 상한'));
    await tester.pump();
    expect(find.text('로그 줄 (1/2)'), findsOneWidget);
    expect(find.text('선택 3개'), findsOneWidget);

    await tester.tap(find.text('선택한 것 적용'));
    await tester.pumpAndSettle();
    final body = jsonDecode(posted.single.body) as Map<String, dynamic>;
    expect(body['action'], 'apply');
    expect(body['lines'], [0]);
    expect(body.containsKey('projects'), isFalse); // all projects = omitted
    expect(body['summaries'], isTrue);
    expect(body['processed'], isTrue);
    expect(find.text('정리 결과 검토'), findsNothing); // back on the log
  });

  testWidgets('search filters hits by source kind', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.enterText(find.byType(TextField), 'GA4 매핑');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('2건'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'git 커밋 1'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, '한 줄 기록 1'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2건'), findsOneWidget);
    expect(find.text('무관한 줄'), findsOneWidget);
    expect(find.text('GA4 캠페인 매핑이 빠져서'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, '한 줄 기록 1')); // kind filter off again
    SearchScreen.clock = () => DateTime(2026, 10, 27);
    addTearDown(() => SearchScreen.clock = DateTime.now);
    await tester.tap(find.widgetWithText(ChoiceChip, '7일')); // 10-09 is out; the 2026-10 month file counts by its last day
    await tester.pumpAndSettle();
    expect(find.text('1 / 2건'), findsOneWidget);
    expect(find.text('무관한 줄'), findsOneWidget);
    expect(find.text('GA4 캠페인 매핑이 빠져서'), findsNothing);
  });

  testWidgets('settings: notification switch saves; the hotkey dialog records ⌘⇧J', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    posted.clear();
    mockHotkey = '';

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();

    // the page's ListView, not the server-address TextField's own Scrollable
    final scrollable = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    // a non-lazy ListView already holds every child, so scroll until the tile is actually hit-testable
    await tester.dragUntilVisible(find.text('시스템 알림').hitTestable(), scrollable, const Offset(0, -250));
    await tester.tap(find.text('시스템 알림'));
    await tester.pumpAndSettle();
    expect(jsonDecode(posted.single.body), {'notifications': false});

    await tester.dragUntilVisible(find.text('바꾸기').last.hitTestable(), scrollable, const Offset(0, -250));
    await tester.tap(find.text('바꾸기').last);
    await tester.pumpAndSettle();
    expect(find.text('전역 단축키 바꾸기'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    expect(find.text(HotkeySpec.label('meta+shift+j')), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('저장')));
    await tester.pumpAndSettle();
    expect(jsonDecode(posted.last.body), {'hotkey': 'meta+shift+j'});
    expect(find.text(HotkeySpec.label('meta+shift+j')), findsOneWidget); // now listed under 단축키
  });

  testWidgets('index sheet shows the phase and file counts while refreshing, then completion', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    indexPolls = 0;
    mockKiwiInstalled = false;

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('색인'));
    // not pumpAndSettle: the spinner in the button animates until the 2s poll fires
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('본문 읽는 중 20/40 파일'), findsOneWidget);
    expect(find.textContaining('30%'), findsOneWidget); // 0.6 × 20/40
    expect(find.text('색인 중…'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(0.3, 0.001));

    await tester.pump(const Duration(seconds: 2)); // poll → finished
    await tester.pumpAndSettle();
    expect(find.text('색인 완료'), findsOneWidget);
    expect(find.text('색인 갱신'), findsOneWidget);
    // the Kiwi warning is a Korean row with the terminal hint (no bundle on the web), never AutoRAG's English message
    expect(find.text('키워드 분석'), findsOneWidget);
    expect(find.textContaining('공백 기준 — 조사·어미가 붙은 말(인증서를)'), findsOneWidget);
    expect(find.textContaining("zaevis ext install kiwi"), findsOneWidget);
    expect(find.textContaining('needs the Kiwi native library'), findsNothing);
    expect(find.text('Kiwi 설치'), findsNothing);
  });

  testWidgets('index sheet in the packaged app offers the Kiwi install button, which runs ext install kiwi', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    indexPolls = 5; // past the "refreshing" first answer
    mockKiwiInstalled = false;
    final backend = _FakeBackend();

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi(), backend: backend));
    await tester.pumpAndSettle();
    await tester.tap(find.text('색인'));
    await tester.pumpAndSettle();
    expect(find.textContaining('공백 기준'), findsOneWidget);
    await tester.tap(find.text('Kiwi 설치'));
    await tester.pumpAndSettle();
    expect(backend.ran, anyElement(equals(['ext', 'install', 'kiwi'])));
    expect(find.textContaining('Kiwi 0.24.1 설치 완료'), findsOneWidget);
    await tester.tap(find.text('완료 · 닫기'));
    await tester.pumpAndSettle();
    // installed now, but the index was built without it: the row says to rebuild
    expect(find.textContaining('Kiwi 설치됨 — 처음부터 다시 색인하면'), findsOneWidget);
    expect(find.text('Kiwi 설치'), findsNothing);
  });

  testWidgets('settings: the Kiwi tile installs through the bundle and then offers the rebuild from scratch', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    mockKiwiInstalled = false;
    posted.clear();
    final backend = _FakeBackend();

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi(), backend: backend));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(ListTile, '한국어 형태소 분석 (Kiwi)');
    await tester.dragUntilVisible(tile, find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(find.textContaining('129MB 다운로드'), findsOneWidget);
    await tester.tap(find.descendant(of: tile, matching: find.text('설치')));
    await tester.pumpAndSettle();
    expect(backend.ran, anyElement(equals(['ext', 'install', 'kiwi'])));
    await tester.tap(find.text('완료 · 닫기'));
    await tester.pumpAndSettle();
    expect(find.text('처음부터 다시 색인할까요?'), findsOneWidget);
    await tester.tap(find.text('다시 색인'));
    await tester.pumpAndSettle();
    final rebuild = posted.where((r) => r.url.path == '/api/index' && r.method == 'POST').toList();
    expect(rebuild.length, 1);
    expect(jsonDecode(rebuild.single.body), {'force': true});
    expect(find.textContaining('Kiwi 설치됨 — 처음부터 다시 색인하면'), findsOneWidget, reason: 'the tile reloads with the server\'s new status');
  });

  testWidgets('onboarding installs Kiwi before the first collect when the box is ticked', (tester) async {
    tester.view.physicalSize = const Size(1000, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    mockKiwiInstalled = false;
    posted.clear();
    final backend = _FakeBackend(configured: false);

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi(), backend: backend));
    await tester.pumpAndSettle();
    expect(find.text('한국어 형태소 분석 (Kiwi) 설치'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, '한국어 형태소 분석 (Kiwi) 설치')).value, isTrue);
    await tester.tap(find.text('시작'));
    await tester.pumpAndSettle();
    expect(backend.ran.first.first, 'setup');
    expect(backend.ran[1], ['ext', 'install', 'kiwi'], reason: 'before the server and the first collect, so the first index already uses Kiwi');
    expect(posted.where((r) => r.url.path == '/api/collect').length, 1);
  });

  testWidgets('collect tab: a connector preset fills the form, adds the source and collects it once', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    posted.clear();

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('연결').first);
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(find.text('커넥터 추가').hitTestable(), find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first, const Offset(0, -250));
    await tester.tap(find.text('커넥터 추가'));
    await tester.pumpAndSettle();

    expect(find.text('추가하고 수집'), findsOneWidget);
    await tester.tap(find.text('폴더의 노트 (Markdown·텍스트)'));
    await tester.pumpAndSettle();
    expect(find.text('notes'), findsOneWidget); // name filled from the preset
    expect(find.textContaining('{fromDate}'), findsWidgets);

    await tester.tap(find.text('추가하고 수집'));
    await tester.pumpAndSettle();
    expect(posted.map((r) => r.url.path).toList(), ['/api/sources', '/api/collect']);
    final added = jsonDecode(posted.first.body) as Map<String, dynamic>;
    expect(added['name'], 'notes');
    expect(added['command'], contains('-newermt {fromDate}'));
    expect(jsonDecode(posted.last.body), {'sources': ['notes']});
  });

  testWidgets('collect tab: external sources show install hints, and connecting Obsidian sends the vault path', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    posted.clear();
    mockObsidianConfigured = false;

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('연결').first);
    await tester.pumpAndSettle();
    final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    await tester.dragUntilVisible(find.text('외부 소스 (AutoRAG)').hitTestable(), list, const Offset(0, -250));
    await tester.pumpAndSettle();

    // not installed → the card says so and offers the install command
    expect(find.text('미설치 — slacrawl 명령이 없습니다'), findsOneWidget);
    await tester.dragUntilVisible(find.text('Slack').hitTestable(), list, const Offset(0, -250));
    await tester.tap(find.text('Slack'));
    await tester.pumpAndSettle();
    expect(find.text('npm install -g slacrawl'), findsOneWidget);
    expect(find.text('설치 명령 복사'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '연결'), findsNothing, reason: 'no connect form without the CLI');

    // connect Obsidian
    await tester.dragUntilVisible(find.text('Obsidian 볼트').hitTestable(), list, const Offset(0, -250));
    await tester.tap(find.text('Obsidian 볼트'));
    await tester.pumpAndSettle();
    expect(find.text('연결 안 됨'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '볼트 폴더 *'), '/tmp/vault');
    await tester.dragUntilVisible(find.widgetWithText(FilledButton, '연결').hitTestable(), list, const Offset(0, -250));
    await tester.tap(find.widgetWithText(FilledButton, '연결'));
    await tester.pumpAndSettle();

    final put = posted.singleWhere((r) => r.url.path == '/api/datasources/obsidian');
    expect(put.method, 'PUT');
    expect(jsonDecode(put.body), {'enabled': true, 'connector': {'vaultPath': '/tmp/vault'}, 'description': ''});
    // after the reload the card is connected with its sync record
    expect(find.textContaining('연결됨 · 동기화'), findsOneWidget);
    expect(find.textContaining('조각 2개'), findsOneWidget);
  });

  testWidgets('collect tab: a connected external source can be synced, toggled off and removed', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    posted.clear();
    mockObsidianConfigured = true;

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('연결').first);
    await tester.pumpAndSettle();
    final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    await tester.dragUntilVisible(find.text('Obsidian 볼트').hitTestable(), list, const Offset(0, -250));
    await tester.tap(find.text('Obsidian 볼트'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '볼트 폴더 *'), findsOneWidget);
    expect(tester.widget<TextField>(find.widgetWithText(TextField, '볼트 폴더 *')).controller!.text, '/tmp/vault');

    await tester.dragUntilVisible(find.text('지금 동기화').hitTestable(), list, const Offset(0, -250));
    await tester.tap(find.text('지금 동기화'));
    await tester.pumpAndSettle();
    expect(posted.last.url.path, '/api/datasources/obsidian/sync');

    // the GitHub card asks for the token value separately; it goes out as `secrets` under the env name
    await tester.dragUntilVisible(find.text('GitHub 이슈·PR').hitTestable(), list, const Offset(0, -250));
    await tester.tap(find.text('GitHub 이슈·PR'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.widgetWithText(TextField, '토큰 환경 변수 이름')).controller!.text, 'GITHUB_TOKEN');
    final tokenField = find.widgetWithText(TextField, '토큰 값 (GITHUB_TOKEN)');
    expect(tokenField, findsOneWidget);
    expect(tester.widget<TextField>(tokenField).obscureText, isTrue);
    await tester.enterText(find.widgetWithText(TextField, '저장소 *'), 'zae-park/zaevis');
    await tester.enterText(tokenField, 'ghp_secret');
    await tester.dragUntilVisible(find.widgetWithText(FilledButton, '연결').hitTestable(), list, const Offset(0, -250));
    await tester.tap(find.widgetWithText(FilledButton, '연결'));
    await tester.pumpAndSettle();
    final gh = posted.lastWhere((r) => r.url.path == '/api/datasources/github');
    final ghBody = jsonDecode(gh.body) as Map<String, dynamic>;
    expect(ghBody['secrets'], {'GITHUB_TOKEN': 'ghp_secret'});
    expect(ghBody['connector']['tokenEnv'], 'GITHUB_TOKEN');
    expect(jsonEncode(ghBody['connector']), isNot(contains('ghp_secret')));

    await tester.dragUntilVisible(find.text('연결 삭제').hitTestable(), list, const Offset(0, -250));
    await tester.tap(find.text('연결 삭제'));
    await tester.pumpAndSettle();
    expect(posted.last.method, 'DELETE');
    expect(posted.last.url.path, '/api/datasources/obsidian');
  });

  testWidgets('메모리 tab: 원본 layer lists collected files by day with citation counts; a line\'s 출처 opens its origin', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('메모리').first);
    await tester.pumpAndSettle();
    expect(find.text('프로젝트 상태'), findsOneWidget); // side panel on a wide window
    expect(find.text('ROAS'), findsOneWidget);
    expect(find.textContaining('정리 에이전트는 고치지 못하고'), findsOneWidget); // flow strip

    // 출처 on the digest's line → its transcript
    await tester.tap(find.textContaining('출처 2026-10-09_회의'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-09_회의.txt'), findsOneWidget); // file screen title
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('하루'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-06'), findsOneWidget);
    expect(find.text('MCP 연결 완료'), findsOneWidget);
    expect(find.textContaining('내가 쓴 줄만 있습니다'), findsOneWidget);
    expect(find.text('2026-10-09'), findsOneWidget);
    expect(find.textContaining('수집한 원본에서 쓴 줄이 그 파일과 같은 하루에 있습니다'), findsOneWidget);
    expect(find.textContaining('1일은 원본에서 줄로 이어졌습니다'), findsOneWidget);
    expect(find.text('git 커밋'), findsOneWidget);
    expect(find.text('GA4 매핑 누락'), findsWidgets);

    await tester.tap(find.text('원본'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-09'), findsOneWidget);
    expect(find.text('기록 1줄의 근거'), findsOneWidget); // the transcript is cited by one line
    expect(find.text('아직 정리 안 됨'), findsOneWidget); // 2026-10-08 agent sessions, cited by nothing
    expect(find.text('3개 파일 · 2일'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'git 커밋'));
    await tester.pumpAndSettle();
    expect(find.text('1개 파일 · 1일'), findsOneWidget);
  });
}
