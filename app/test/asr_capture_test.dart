import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaevis/api.dart';
import 'package:zaevis/recording/asr_capture.dart';
import 'package:zaevis/recording/recorder.dart';

class _FakeRec implements Recorder {
  bool stopped = false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startStream({int sampleRate = kSampleRate}) async {
    stopped = false;
    return Stream<Uint8List>.fromIterable([
      Uint8List.fromList([1, 0, 2, 0]),
      Uint8List.fromList([3, 0]),
    ]);
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('AsrCapture start then stop posts create/audio/stop', () async {
    final posted = <String>[];
    final api = WorklogApi(
      baseUrl: 'http://127.0.0.1:4710',
      client: MockClient((req) async {
        posted.add('${req.method} ${req.url.path}');
        final path = req.url.path;
        if (path == '/api/asr') {
          return http.Response(jsonEncode({'id': 'asr-test', 'mode': 'live'}), 201, headers: {'content-type': 'application/json'});
        }
        if (path.endsWith('/audio')) {
          return http.Response(jsonEncode({'events': <Object>[], 'partial': '', 'text': ''}), 200, headers: {'content-type': 'application/json'});
        }
        if (path.endsWith('/stop')) {
          return http.Response(jsonEncode({'events': <Object>[], 'partial': '', 'text': 'hello'}), 200, headers: {'content-type': 'application/json'});
        }
        if (req.method == 'DELETE') {
          return http.Response(jsonEncode({'ok': true}), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 404);
      }),
    );
    final rec = _FakeRec();
    final cap = AsrCapture(api: api, recorder: rec, mode: 'live');
    await cap.start();
    expect(cap.id, 'asr-test');
    final text = await cap.stop();
    expect(posted.where((p) => p == 'POST /api/asr'), isNotEmpty);
    expect(posted.any((p) => p.endsWith('/stop')), isTrue, reason: 'posted=$posted');
    expect(text, 'hello');
    expect(rec.stopped, isTrue);
  });

  test('AsrCapture cancel deletes the session', () async {
    final posted = <String>[];
    final api = WorklogApi(
      baseUrl: 'http://127.0.0.1:4710',
      client: MockClient((req) async {
        posted.add('${req.method} ${req.url.path}');
        if (req.url.path == '/api/asr') {
          return http.Response(jsonEncode({'id': 'asr-x', 'mode': 'meeting'}), 201, headers: {'content-type': 'application/json'});
        }
        return http.Response(jsonEncode({'ok': true}), 200, headers: {'content-type': 'application/json'});
      }),
    );
    final cap = AsrCapture(api: api, recorder: _FakeRec(), mode: 'meeting', name: 'n.wav');
    await cap.start();
    await cap.cancel();
    expect(posted.any((p) => p.startsWith('DELETE ')), isTrue, reason: 'posted=$posted');
  });
}
