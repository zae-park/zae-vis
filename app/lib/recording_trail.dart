import 'models.dart';

/// Where one recording is on the way from the microphone to a memory citation.
enum RecordingStage { queued, running, failed, saved, indexing, searchable, waitingDigest, linked }

class RecordingTrail {
  const RecordingTrail({required this.file, required this.sentence, required this.stage, this.openPath, this.watch = false});
  final String file;
  final String sentence;
  final RecordingStage stage;

  /// Worklog path to open, when the text already exists.
  final String? openPath;

  /// The queue is still on this audio file, so the record floater can watch it.
  final bool watch;
}

/// Newest recordings that are not yet a cited source. At most [limit].
///
/// A collect line like `전사 1/1 · note.wav · 음성 인식 42%` counts as recognition in progress
/// even when that pass is not a queue job.
List<RecordingTrail> recordingTrails({
  required Inbox inbox,
  IndexStatus? index,
  String? collectLine,
  int limit = 3,
}) {
  final items = <RecordingTrail>[];
  final covered = <String>{};

  final live = _collectFile(collectLine);
  if (live != null) {
    covered.add(live.$1);
    items.add(RecordingTrail(
      file: live.$1,
      sentence: live.$2 == null || live.$2!.isEmpty ? '인식 중' : '인식 중 · ${live.$2}',
      stage: RecordingStage.running,
    ));
  }

  for (final job in inbox.jobs) {
    if (covered.contains(job.file)) continue;
    if (job.state == 'queued' || job.state == 'running') {
      covered.add(job.file);
      items.add(RecordingTrail(
        file: job.file,
        sentence: job.state == 'queued' ? '대기 · 곧 전사를 시작합니다' : '인식 중 · ${job.line ?? '전사 중'}',
        stage: job.state == 'queued' ? RecordingStage.queued : RecordingStage.running,
        watch: true,
      ));
    } else if (job.state == 'failed' && inbox.audio.any((a) => a.name == job.file)) {
      covered.add(job.file);
      items.add(RecordingTrail(
        file: job.file,
        sentence: '전사 실패 · ${job.error ?? '다시 시도할 수 있습니다'}',
        stage: RecordingStage.failed,
      ));
    }
  }

  for (final audio in inbox.audio) {
    if (covered.contains(audio.name)) continue;
    covered.add(audio.name);
    items.add(RecordingTrail(file: audio.name, sentence: '대기 · 다음 수집에서 전사됩니다', stage: RecordingStage.queued));
  }

  for (final transcript in inbox.transcripts) {
    final path = 'inbox/transcripts/${transcript.name}';
    items.add(RecordingTrail(
      file: transcript.name,
      sentence: transcriptSentence(transcript, index),
      stage: transcriptStage(transcript, index),
      openPath: path,
    ));
  }

  items.sort((a, b) {
    final byStage = _rank(a.stage).compareTo(_rank(b.stage));
    if (byStage != 0) return byStage;
    return a.file.compareTo(b.file);
  });
  if (items.length <= limit) return items;
  return items.sublist(0, limit);
}

/// One line for a file screen. Processed transcripts already went through review.
String? recordingSentenceForPath(String path, {Inbox? inbox, IndexStatus? index}) {
  if (path.contains('processed/transcripts/')) return '출처 연결 · 정리에 반영된 전사입니다.';
  if (!path.contains('inbox/transcripts/')) return null;
  final name = path.split('/').last;
  final file = inbox?.transcripts.where((t) => t.name == name);
  final match = file == null || file.isEmpty ? null : file.first;
  if (match == null) return transcriptSentence(InboxFile(name: name, size: 0), index);
  return transcriptSentence(match, index);
}

RecordingStage transcriptStage(InboxFile file, IndexStatus? index) {
  if (index?.refreshing == true) return RecordingStage.indexing;
  final at = index?.finishedAt;
  final modified = file.modified;
  if (at != null && modified != null && !modified.isAfter(at)) return RecordingStage.waitingDigest;
  return RecordingStage.saved;
}

String transcriptSentence(InboxFile file, IndexStatus? index) {
  return switch (transcriptStage(file, index)) {
    RecordingStage.indexing => '색인 중 · 끝나면 검색됩니다',
    RecordingStage.waitingDigest => '검색 가능 · 정리 대기. 주간 정리 뒤에 메모리 출처가 됩니다',
    _ => '글 저장 · 다음 색인에 들어갑니다',
  };
}

/// Why a search with no visible hits is empty. [hidden] is how many of [total] the filters removed.
String emptySearchNote({
  required String query,
  required int total,
  required int shown,
  required bool filtered,
  IndexStatus? index,
  Inbox? inbox,
}) {
  if (total > 0 && shown == 0 && filtered) {
    return '전체 $total건 중 이 기간·출처에는 없습니다.';
  }
  if (index?.refreshing == true) return '색인 중입니다. 끝나면 다시 찾습니다.';
  final pending = _pendingTranscripts(inbox, index);
  if (pending.isNotEmpty) {
    final names = pending.take(3).map((f) => f.name).join(', ');
    final more = pending.length > 3 ? ' 외 ${pending.length - 3}개' : '';
    return '전사 ${pending.length}개가 방금 저장됐습니다. 색인이 끝나면 검색됩니다. $names$more';
  }
  if (_latinQuery(query)) return '"$query"에 대한 결과가 없습니다. 기록은 한글로 남아 있는 경우가 많습니다. 한글로 물어보세요.';
  return '"$query"에 대한 결과가 없습니다.';
}

List<InboxFile> _pendingTranscripts(Inbox? inbox, IndexStatus? index) {
  final at = index?.finishedAt;
  if (inbox == null || at == null || index?.refreshing == true) return const [];
  return inbox.transcripts.where((f) => f.modified != null && f.modified!.isAfter(at)).toList();
}

bool _latinQuery(String query) {
  final latin = RegExp('[A-Za-z]');
  final hangul = RegExp('[가-힣]');
  return latin.hasMatch(query) && !hangul.hasMatch(query);
}

int _rank(RecordingStage stage) => switch (stage) {
      RecordingStage.running => 0,
      RecordingStage.indexing => 1,
      RecordingStage.queued => 2,
      RecordingStage.failed => 3,
      RecordingStage.saved => 4,
      RecordingStage.searchable => 5,
      RecordingStage.waitingDigest => 6,
      RecordingStage.linked => 7,
    };

(String, String?)? _collectFile(String? line) {
  if (line == null || !line.startsWith('전사 ')) return null;
  final parts = line.split(' · ');
  if (parts.length < 2) return null;
  final name = parts[1].trim();
  if (name.isEmpty) return null;
  final detail = parts.length >= 3 ? parts.sublist(2).join(' · ').trim() : null;
  return (name, detail);
}
