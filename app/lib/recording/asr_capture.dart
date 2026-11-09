import 'dart:async';
import 'dart:typed_data';

import '../api.dart';
import 'recorder.dart';

/// Pushes mic PCM into a server ASR session (live or meeting) and surfaces partial/final text.
/// When [asrStart] fails (no whisperX), falls back to local buffering only — [stop] then returns
/// an empty string and [localChunks] still hold the recording for `/api/voice` or WAV upload.
class AsrCapture {
  AsrCapture({
    required this.api,
    required this.recorder,
    required this.mode,
    this.language,
    this.name,
    this.onPartial,
    this.onFinal,
    this.onLevel,
    this.onError,
  });

  final WorklogApi api;
  final Recorder recorder;
  final String mode; // "live" | "meeting"
  final String? language;
  final String? name;
  final void Function(String text)? onPartial;
  final void Function(String text, String all)? onFinal;
  final void Function(double level)? onLevel;
  final void Function(Object error)? onError;

  String? id;
  final _chunks = <Uint8List>[];
  StreamSubscription<Uint8List>? _sub;
  Timer? _flush;
  final _pending = BytesBuilder(copy: false);
  Future<void>? _inFlight;
  var _closed = false;

  /// True when the server accepted an ASR session (partials/finals will arrive).
  bool get streaming => id != null;

  /// Local PCM kept so meeting mode can still upload a full WAV on stop.
  List<Uint8List> get localChunks => List.unmodifiable(_chunks);

  bool get active => !_closed;

  Future<void> start() async {
    if (!await recorder.hasPermission()) throw StateError('mic');
    _chunks.clear();
    _pending.clear();
    _closed = false;
    try {
      final created = await api.asrStart(mode: mode, language: language, name: name);
      id = created.id;
    } on ApiException catch (e) {
      // 409 no_asr / offline → local buffer only
      id = null;
      if (e.status != 0 && e.status != 404 && e.status != 409) onError?.call(e);
    }
    try {
      final stream = await recorder.startStream();
      _sub = stream.listen((c) {
        if (_closed) return;
        _chunks.add(c);
        _pending.add(c);
        onLevel?.call(pcm16Level(c));
      }, onError: (Object e) => onError?.call(e));
      if (id != null) {
        _flush = Timer.periodic(const Duration(milliseconds: 400), (_) => unawaited(_pump()));
      }
    } catch (e) {
      await cancel();
      rethrow;
    }
  }

  Future<void> _pump() async {
    if (_closed || id == null || _inFlight != null) return;
    final bytes = _pending.takeBytes();
    if (bytes.isEmpty) return;
    final done = Completer<void>();
    _inFlight = done.future;
    try {
      final r = await api.asrPush(id!, bytes);
      if (_closed) return;
      if (r.partial.isNotEmpty) onPartial?.call(r.partial);
      for (final e in r.events) {
        if (e.type == 'final' && e.text.isNotEmpty) onFinal?.call(e.text, r.text);
      }
    } catch (e) {
      onError?.call(e);
    } finally {
      done.complete();
      if (identical(_inFlight, done.future)) _inFlight = null;
    }
  }

  /// Stops the mic and the server session. Returns joined final text (empty in local-only mode).
  Future<String> stop() async {
    _flush?.cancel();
    _flush = null;
    _closed = true;
    // Detach without awaiting — awaiting StreamSubscription.cancel can deadlock in widget tests
    // when the recorder's StreamController.close() is also racing the same subscription.
    final sub = _sub;
    _sub = null;
    unawaited(sub?.cancel() ?? Future.value());
    try {
      await recorder.stop();
    } catch (_) {}
    final sid = id;
    final leftover = _pending.takeBytes();
    id = null;
    final pending = _inFlight;
    if (pending != null) await pending;
    if (sid == null) return '';
    try {
      if (leftover.isNotEmpty) {
        final r = await api.asrPush(sid, leftover);
        if (r.partial.isNotEmpty) onPartial?.call(r.partial);
        for (final e in r.events) {
          if (e.type == 'final' && e.text.isNotEmpty) onFinal?.call(e.text, r.text);
        }
      }
      final r = await api.asrStop(sid);
      return r.text;
    } catch (e) {
      onError?.call(e);
      return '';
    }
  }

  Future<void> cancel() async {
    _flush?.cancel();
    _flush = null;
    _closed = true;
    final sub = _sub;
    _sub = null;
    unawaited(sub?.cancel() ?? Future.value());
    try {
      await recorder.stop();
    } catch (_) {}
    final sid = id;
    id = null;
    if (sid != null) {
      try {
        await api.asrCancel(sid);
      } catch (_) {}
    }
  }
}
