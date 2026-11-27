import 'dart:math' as math;
import 'dart:typed_data';

const tuningNotes = [
  'C',
  'C♯',
  'D',
  'E♭',
  'E',
  'F',
  'F♯',
  'G',
  'A♭',
  'A',
  'B♭',
  'B',
];

double noteFrequency(int midi) =>
    440 * math.pow(2, (midi - 69) / 12).toDouble();
String noteLabel(int midi) => '${tuningNotes[midi % 12]}${midi ~/ 12 - 1}';

({int midi, double cents}) describePitch(double hz) {
  final semitones = 69 + 12 * math.log(hz / 440) / math.ln2;
  final midi = semitones.round();
  return (midi: midi, cents: (semitones - midi) * 100);
}

double? estimatePitch(
  Uint8List bytes,
  int sampleRate, {
  double minimumEnergy = .000015,
}) {
  final view = ByteData.sublistView(bytes);
  final count = bytes.length ~/ 2;
  final maxLag = sampleRate ~/ 44;
  if (count < maxLag * 2) return null;
  final samples = Float64List(count);
  var dc = 0.0;
  for (var i = 0; i < count; i++) {
    samples[i] = view.getInt16(i * 2, Endian.little) / 32768;
    dc += samples[i];
  }
  dc /= count;
  var energy = 0.0;
  for (var i = 0; i < count; i++) {
    samples[i] -= dc;
    energy += samples[i] * samples[i];
  }
  if (energy / count < minimumEnergy) return null;
  final first = math.max(2, sampleRate ~/ 1400);
  final scores = Float64List(maxLag + 1);
  var best = 0.0;
  for (var lag = first; lag <= maxLag; lag++) {
    var sum = 0.0, left = 0.0, right = 0.0;
    for (var i = 0; i < count - lag; i += 2) {
      final a = samples[i], b = samples[i + lag];
      sum += a * b;
      left += a * a;
      right += b * b;
    }
    final norm = math.sqrt(left * right);
    scores[lag] = norm > 0 ? sum / norm : 0;
    best = math.max(best, scores[lag]);
  }
  if (best < .6) return null;
  for (var lag = first + 1; lag < maxLag; lag++) {
    final a = scores[lag - 1], b = scores[lag], c = scores[lag + 1];
    if (b < best * .9 || b <= a || b < c) continue;
    final divisor = a - 2 * b + c;
    final offset = divisor == 0 ? 0.0 : (.5 * (a - c) / divisor).clamp(-.5, .5);
    return sampleRate / (lag + offset);
  }
  return null;
}
