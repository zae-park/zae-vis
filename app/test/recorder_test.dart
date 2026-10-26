import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaevis/recording/recorder.dart';

void main() {
  test('wavFromPcm16 writes a valid 44-byte header around the samples', () {
    final a = Uint8List.fromList([1, 0, 2, 0]);
    final b = Uint8List.fromList([3, 0]);
    final wav = wavFromPcm16([a, b], sampleRate: 16000);
    expect(wav.length, 44 + 6);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    final d = ByteData.sublistView(wav);
    expect(d.getUint32(4, Endian.little), 36 + 6);
    expect(d.getUint16(20, Endian.little), 1); // PCM
    expect(d.getUint16(22, Endian.little), 1); // mono
    expect(d.getUint32(24, Endian.little), 16000);
    expect(d.getUint32(28, Endian.little), 32000); // byte rate
    expect(d.getUint16(34, Endian.little), 16);
    expect(d.getUint32(40, Endian.little), 6);
    expect(wav.sublist(44), [1, 0, 2, 0, 3, 0]);
  });

  test('pcm16Level peaks at 1 for full scale and 0 for silence', () {
    expect(pcm16Level(Uint8List.fromList([0, 0, 0, 0])), 0);
    expect(pcm16Level(Uint8List.fromList([0xFF, 0x7F])), closeTo(1, 0.001)); // 32767
    expect(pcm16Level(Uint8List.fromList([0x00, 0x40])), closeTo(0.5, 0.001)); // 16384
  });

  test('recordingName sorts by time', () {
    expect(recordingName(DateTime(2026, 10, 26, 20, 41)), '2026-10-26_2041_녹음.wav');
  });
}
