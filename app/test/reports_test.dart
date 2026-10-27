import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaevis/api.dart';
import 'package:zaevis/models.dart';
import 'package:zaevis/screens/reports_screen.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

final posted = <http.Request>[];
bool running = false;
int statusPolls = 0;
bool empty = false;
Map<String, dynamic> setting = {
  'daily': {'enabled': false, 'days': ['mon', 'tue', 'wed', 'thu', 'fri']},
  'weekly': {'enabled': false, 'day': 'mon'},
  'monthly': {'enabled': true, 'day': 1},
};
final daily = <Map<String, dynamic>>[
  {'kind': 'daily', 'period': '2026-10-26', 'path': 'reports/daily/2026-10-26.md', 'createdAt': '2026-10-26T10:00:00Z', 'agent': 'claude'},
  {'kind': 'daily', 'period': '2026-10-23', 'path': 'reports/daily/2026-10-23.md', 'createdAt': '2026-10-23T10:00:00Z', 'agent': 'claude'},
];

WorklogApi _fakeApi() => WorklogApi(
      baseUrl: 'http://127.0.0.1:4710',
      client: MockClient((req) async {
        final path = req.url.path;
        if (path == '/api/reports' && req.method == 'GET') {
          statusPolls++;
          return _json({
            'setting': setting,
            'running': running ? {'kind': 'daily', 'period': '2026-10-27', 'startedAt': '2026-10-27T06:00:00Z', 'agent': 'claude'} : null,
            'lastRun': {},
            'reports': empty
                ? {'daily': <Object>[], 'weekly': <Object>[], 'monthly': <Object>[]}
                : {
                    'daily': daily,
                    'weekly': <Object>[],
                    'monthly': [
                      {'kind': 'monthly', 'period': '2026-09', 'path': 'summaries/2026-09.md', 'createdAt': '2026-10-05T01:00:00Z', 'agent': null},
                    ],
                  },
            'defaults': {'daily': '2026-10-27', 'weekly': '2026-W43', 'monthly': '2026-09'},
          });
        }
        if (path.startsWith('/api/reports/') && req.method == 'GET') {
          final seg = path.split('/');
          final kind = seg[3];
          final period = seg[4];
          return _json({
            'kind': kind, 'period': period, 'path': kind == 'monthly' ? 'summaries/$period.md' : 'reports/$kind/$period.md',
            'createdAt': '2026-10-27T06:05:00Z', 'agent': kind == 'monthly' ? null : 'claude',
            'range': {'from': period, 'to': period, 'label': '$period (화)'},
            'markdown': kind == 'monthly' ? '# $period 작업 정리\n\n정리 초안\n' : '# $period 일간 리포트\n\n## 한 일\n- [[zaevis]] 리포트 화면 (근거: $period sources/git/$period.md)\n',
          });
        }
        if (path == '/api/reports/settings' && req.method == 'PUT') {
          posted.add(req);
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          for (final k in ['daily', 'weekly', 'monthly']) {
            if (b[k] is Map) setting[k] = {...setting[k] as Map, ...b[k] as Map};
          }
          return _json({'setting': setting, 'running': null, 'lastRun': {}, 'reports': {'daily': daily, 'weekly': <Object>[], 'monthly': <Object>[]}, 'defaults': {}});
        }
        if (path == '/api/reports/run' && req.method == 'POST') {
          posted.add(req);
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          running = true;
          return _json({'started': true, 'kind': b['kind'], 'period': b['period'] ?? '2026-10-27', 'agent': 'claude'}, 202);
        }
        return _json({'error': 'not_found'}, 404);
      }),
    );

Widget _app(WorklogApi api, {double width = 1200}) => MediaQuery(
      data: MediaQueryData(size: Size(width, 800)),
      child: MaterialApp(home: Scaffold(body: ReportsScreen(key: UniqueKey(), api: api, onOpenProject: (_) {}, clock: () => DateTime(2026, 10, 27, 15)))),
    );

