import 'dart:math' as math;
import 'dart:typed_data';

enum RehearsalChannel { both, left, right }

const rehearsalSampleRate = 22050;

Uint8List _wave(
  int frames,
  double Function(int frame) sample,
  RehearsalChannel channel,
) {
  final bytes = ByteData(44 + frames * 4);
  void tag(int index, String value) {
    for (final (offset, code) in value.codeUnits.indexed) {
      bytes.setUint8(index + offset, code);
    }
  }

  tag(0, 'RIFF');
  bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
  tag(8, 'WAVEfmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 2, Endian.little);
  bytes.setUint32(24, rehearsalSampleRate, Endian.little);
  bytes.setUint32(28, rehearsalSampleRate * 4, Endian.little);
  bytes.setUint16(32, 4, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  bytes.setUint32(40, frames * 4, Endian.little);
  for (var i = 0; i < frames; i++) {
    final value = (sample(i).clamp(-1.0, 1.0) * 32767).round();
    bytes.setInt16(
      44 + i * 4,
      channel == RehearsalChannel.right ? 0 : value,
      Endian.little,
    );
    bytes.setInt16(
      46 + i * 4,
      channel == RehearsalChannel.left ? 0 : value,
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}

Uint8List metronomeWave(
  int bpm,
  int beats,
  RehearsalChannel channel, {
  bool soft = false,
}) {
  final spacing = rehearsalSampleRate * 60 / bpm;
  return _wave((beats * spacing).round(), (frame) {
    final beat = math.min(beats - 1, (frame / spacing).floor());
    final seconds = (frame - beat * spacing) / rehearsalSampleRate;
    if (seconds > .045) return 0;
    final frequency = soft ? (beat == 0 ? 760 : 500) : (beat == 0 ? 1500 : 950);
    return math.sin(seconds * frequency * 2 * math.pi) *
        math.exp(-seconds * 100) *
        .62;
  }, channel);
}

Uint8List referenceToneWave(double frequency) {
  const length = 2;
  return _wave(rehearsalSampleRate * length, (frame) {
    final seconds = frame / rehearsalSampleRate;
    final fade = math.min(1.0, math.min(seconds, length - seconds) * 35);
    return math.sin(seconds * frequency * 2 * math.pi) * fade * .4;
  }, RehearsalChannel.both);
}

Uint8List pianoNoteWave(int midiNote) {
  final frequency = 440 * math.pow(2, (midiNote - 69) / 12);
  const duration = 1.2;
  return _wave((rehearsalSampleRate * duration).round(), (frame) {
    final time = frame / rehearsalSampleRate;
    final phase = time * frequency * 2 * math.pi;
    final attack = math.min(1.0, time * 220);
    final release = math.min(1.0, (duration - time) * 12);
    return (math.sin(phase) * math.exp(-3 * time) +
            math.sin(phase * 2.003) * .30 * math.exp(-7 * time) +
            math.sin(phase * 3.008) * .15 * math.exp(-11 * time)) *
        attack *
        release *
        .27;
  }, RehearsalChannel.both);
}
