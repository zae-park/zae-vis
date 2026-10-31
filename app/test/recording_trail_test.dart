import 'package:flutter_test/flutter_test.dart';
import 'package:zaevis/models.dart';
import 'package:zaevis/recording_trail.dart';

IndexStatus _index({bool refreshing = false, String? finishedAt}) => IndexStatus.fromJson({
      'refreshing': refreshing,
      if (finishedAt != null) 'lastRefresh': {'ok': true, 'finishedAt': finishedAt},
      'autorag': {'state': refreshing ? 'indexing' : 'success', 'inFlight': refreshing, 'stale': false, 'diagnostics': <Object>[]},
    });

Inbox _inbox({List<Object> jobs = const [], List<Object> transcripts = const [], List<Object> audio = const []}) => Inbox.fromJson({
      'jobs': jobs,
      'transcripts': transcripts,
      'sessions': <Object>[],
      'audio': audio,
    });

void main() {
  test('a running queue job and a saved transcript get different sentences', () {
    final trails = recordingTrails(
      inbox: _inbox(
        jobs: [
          {'file': 'a.wav', 'state': 'running', 'line': '음성 인식 40%'},
        ],
        transcripts: [
          {'name': 'note.txt', 'size': 10, 'modified': '2026-10-30T01:00:00Z'},
        ],
      ),
      index: _index(finishedAt: '2026-10-30T02:00:00Z'),
    );
    expect(trails.first.sentence, '인식 중 · 음성 인식 40%');
    expect(trails.first.watch, isTrue);
    expect(trails.last.sentence, contains('정리 대기'));
    expect(trails.last.openPath, 'inbox/transcripts/note.txt');
  });

  test('a collect progress line counts as recognition even without a queue job', () {
    final trails = recordingTrails(
      inbox: _inbox(),
      collectLine: '전사 1/1 · 2026-10-30_1424_녹음.wav · 음성 인식 42%',
    );
    expect(trails.single.file, '2026-10-30_1424_녹음.wav');
    expect(trails.single.sentence, '인식 중 · 음성 인식 42%');
    expect(trails.single.watch, isFalse);
  });

  test('a transcript newer than the index is still waiting to be searchable', () {
    final file = InboxFile(name: 'new.txt', size: 1, modified: DateTime.utc(2026, 10, 30, 3));
    expect(transcriptSentence(file, _index(finishedAt: '2026-10-30T02:00:00Z')), contains('다음 색인'));
    expect(transcriptSentence(file, _index(refreshing: true, finishedAt: '2026-10-30T04:00:00Z')), '색인 중 · 끝나면 검색됩니다');
  });

  test('empty search names the reason', () {
    final indexed = _index(finishedAt: '2026-10-30T02:00:00Z');
    final fresh = _inbox(transcripts: [
      {'name': '방금.txt', 'size': 1, 'modified': '2026-10-30T03:00:00Z'},
    ]);
    expect(emptySearchNote(query: '로제타', total: 4, shown: 0, filtered: true, index: indexed), contains('전체 4건'));
    expect(emptySearchNote(query: '로제타', total: 0, shown: 0, filtered: false, index: _index(refreshing: true)), contains('색인 중'));
    expect(emptySearchNote(query: '로제타', total: 0, shown: 0, filtered: false, index: indexed, inbox: fresh), contains('방금.txt'));
    expect(emptySearchNote(query: 'rosetta', total: 0, shown: 0, filtered: false, index: indexed, inbox: _inbox()), contains('한글로'));
    expect(recordingSentenceForPath('processed/transcripts/a.txt'), contains('출처 연결'));
  });
}