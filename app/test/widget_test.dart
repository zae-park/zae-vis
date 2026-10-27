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

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

final posted = <http.Request>[];

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
          case '/api/file':
            return _json({'path': req.url.queryParameters['path'], 'markdown': '# git · 2026-10-09\n\n## roas\n\n- GA4 캠페인 매핑이 빠져서 — 박재'});
          case '/api/sources':
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
              'dailyAt': '18:30', 'indexOnInject': false, 'worklogDir': '/w', 'whisperx': false, 'localEmbedding': true,
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
}
