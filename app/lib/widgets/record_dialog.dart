import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api.dart';
import '../recording/recorder.dart';
import 'input_dialogs.dart' show toast;

/// Records from the microphone and uploads the result to the inbox (whisperX transcribes it in the
/// background when installed). The controls float at the bottom right and can be dragged, so the
/// rest of the app stays usable. Returns the saved file name, or null when cancelled.
Completer<String?>? _recordOpen;

Future<String?> showRecordDialog(BuildContext context, WorklogApi api, {Recorder? recorder, String? watch}) {
  final pending = _recordOpen;
  if (pending != null) return pending.future;
  final completer = Completer<String?>();
  _recordOpen = completer;
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _RecordFloater(
      api: api,
      recorder: recorder ?? PluginRecorder(),
      watch: watch,
      onQueued: (saved) {
        if (!completer.isCompleted) completer.complete(saved);
      },
      onDone: (saved) {
        entry.remove();
        _recordOpen = null;
        if (!completer.isCompleted) completer.complete(saved);
      },
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class _RecordFloater extends StatefulWidget {
  const _RecordFloater({required this.api, required this.recorder, required this.onQueued, required this.onDone, this.watch});
  final WorklogApi api;
  final Recorder recorder;

  /// An audio file already in the queue. The floater opens on its progress instead of a new recording.
  final String? watch;
  /// The file is in the inbox. The floater stays up afterwards while whisperX runs.
  final void Function(String saved) onQueued;
  final void Function(String? saved) onDone;

  @override
  State<_RecordFloater> createState() => _RecordFloaterState();
}

enum _Phase { idle, recording, uploading, transcribing }

enum _Job { gone, active, failed }

class _RecordFloaterState extends State<_RecordFloater> {
  _Phase _phase = _Phase.idle;
  final _chunks = <Uint8List>[];
  StreamSubscription<Uint8List>? _sub;
  Timer? _tick;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  double _level = 0;
  String? _error;
  String? _saved;
  String _status = '전사 준비 중';
  double? _fraction;
  var _closed = false;
  final _stackKey = GlobalKey();
  final _cardKey = GlobalKey();
  bool _moved = false;
  Offset _topLeft = Offset.zero;

  @override
  void initState() {
    super.initState();
    final watch = widget.watch;
    if (watch == null) return;
    _phase = _Phase.transcribing;
    _saved = watch;
    _status = '전사 중…';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closed) _follow(watch);
    });
  }

  Future<void> _follow(String saved) async {
    final job = await _readJob(saved);
    if (!mounted || _closed) return;
    if (job != _Job.active) {
      if (job == _Job.gone) _close(saved);
      return;
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) async {
      final next = await _readJob(saved);
      if (!mounted || _closed) return;
      if (next == _Job.gone) _close(saved);
      if (next == _Job.failed) _tick?.cancel();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _sub?.cancel();
    widget.recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      if (!await widget.recorder.hasPermission()) {
        setState(() => _error = '마이크 접근이 허용되지 않았습니다. 시스템 설정 → 개인정보 보호 및 보안 → 마이크에서 zaevis를 켜 주세요.');
        return;
      }
      final stream = await widget.recorder.startStream();
      _chunks.clear();
      _startedAt = DateTime.now();
      _sub = stream.listen((c) {
        _chunks.add(c);
        _level = pcm16Level(c);
      }, onError: (Object e) => setState(() => _error = '녹음 오류: $e'));
      _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) setState(() => _elapsed = DateTime.now().difference(_startedAt!));
      });
      setState(() => _phase = _Phase.recording);
    } catch (e) {
      setState(() => _error = '녹음을 시작하지 못했습니다: $e');
    }
  }

  Future<void> _stopAndUpload() async {
    _tick?.cancel();
    await widget.recorder.stop(); // the plugin ends the stream here; no further chunks arrive
    // not awaited: a subscription on an already-ended stream may settle its cancel() late
    unawaited(_sub?.cancel() ?? Future.value());
    _sub = null;
    final bytes = wavFromPcm16(_chunks);
    final name = recordingName(_startedAt ?? DateTime.now());
    setState(() => _phase = _Phase.uploading);
    try {
      final saved = await widget.api.uploadAudio(name: name, size: bytes.length, bytes: bytes);
      if (!mounted) return;
      widget.onQueued(saved);
      setState(() {
        _phase = _Phase.transcribing;
        _saved = saved;
        _status = '전사 준비 중';
        _fraction = null;
      });
      final job = await _readJob(saved);
      if (!mounted || _closed) return;
      if (job != _Job.active) {
        if (job == _Job.gone) _close(saved);
        return;
      }
      _tick = Timer.periodic(const Duration(seconds: 1), (_) async {
        final next = await _readJob(saved);
        if (!mounted || _closed) return;
        if (next == _Job.gone) _close(saved);
        if (next == _Job.failed) _tick?.cancel();
      });
    } on ApiException catch (e) {
      setState(() {
        _phase = _Phase.idle;
        _error = e.message;
      });
    }
  }

  /// gone: nothing left to wait for. active: still queued or running. failed: the floater stays so the error can be read.
  Future<_Job> _readJob(String saved) async {
    try {
      final inbox = await widget.api.inbox();
      final match = inbox.jobs.where((j) => j.file == saved);
      final job = match.isEmpty ? null : match.first;
      if (job == null || job.state == 'done' || job.state == 'cancelled') return _Job.gone;
      final current = job;
      if (current.state == 'failed') {
        if (mounted) setState(() {
          _status = '전사 실패';
          _error = current.error ?? '전사에 실패했습니다';
          _fraction = null;
        });
        return _Job.failed;
      }
      if (mounted) setState(() {
        _status = current.line ?? (current.state == 'queued' ? '전사 대기' : '전사 중…');
        _fraction = current.fraction;
        _error = null;
      });
      return _Job.active;
    } catch (_) {
      return _Job.gone;
    }
  }

  var _stopping = false;

  Future<void> _stopTranscription() async {
    if (_stopping) return;
    _stopping = true;
    final saved = _saved;
    if (mounted) setState(() => _status = '취소하는 중');
    if (saved != null) {
      try {
        await widget.api.cancelTranscription(saved);
      } on ApiException catch (e) {
        if (e.status != 404) {
          _stopping = false;
          if (mounted) setState(() => _error = e.message);
          return;
        }
      }
    }
    if (mounted) _close(saved);
  }

  void _close(String? saved) {
    if (_closed) return;
    _closed = true;
    _tick?.cancel();
    widget.onDone(saved);
  }

  Future<void> _cancel() async {
    _tick?.cancel();
    if (_phase == _Phase.recording) await widget.recorder.stop();
    unawaited(_sub?.cancel() ?? Future.value());
    _sub = null;
    if (mounted) _close(_phase == _Phase.transcribing ? _saved : null);
  }

  void _drag(DragUpdateDetails details) {
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final card = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || card == null) return;
    if (!_moved) {
      _topLeft = stack.globalToLocal(card.localToGlobal(Offset.zero));
      _moved = true;
    }
    final size = stack.size;
    setState(() {
      final next = _topLeft + details.delta;
      _topLeft = Offset(next.dx.clamp(8, size.width - 308), next.dy.clamp(8, size.height - 80));
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    String two(int n) => n.toString().padLeft(2, '0');
    final mmss = '${two(_elapsed.inMinutes)}:${two(_elapsed.inSeconds % 60)}';
    final recording = _phase == _Phase.recording;
    final transcribing = _phase == _Phase.transcribing;
    return SizedBox.expand(
      key: _stackKey,
      child: Stack(children: [
        Positioned(
          left: _moved ? _topLeft.dx : null,
          top: _moved ? _topLeft.dy : null,
          right: _moved ? null : 20,
          bottom: _moved ? null : 24,
          width: 300,
          child: Material(
            key: _cardKey,
            elevation: 6,
            color: scheme.surfaceContainerLowest,
            shadowColor: Colors.black26,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.outlineVariant)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  GestureDetector(
                    onPanUpdate: _drag,
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.drag_indicator, size: 18),
                      SizedBox(width: 4),
                      Text('녹음'),
                    ]),
                  ),
                  const Spacer(),
                  IconButton(tooltip: '닫기', visualDensity: VisualDensity.compact, onPressed: _phase == _Phase.uploading ? null : _cancel, icon: const Icon(Icons.close, size: 18)),
                ]),
                Text(
                  recording
                      ? mmss
                      : transcribing
                          ? _status
                          : (_phase == _Phase.uploading ? '올리는 중…' : '눌러서 녹음 시작'),
                  style: t.titleSmall,
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: recording ? _level : (transcribing ? _fraction : 0), minHeight: 6, borderRadius: BorderRadius.circular(3)),
                const SizedBox(height: 8),
                Text(
                  recording
                      ? '중지하면 inbox에 올라가고, whisperX가 설치돼 있으면 바로 전사합니다.'
                      : transcribing
                          ? '오른쪽 위를 누르면 전사는 이어집니다. 녹음은 inbox에 남습니다.'
                          : '16kHz 모노 WAV로 저장합니다. 1분에 약 2MB. 첫 녹음 때 마이크 권한을 묻습니다.',
                  style: t.bodySmall,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 10),
                Row(children: [
                  if (!transcribing) TextButton(onPressed: _phase == _Phase.uploading ? null : _cancel, child: const Text('취소')),
                  const Spacer(),
                  if (transcribing)
                    FilledButton(onPressed: _stopping ? null : _stopTranscription, child: const Text('전사 취소')),
                  if (!transcribing)
                    FilledButton.icon(
                      onPressed: _phase == _Phase.uploading ? null : (recording ? _stopAndUpload : _start),
                      icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record, size: 18),
                      label: Text(recording ? '중지하고 올리기' : '녹음 시작'),
                    ),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Shared by the app bar button and the collect tab.
Future<void> recordAndNotify(BuildContext context, WorklogApi api, {Recorder? recorder}) async {
  final saved = await showRecordDialog(context, api, recorder: recorder);
  if (saved != null && context.mounted) toast(context, '녹음을 전사 대기열에 넣었습니다: $saved');
}
