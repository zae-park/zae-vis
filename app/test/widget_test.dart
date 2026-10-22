import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:worklog_app/api.dart';
import 'package:worklog_app/main.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

WorklogApi _fakeApi() => WorklogApi(
      baseUrl: 'http://127.0.0.1:4710',
      client: MockClient((req) async {
        switch (req.url.path) {
          case '/api/logs':
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
                {'number': 1, 'title': 'ROAS 주간회의', 'path': 'processed/transcripts/2026-10-09_회의.txt', 'snippet': 'GA4 캠페인 매핑이 빠져서', 'score': 1.2},
              ],
            });
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

    await tester.pumpWidget(WorklogApp(api: _fakeApi()));
    await tester.enterText(find.byType(TextField), 'GA4 매핑');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('ROAS 주간회의'), findsOneWidget);
    expect(find.text('processed/transcripts/2026-10-09_회의.txt'), findsOneWidget);
  });

  testWidgets('log tab lists newest first and filters to my lines', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(WorklogApp(api: _fakeApi()));
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

    await tester.pumpWidget(WorklogApp(api: _fakeApi()));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });
}
