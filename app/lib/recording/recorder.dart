import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart' as rec;

/// Microphone capture as 16-bit mono PCM, the same on macOS and in the browser. The dialog turns
/// the chunks into a WAV in memory and uploads it; nothing touches the disk on the way.
abstract class Recorder {
  /// Asks the OS / browser for microphone access (shows the system prompt the first time).
  Future<bool> hasPermission();

  Future<Stream<Uint8List>> startStream({int sampleRate = kSampleRate});

  Future<void> stop();

  Future<void> dispose();
}

const kSampleRate = 16000; // what whisperX resamples to anyway: small files, no quality lost

class PluginRecorder implements Recorder {
  final _r = rec.AudioRecorder();

  @override
  Future<bool> hasPermission() => _r.hasPermission();

  @override
  Future<Stream<Uint8List>> startStream({int sampleRate = kSampleRate}) =>
      _r.startStream(rec.RecordConfig(encoder: rec.AudioEncoder.pcm16bits, sampleRate: sampleRate, numChannels: 1));

  @override
  Future<void> stop() => _r.stop();

  @override
  Future<void> dispose() => _r.dispose();
}

/// Peak level 0..1 of a chunk of little-endian 16-bit samples, for the meter.
double pcm16Level(Uint8List chunk) {
  if (chunk.length < 2) return 0;
  final data = ByteData.sublistView(chunk, 0, chunk.length - chunk.length % 2);
  var peak = 0;
  for (var i = 0; i < data.lengthInBytes; i += 2) {
    final v = data.getInt16(i, Endian.little).abs();
    if (v > peak) peak = v;
  }
  return math.min(1, peak / 32768);
}

/// Wraps PCM chunks in a 44-byte RIFF/WAVE header (PCM, 16-bit).
Uint8List wavFromPcm16(List<Uint8List> chunks, {int sampleRate = kSampleRate, int channels = 1}) {
  final dataSize = chunks.fold<int>(0, (n, c) => n + c.length);
  final out = Uint8List(44 + dataSize);
  final b = ByteData.sublistView(out);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      out[at + i] = s.codeUnitAt(i);
    }
  }

  final byteRate = sampleRate * channels * 2;
  ascii(0, 'RIFF');
  b.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  b.setUint32(16, 16, Endian.little); // PCM fmt chunk size
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, channels, Endian.little);
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, byteRate, Endian.little);
  b.setUint16(32, channels * 2, Endian.little); // block align
  b.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  b.setUint32(40, dataSize, Endian.little);
  var at = 44;
  for (final c in chunks) {
    out.setRange(at, at + c.length, c);
    at += c.length;
  }
  return out;
}

/// "2026-10-26_2041_녹음.wav": sorts by time and is what the transcript will be named after.
String recordingName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}_${two(t.hour)}${two(t.minute)}_녹음.wav';
}
