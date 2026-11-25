import 'package:encoresheets/reader_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new fitting preferences preserve older reader layouts by default', () {
    final legacy = ReaderPreferences.fromJson({'landscapeWidth': true});
    expect(legacy.pageFit, ReaderPageFit.standard);
    expect(legacy.landscapeWidth, isTrue);
    for (final fit in ReaderPageFit.values) {
      final restored = ReaderPreferences.fromJson(
        legacy.copyWith(pageFit: fit).toJson(),
      );
      expect(restored.pageFit, fit);
      expect(restored.landscapeWidth, isTrue);
    }
  });
}
