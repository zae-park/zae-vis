import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/l10n.dart';
import '../recording/asr_capture.dart';
import '../recording/recorder.dart';
import 'input_dialogs.dart' show toast;

/// Records from the microphone and uploads the result to the inbox (whisperX transcribes it in the
/// background when installed). While recording, a meeting ASR session fills in a live draft when
/// available. The controls float at the bottom right and can be dragged. Returns the saved file
/// name, or null when cancelled.
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
  final void Function(String saved) onQueued;
  final void Function(String? saved) onDone;

  @override
  State<_RecordFloater> createState() => _RecordFloaterState();
}

enum _Phase { idle, recording, uploading, transcribing }

enum _Job { gone, active, failed }

class _RecordFloaterState extends State<_RecordFloater> {
  _Phase _phase = _Phase.idle;
  Timer? _tick;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  double _level = 0;
  String? _error;
  String? _saved;
  String _status = l10nNow.recordPreparing;
  double? _fraction;
  var _closed = false;
  final _stackKey = GlobalKey();
  final _cardKey = GlobalKey();
  bool _moved = false;
  Offset _topLeft = Offset.zero;
  AsrCapture? _asr;
  String _draft = '';
  String? _recordingName;

  @override
  void initState() {
    super.initState();
    final watch = widget.watch;
    if (watch == null) return;
    _phase = _Phase.transcribing;
    _saved = watch;
    _status = l10nNow.recordTranscribing;
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
    unawaited(_asr?.cancel() ?? Future.value());
    widget.recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _draft = '';
    });
    try {
      if (!await widget.recorder.hasPermission()) {
        setState(() => _error = context.l10n.recordMicDenied);
        return;
      }
      _startedAt = DateTime.now();
      _recordingName = recordingName(_startedAt!);
      final cap = AsrCapture(
        api: widget.api,
        recorder: widget.recorder,
        mode: 'meeting',
        name: _recordingName,
        onFinal: (_, all) {
          if (mounted) setState(() => _draft = all);
        },
        onLevel: (lv) {
          if (mounted) setState(() => _level = lv);
        },
        onError: (e) {
          if (mounted) setState(() => _error = context.l10n.recordError('$e'));
        },
      );
      await cap.start();
      _asr = cap;
      _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) setState(() => _elapsed = DateTime.now().difference(_startedAt!));
      });
      setState(() => _phase = _Phase.recording);
    } catch (e) {
      setState(() => _error = context.l10n.recordStartFailed('$e'));
    }
  }

  Future<void> _stopAndUpload() async {
    _tick?.cancel();
    final cap = _asr;
    _asr = null;
    if (cap == null) return;
    final draft = await cap.stop();
    if (draft.isNotEmpty) _draft = draft;
    final pcm = List<Uint8List>.from(cap.localChunks);
    final bytes = wavFromPcm16(pcm);
    final name = _recordingName ?? recordingName(_startedAt ?? DateTime.now());
    setState(() {
      _phase = _Phase.uploading;
      if (_draft.isNotEmpty) _status = _draft;
    });
    try {
      final saved = await widget.api.uploadAudio(name: name, size: bytes.length, bytes: bytes);
      if (!mounted) return;
      widget.onQueued(saved);
      setState(() {
        _phase = _Phase.transcribing;
        _saved = saved;
        _status = _draft.isNotEmpty ? _draft : context.l10n.recordPreparing;
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

  Future<_Job> _readJob(String saved) async {
    try {
      final inbox = await widget.api.inbox();
      final match = inbox.jobs.where((j) => j.file == saved);
      final job = match.isEmpty ? null : match.first;
      if (job == null || job.state == 'done' || job.state == 'cancelled') return _Job.gone;
      final current = job;
      if (current.state == 'failed') {
        if (mounted) {
          setState(() {
            _status = context.l10n.recordTranscribeFailed;
            _error = current.error ?? context.l10n.recordTranscribeFailedLong;
            _fraction = null;
          });
        }
        return _Job.failed;
      }
      if (mounted) {
        setState(() {
          // Keep showing the live draft while the high-quality job runs.
          if (_draft.isEmpty) {
            _status = current.line ?? (current.state == 'queued' ? context.l10n.recordQueued : context.l10n.recordTranscribing);
          }
          _fraction = current.fraction;
          _error = null;
        });
      }
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
    if (mounted) setState(() => _status = context.l10n.recordCancelling);
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
    if (_asr != null) {
      await _asr!.cancel();
      _asr = null;
    }
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
          width: _draft.isEmpty ? 300 : 360,
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
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.drag_indicator, size: 18),
                      const SizedBox(width: 4),
                      Text(context.l10n.recordTitle),
                    ]),
                  ),
                  const Spacer(),
                  IconButton(tooltip: context.l10n.commonClose, visualDensity: VisualDensity.compact, onPressed: _phase == _Phase.uploading ? null : _cancel, icon: const Icon(Icons.close, size: 18)),
                ]),
                Text(
                  recording
                      ? mmss
                      : transcribing
                          ? (_draft.isEmpty ? _status : context.l10n.recordHintTranscribing)
                          : (_phase == _Phase.uploading ? context.l10n.recordUploading : context.l10n.recordTapToStart),
                  style: t.titleSmall,
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: recording ? _level : (transcribing ? _fraction : 0), minHeight: 6, borderRadius: BorderRadius.circular(3)),
                const SizedBox(height: 8),
                Text(
                  recording
                      ? (_draft.isEmpty ? context.l10n.recordHintRecording : _draft)
                      : transcribing
                          ? (_draft.isEmpty ? context.l10n.recordHintTranscribing : _draft)
                          : context.l10n.recordHintIdle,
                  style: t.bodySmall,
                  maxLines: _draft.isEmpty ? 3 : 8,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 10),
                Row(children: [
                  if (!transcribing) TextButton(onPressed: _phase == _Phase.uploading ? null : _cancel, child: Text(context.l10n.commonCancel)),
                  const Spacer(),
                  if (transcribing)
                    FilledButton(onPressed: _stopping ? null : _stopTranscription, child: Text(context.l10n.recordCancelTranscription)),
                  if (!transcribing)
                    FilledButton.icon(
                      onPressed: _phase == _Phase.uploading ? null : (recording ? _stopAndUpload : _start),
                      icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record, size: 18),
                      label: Text(recording ? context.l10n.recordStopUpload : context.l10n.recordStart),
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
  if (saved != null && context.mounted) toast(context, context.l10n.recordQueuedToast(saved));
}
