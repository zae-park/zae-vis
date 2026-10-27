import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaevis/api.dart';
import 'package:zaevis/main.dart';
import 'package:zaevis/recording/recorder.dart';
import 'package:zaevis/screens/search_screen.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

final posted = <http.Request>[];
int indexPolls = 0;
String mockHotkey = '';
String? mockAskAgent = 'claude';

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
          case '/api/ask' when req.method == 'GET':
            return _json({
              'running': null, 'last': null, 'chosen': mockAskAgent,
              'setting': {'agent': 'auto', 'model': ''},
              'agents': [
                {'id': 'claude', 'title': 'Claude Code', 'available': mockAskAgent != null, 'detail': '2.1.304'},
                {'id': 'openrouter', 'title': 'OpenRouter API', 'available': false, 'detail': '키 없음'},
              ],
            });
          case '/api/ask' when req.method == 'POST':
            posted.add(req);
            if (mockAskAgent == null) return _json({'error': 'no_agent', 'message': '답을 쓸 에이전트가 없습니다. Claude Code·Codex·Gemini CLI 중 하나를 설치하세요.'}, 409);
            return _json({
              'q': (jsonDecode(req.body) as Map<String, dynamic>)['q'], 'agent': 'claude', 'ms': 12345,
              'answer': 'GA4 매핑은 캠페인 매핑이 빠져 막혔다 [1]. 수동으로 채우기로 정했다 [2].',
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
              'rerank': {'enabled': false, 'hasKey': false, 'keyHint': null, 'model': 'voyageai/rerank-3-lite', 'external': '없음 — 모든 검색은 이 맥 안에서 처리됩니다.'},
            });
          case '/api/digest' when req.method == 'GET':
            return _json({
              'running': false, 'nextWeekly': '2026-11-02', 'chosen': 'claude',
              'setting': {'agent': 'auto', 'model': '', 'weekly': true},
              'agents': [
                {'id': 'claude', 'title': 'Claude Code', 'available': true, 'detail': '2.1.304 (Claude Code)'},
                {'id': 'codex', 'title': 'Codex CLI', 'available': false, 'detail': '설치되지 않음'},
                {'id': 'gemini', 'title': 'Gemini CLI', 'available': false, 'detail': '설치되지 않음'},
                {'id': 'openrouter', 'title': 'OpenRouter API', 'available': false, 'detail': '키 없음'},
              ],
              'last': {'lastRun': '2026-10-26T12:00:00Z', 'agent': 'claude', 'ok': true, 'report': '로그 3줄 추가, inbox 1개 처리'},
            });
          case '/api/digest/run':
            posted.add(req);
            return _json({'started': true}, 202);
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
                : {'refreshing': false, 'lastRefresh': {'ok': true}, 'autorag': {'state': 'success', 'inFlight': false, 'stale': false, 'diagnostics': <Object>[]}});
          case '/api/sources' when req.method == 'POST':
            posted.add(req);
            return _json({'ok': true}, 201);
          case '/api/collect':
            posted.add(req);
            return _json({'started': true}, 202);
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

  testWidgets('질문 mode asks the server, shows the answer with [n] marks that jump to the source, and opens the file', (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    posted.clear();

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('질문'));
    await tester.pumpAndSettle();
    expect(find.text('검색한 문단만 근거로 답을 씁니다'), findsOneWidget);
    expect(find.textContaining('답은 Claude Code가 씁니다'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'GA4 매핑은 왜 막혔지?');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    final ask = posted.singleWhere((r) => r.url.path == '/api/ask');
    expect(jsonDecode(ask.body), {'q': 'GA4 매핑은 왜 막혔지?', 'topK': 10});
    expect(find.textContaining('캠페인 매핑이 빠져 막혔다'), findsOneWidget);
    expect(find.text('근거 2개'), findsOneWidget);
    expect(find.text('2026-10-09 · git 커밋 · roas · 박재'), findsOneWidget);
    expect(find.textContaining('Claude Code · 12.3초'), findsOneWidget);

    // the [2] mark scrolls to and outlines source 2
    await tester.tap(find.widgetWithText(InkWell, '2').first);
    await tester.pumpAndSettle();
    final card2 = tester.widget<Card>(find.ancestor(of: find.text('2026-10 · 한 줄 기록'), matching: find.byType(Card)).first);
    expect(card2.shape, isA<RoundedRectangleBorder>(), reason: 'focused source is outlined');

    await tester.tap(find.text('2026-10 · 한 줄 기록'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10.md'), findsOneWidget); // file screen title
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
    expect(find.text('설정 열기'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'x');
    await tester.testTextInput.receiveAction(TextInputAction.search);
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
    // Flutter test on macOS maps ⌘ to the meta key
    Future<void> cmd(LogicalKeyboardKey key, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    await cmd(LogicalKeyboardKey.digit2);
    expect(find.text('날짜순 한 줄 기록 — 내가 쓴 줄과 정리가 쓴 줄'), findsOneWidget, reason: 'log tab header');

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
    await tester.tap(find.text('로그').first);
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
    await tester.tap(find.text('로그').first);
    await tester.pumpAndSettle();

    expect(find.text('GA4 매핑 누락'), findsOneWidget);
    expect(find.text('MCP 연결 완료'), findsOneWidget);
    expect(find.textContaining('Claude 정리'), findsOneWidget);

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
    await tester.tap(find.text('수집').first);
    await tester.pumpAndSettle();

    expect(find.text('git 커밋'), findsOneWidget);
    expect(find.textContaining('커밋 3개'), findsOneWidget);
    expect(find.text('EXTENDED_HISTORY 필요'), findsOneWidget);
    expect(find.text('지금 수집'), findsOneWidget);
    expect(find.text('전사본 (1)'), findsOneWidget);
  });

  testWidgets('log tab FAB adds a line with tag and project', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    posted.clear();

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('로그').first);
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
    await tester.tap(find.text('로그').first);
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
    expect(find.text('⌘⇧J'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('저장')));
    await tester.pumpAndSettle();
    expect(jsonDecode(posted.last.body), {'hotkey': 'meta+shift+j'});
    expect(find.text('⌘⇧J'), findsOneWidget); // now listed under 단축키
  });

  testWidgets('index sheet shows the phase and file counts while refreshing, then completion', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    indexPolls = 0;

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
  });

  testWidgets('collect tab: a connector preset fills the form, adds the source and collects it once', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    posted.clear();

    await tester.pumpWidget(ZaevisApp(desktopIntegration: false, api: _fakeApi()));
    await tester.tap(find.text('수집').first);
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
}
