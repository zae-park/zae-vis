import 'package:flutter_test/flutter_test.dart';
import 'package:worklog_app/models.dart';
import 'package:worklog_app/widgets/markdown_view.dart';

void main() {
  test('LogEntry.fromJson', () {
    final e = LogEntry.fromJson({
      'date': '10-08',
      'projects': ['roas'],
      'tags': ['done'],
      'text': '분리 채점',
      'source': 'git roas a1b2c3d',
      'author': 'claude',
    });
    expect(e.byClaude, isTrue);
    expect(e.projects, ['roas']);
    expect(e.source, 'git roas a1b2c3d');
  });

  test('SearchResult error and hits', () {
    final err = SearchResult.fromJson({
      'ok': false,
      'hits': <Object>[],
      'error': {'code': 'index-not-ready', 'message': 'refresh'},
    });
    expect(err.needsRefresh, isTrue);

    final ok = SearchResult.fromJson({
      'ok': true,
      'hits': [
        {'number': 1, 'title': 'T', 'path': 'log/2026-10.md', 'snippet': 's', 'score': 0.5},
      ],
    });
    expect(ok.hits.single.score, 0.5);
  });

  test('IndexStatus reads diagnostics and refresh errors', () {
    final s = IndexStatus.fromJson({
      'refreshing': false,
      'lastRefresh': {'ok': false, 'error': 'boom'},
      'autorag': {
        'state': 'failed',
        'stale': true,
        'diagnostics': [
          {'message': 'embedding unavailable'},
        ],
      },
    });
    expect(s.lastError, 'boom');
    expect(s.messages, ['embedding unavailable']);
    expect(s.stale, isTrue);
  });

  test('parseBlocks handles headings, lists, tasks and code', () {
    final blocks = parseBlocks('# T\n\n## 현재 상태\n문장 하나\n이어짐\n\n- a\n  - b\n- [x] done\n1. one\n```\ncode\n```\n');
    expect(blocks.map((b) => b.kind).toList(), [
      BlockKind.heading,
      BlockKind.heading,
      BlockKind.paragraph,
      BlockKind.bullet,
      BlockKind.bullet,
      BlockKind.task,
      BlockKind.numbered,
      BlockKind.code,
    ]);
    expect(blocks[2].text, '문장 하나 이어짐');
    expect(blocks[4].level, 1);
    expect(blocks[5].checked, isTrue);
  });

  test('parseInline finds bold, code, links and tags', () {
    final spans = parseInline('**굵게** `x` [[roas-multihorizon]] #done 끝');
    expect(spans.where((s) => s.kind != InlineKind.text).map((s) => s.kind).toList(),
        [InlineKind.bold, InlineKind.code, InlineKind.link, InlineKind.tag]);
    expect(spans.firstWhere((s) => s.kind == InlineKind.link).text, 'roas-multihorizon');
  });
}
