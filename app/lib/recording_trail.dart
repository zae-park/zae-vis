import 'l10n/l10n.dart';
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
  final l = l10nNow;
  final items = <RecordingTrail>[];
  final covered = <String>{};

  final live = _collectFile(collectLine);
  if (live != null) {
    covered.add(live.$1);
    items.add(RecordingTrail(
      file: live.$1,
      sentence: live.$2 == null || live.$2!.isEmpty ? l.trailRecognizing : l.trailRecognizingDetail(live.$2!),
      stage: RecordingStage.running,
    ));
  }

  for (final job in inbox.jobs) {
    if (covered.contains(job.file)) continue;
    if (job.kind == 'speakers') {
      // a speaker pass for a transcript already saved: its line, opening the transcript
      if (!job.active) continue;
      covered.add(job.file);
      items.add(RecordingTrail(
        file: job.file,
        sentence: job.state == 'queued' ? l.trailSpeakersQueued : l.trailSpeakersRunning(job.line ?? ''),
        stage: job.state == 'queued' ? RecordingStage.queued : RecordingStage.running,
        openPath: 'inbox/transcripts/${job.file}',
      ));
      continue;
    }
    if (job.state == 'queued' || job.state == 'running') {
      covered.add(job.file);
      items.add(RecordingTrail(
        file: job.file,
        sentence: job.state == 'queued' ? l.trailQueued : l.trailRecognizingDetail(job.line ?? l.trailTranscribing),
        stage: job.state == 'queued' ? RecordingStage.queued : RecordingStage.running,
        watch: true,
      ));
    } else if (job.state == 'failed' && inbox.audio.any((a) => a.name == job.file)) {
      covered.add(job.file);
      items.add(RecordingTrail(
        file: job.file,
        sentence: l.trailFailed(job.error ?? l.trailCanRetry),
        stage: RecordingStage.failed,
      ));
    }
  }

  for (final audio in inbox.audio) {
    if (covered.contains(audio.name)) continue;
    covered.add(audio.name);
    items.add(RecordingTrail(file: audio.name, sentence: l.trailNextCollect, stage: RecordingStage.queued));
  }

  for (final transcript in inbox.transcripts) {
    if (covered.contains(transcript.name)) continue;
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
  if (path.contains('processed/transcripts/')) return l10nNow.trailLinked;
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
    RecordingStage.indexing => l10nNow.trailIndexing,
    RecordingStage.waitingDigest => l10nNow.trailWaitingDigest,
    _ => l10nNow.trailSaved,
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
  final l = l10nNow;
  if (total > 0 && shown == 0 && filtered) {
    return l.trailFilteredOut(total);
  }
  if (index?.refreshing == true) return l.trailSearchIndexing;
  final pending = _pendingTranscripts(inbox, index);
  if (pending.isNotEmpty) {
    final names = pending.take(3).map((f) => f.name).join(', ');
    final more = pending.length > 3 ? ' ${l.trailMore(pending.length - 3)}' : '';
    return '${l.trailPendingTranscripts(pending.length)} $names$more';
  }
  if (_latinQuery(query)) return l.trailNoResultsLatin(query);
  return l.trailNoResults(query);
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
