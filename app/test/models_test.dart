import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaevis/models.dart';
import 'package:zaevis/widgets/markdown_view.dart';

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

  test('SearchHit reads context and weak flag', () {
    final h = SearchHit.fromJson({
      'number': 1, 'title': 't', 'path': 'sources/git/2026-10-26.md', 'snippet': 's', 'score': 1, 'weak': false,
      'context': {'kind': 'git', 'sourceLabel': 'git 커밋', 'date': '2026-10-26', 'section': 'zaevis', 'author': '박재', 'matched': ['dmg']},
    });
    expect(h.context!.labels, ['2026-10-26', 'git 커밋', 'zaevis', '박재']);
    expect(h.context!.matched, ['dmg']);
    expect(h.weak, isFalse);
    final old = SearchHit.fromJson({'number': 2, 'title': 't', 'path': 'p', 'snippet': 's'});
    expect(old.context, isNull);
    expect(old.weak, isFalse);
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
    expect(s.embedding, isNull);

    final e = IndexStatus.fromJson({
      'refreshing': false,
      'autorag': {'state': 'success'},
      'embedding': {'enabled': true, 'state': 'ready', 'available': true, 'model': 'Qwen/Qwen3-Embedding-0.6B', 'device': 'metal'},
    }).embedding!;
    expect(e.state, 'ready');
    expect(e.label, contains('Qwen/Qwen3-Embedding-0.6B'));
    expect(EmbeddingStatus.fromJson({'enabled': false, 'state': 'off'}).label, contains('키워드'));
    expect(AppSettings.fromJson({'dailyAt': '18:30'}).localEmbedding, isTrue);
    expect(AppSettings.fromJson({'dailyAt': '18:30', 'localEmbedding': false}).localEmbedding, isFalse);
    final r = AppSettings.fromJson({'dailyAt': '18:30', 'rerank': {'enabled': true, 'hasKey': true, 'keyHint': '9999', 'model': 'm', 'external': 'OpenRouter'}}).rerank!;
    expect(r.active, isTrue);
    expect(r.keyHint, '9999');
    expect(AppSettings.fromJson({'dailyAt': '18:30'}).rerank, isNull);
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

  test('parseInline finds bold, italic, code, math, links and tags', () {
    final spans = parseInline('**굵게** *기울임* `x` \$E = mc^2\$ [[roas-multihorizon]] #done 끝');
    expect(spans.where((s) => s.kind != InlineKind.text).map((s) => s.kind).toList(),
        [InlineKind.bold, InlineKind.italic, InlineKind.code, InlineKind.math, InlineKind.link, InlineKind.tag]);
    expect(spans.firstWhere((s) => s.kind == InlineKind.link).text, 'roas-multihorizon');
    expect(spans.firstWhere((s) => s.kind == InlineKind.math).text, 'E = mc^2');
    // a lone asterisk inside a word is not italic, and a price is not math
    expect(parseInline('a*b and 5*3').every((s) => s.kind == InlineKind.text), isTrue);
    expect(parseInline(r'$5 and $7 later').any((s) => s.kind == InlineKind.math), isFalse);
    expect(parseInline(r'넓이 $\pi r^2$ 로').firstWhere((s) => s.kind == InlineKind.math).text, r'\pi r^2');
  });

  test('highlightSpans marks query terms case-insensitively', () {
    const mark = TextStyle(fontWeight: FontWeight.w700);
    final spans = highlightSpans('DMG 빌드와 dmg 서명', ['dmg'], mark);
    expect(spans.map((s) => s.text).toList(), ['DMG', ' 빌드와 ', 'dmg', ' 서명']);
    expect(spans[0].style?.fontWeight, FontWeight.w700);
    expect(spans[1].style?.fontWeight, isNull);
    expect(highlightSpans('그대로', const [], mark).single.text, '그대로');
  });
}
