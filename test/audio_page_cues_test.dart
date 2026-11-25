import 'package:encoresheets/audio_page_cues.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('audio cues resolve by position after forward and backward seeks', () {
    final cues = readAudioPageCues([
      {'ms': 1500, 'page': 4},
      {'ms': -1, 'page': 9},
      {'ms': 500, 'page': 2},
      {'ms': 1000, 'page': 3},
    ]);
    expect(audioCueAt(cues, Duration.zero), isNull);
    expect(audioCueAt(cues, const Duration(milliseconds: 1700))?.page, 4);
    expect(audioCueAt(cues, const Duration(milliseconds: 1000))?.page, 3);
    expect(audioCueAt(cues, const Duration(milliseconds: 999))?.page, 2);
  });
}
