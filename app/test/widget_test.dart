import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaevis/api.dart';
import 'package:zaevis/main.dart';

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
          case '/api/logs/2026-10':
            return _json({
              'month': '2026-10',
              'entries': [
                {'date': '10-06', 'projects': ['databricks-poc'], 'tags': ['done'], 'text': 'MCP 연결 완료', 'source': null, 'author': 'me'},
                {'date': '10-08', 'projects': ['roas'], 'tags': ['blocked'], 'text': 'GA4 매핑 누락', 'source': '2026-10-09_회의', 'author': 'claude'},
              ],
            });
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
          case '/api/projects':
            return _json({'projects': [{'slug': 'roas', 'title': 'ROAS', 'status': '', 'repos': <Object>[], 'currentState': ''}]});
          case '/api/logs' when req.method == 'POST':
            posted.add(req);
            return _json({'month': '2026-10', 'line': '- 10-23 #done x'}, 201);
          default:
            return _json({'error': 'not_found'}, 404);
        }
      }),
    );

void main() {
  testWidgets('search shows numbered hits', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZaevisApp(api: _fakeApi()));
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

    await tester.pumpWidget(ZaevisApp(api: _fakeApi()));
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();

    expect(find.text('의미 검색 (로컬 임베딩)'), findsOneWidget);
    expect(find.text('검색 결과 재정렬 (OpenRouter)'), findsOneWidget);
    expect(find.textContaining('지금 외부로 나가는 요청: 없음'), findsOneWidget);
    expect(find.text('키 삭제'), findsNothing);
    // nothing to save yet: the save button stays disabled until a key is typed
    final save = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '저장'));
    expect(save.onPressed, isNull);
  });

  testWidgets('log tab lists newest first and filters to my lines', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZaevisApp(api: _fakeApi()));
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

    await tester.pumpWidget(ZaevisApp(api: _fakeApi()));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('collect tab shows sources with status and the inbox', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZaevisApp(api: _fakeApi()));
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

    await tester.pumpWidget(ZaevisApp(api: _fakeApi()));
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
