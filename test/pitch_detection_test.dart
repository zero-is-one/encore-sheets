import 'dart:math' as math;
import 'dart:typed_data';

import 'package:encoresheets/pitch_detection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects a generated concert A and ignores silence', () {
    const rate = 16000;
    final pcm = ByteData(8192);
    expect(estimatePitch(pcm.buffer.asUint8List(), rate), isNull);
    for (var i = 0; i < pcm.lengthInBytes ~/ 2; i++) {
      pcm.setInt16(
        i * 2,
        (12000 * math.sin(2 * math.pi * 440 * i / rate)).round(),
        Endian.little,
      );
    }
    final pitch = estimatePitch(pcm.buffer.asUint8List(), rate);
    expect(pitch, closeTo(440, 1));
    expect(noteLabel(describePitch(pitch!).midi), 'A4');
  });
}