void main() {
  setUp(() {
    posted.clear();
    running = false;
    statusPolls = 0;
    empty = false;
  });

  test('periods: ISO weeks and the "지금 만들기" choices', () {
    expect(isoWeekOf(DateTime(2026, 10, 27)), (year: 2026, week: 44));
    expect(isoWeekOf(DateTime(2025, 12, 29)), (year: 2026, week: 1));
    expect(isoWeekOf(DateTime(2027, 1, 3)), (year: 2026, week: 53));
    final c = {for (final x in ReportChoice.forNow(DateTime(2026, 11, 2, 9))) x.label: '${x.kind} ${x.period}'};
    expect(c, {
      '오늘': 'daily 2026-11-02', '어제': 'daily 2026-11-01', '이번 주': 'weekly 2026-W45', '지난주': 'weekly 2026-W44', '이번 달': 'monthly 2026-11', '지난달': 'monthly 2026-10',
    });
    expect(const ReportSettings(dailyDays: ['sun', 'sat']).dailyPreset, 'weekend');
    expect(const ReportSettings(dailyDays: ['mon', 'sat']).dailyPreset, isNull);
  });

  testWidgets('reports: kinds, the period list, the report body; "지금 만들기 → 오늘" starts a run and polls until it is done', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_fakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('2026-10-26'), findsOneWidget);
    expect(find.text('2026-10-23'), findsOneWidget);
    expect(find.text('2026-10-26 일간 리포트'), findsOneWidget);
    expect(find.textContaining('리포트 화면'), findsOneWidget);

    await tester.tap(find.text('2026-10-23'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-23 일간 리포트'), findsOneWidget);

    await tester.tap(find.text('월간'));
    await tester.pumpAndSettle();
    expect(find.text('2026-09 작업 정리'), findsOneWidget);
    expect(find.text('정리 초안'), findsOneWidget);

    await tester.tap(find.text('주간'));
    await tester.pumpAndSettle();
    expect(find.textContaining('아직 주간 리포트가 없습니다'), findsOneWidget);

    await tester.tap(find.text('지금 만들기'));
    await tester.pumpAndSettle();
    expect(find.text('지난주'), findsOneWidget);
    expect(find.text('주간 · 2026-W43'), findsOneWidget);
    await tester.tap(find.text('오늘'));
    await tester.pump(); // the progress bar animates forever: no pumpAndSettle while a run is on
    await tester.pump(const Duration(milliseconds: 300));
    final run = posted.singleWhere((r) => r.url.path == '/api/reports/run');
    expect(jsonDecode(run.body), {'kind': 'daily', 'period': '2026-10-27'});
    expect(find.textContaining('일간 리포트 2026-10-27 만드는 중'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // the poll sees the run finish: the new report is selected
    daily.insert(0, {'kind': 'daily', 'period': '2026-10-27', 'path': 'reports/daily/2026-10-27.md', 'createdAt': '2026-10-27T06:05:00Z', 'agent': 'claude'});
    addTearDown(() => daily.removeAt(0));
    final before = statusPolls;
    running = false;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(statusPolls, greaterThan(before));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('2026-10-27 일간 리포트'), findsOneWidget);
  });

  testWidgets('reports: the settings panel saves the weekend preset, a single day, the weekly day and the monthly switch', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_fakeApi()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('리포트 설정'));
    await tester.pumpAndSettle();
    expect(find.text('일간 리포트'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '주말'));
    await tester.pumpAndSettle();
    expect(jsonDecode(posted.last.body), {'daily': {'days': ['sat', 'sun']}});

    await tester.tap(find.widgetWithText(FilterChip, '월'));
    await tester.pumpAndSettle();
    expect(jsonDecode(posted.last.body), {'daily': {'days': ['sat', 'sun', 'mon']}});

    await tester.tap(find.widgetWithText(SwitchListTile, '일간 리포트'));
    await tester.pumpAndSettle();
    expect(jsonDecode(posted.last.body), {'daily': {'enabled': true}});

    await tester.tap(find.text('월요일'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('금요일').last);
    await tester.pumpAndSettle();
    expect(jsonDecode(posted.last.body), {'weekly': {'day': 'fri'}});

    await tester.tap(find.widgetWithText(SwitchListTile, '월간 리포트'));
    await tester.pumpAndSettle();
    expect(jsonDecode(posted.last.body), {'monthly': {'enabled': false}});
    expect(posted.every((r) => r.method == 'PUT' && r.url.path == '/api/reports/settings'), isTrue);
  });

  testWidgets('reports: nothing yet shows the empty pane; a narrow window picks the period from a dropdown', (tester) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    empty = true;
    await tester.pumpWidget(_app(_fakeApi(), width: 600));
    await tester.pumpAndSettle();
    expect(find.textContaining('아직 일간 리포트가 없습니다'), findsOneWidget);
    expect(find.textContaining('지금 만들기'), findsWidgets);

    empty = false;
    await tester.pumpWidget(_app(_fakeApi(), width: 600));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.byType(ListTile), findsNothing, reason: 'no side list when narrow');
    expect(find.text('2026-10-26 일간 리포트'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-10-23').last);
    await tester.pumpAndSettle();
    expect(find.text('2026-10-23 일간 리포트'), findsOneWidget);
  });
}
