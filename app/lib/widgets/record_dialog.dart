import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api.dart';
import '../recording/recorder.dart';
import 'input_dialogs.dart' show toast;

/// Records from the microphone and uploads the result to the inbox (whisperX transcribes it in the
/// background when installed). Returns the saved file name, or null when cancelled.
Future<String?> showRecordDialog(BuildContext context, WorklogApi api, {Recorder? recorder}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RecordDialog(api: api, recorder: recorder ?? PluginRecorder()),
    );

class _RecordDialog extends StatefulWidget {
  const _RecordDialog({required this.api, required this.recorder});
  final WorklogApi api;
  final Recorder recorder;

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

enum _Phase { idle, recording, uploading }

class _RecordDialogState extends State<_RecordDialog> {
  _Phase _phase = _Phase.idle;
  final _chunks = <Uint8List>[];
  StreamSubscription<Uint8List>? _sub;
  Timer? _tick;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  double _level = 0;
  String? _error;

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
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      setState(() {
        _phase = _Phase.idle;
        _error = e.message;
      });
    }
  }

  Future<void> _cancel() async {
    _tick?.cancel();
    if (_phase == _Phase.recording) await widget.recorder.stop();
    unawaited(_sub?.cancel() ?? Future.value());
    _sub = null;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    String two(int n) => n.toString().padLeft(2, '0');
    final mmss = '${two(_elapsed.inMinutes)}:${two(_elapsed.inSeconds % 60)}';
    final recording = _phase == _Phase.recording;
    return AlertDialog(
      title: const Text('녹음'),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _phase == _Phase.uploading ? null : (recording ? _stopAndUpload : _start),
            child: CircleAvatar(
              radius: 40,
              backgroundColor: recording ? scheme.error : scheme.primary,
              child: Icon(recording ? Icons.stop : Icons.mic, size: 40, color: scheme.onPrimary),
            ),
          ),
          const SizedBox(height: 14),
          Text(recording ? mmss : (_phase == _Phase.uploading ? '올리는 중…' : '눌러서 녹음 시작'), style: t.titleMedium),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: recording ? _level : 0, minHeight: 6, borderRadius: BorderRadius.circular(3)),
          const SizedBox(height: 12),
          Text(
            recording
                ? '중지하면 inbox에 올라가고, whisperX가 설치돼 있으면 바로 전사합니다.'
                : '16kHz 모노 WAV로 저장합니다. 1분에 약 2MB. 첫 녹음 때 마이크 권한을 묻습니다.',
            style: t.bodySmall,
            textAlign: TextAlign.center,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: scheme.error), textAlign: TextAlign.center),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _phase == _Phase.uploading ? null : _cancel, child: const Text('취소')),
        FilledButton.icon(
          onPressed: _phase == _Phase.uploading ? null : (recording ? _stopAndUpload : _start),
          icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record),
          label: Text(recording ? '중지하고 올리기' : '녹음 시작'),
        ),
      ],
    );
  }
}

/// Shared by the app bar button and the collect tab.
Future<void> recordAndNotify(BuildContext context, WorklogApi api, {Recorder? recorder}) async {
  final saved = await showRecordDialog(context, api, recorder: recorder);
  if (saved != null && context.mounted) toast(context, '녹음을 전사 대기열에 넣었습니다: $saved');
}
