import 'package:encoresheets/reader_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts standard page-turn pedal keys', () {
    expect(pageTurnForKey(LogicalKeyboardKey.pageDown), 1);
    expect(pageTurnForKey(LogicalKeyboardKey.pageUp), -1);
    expect(pageTurnForKey(LogicalKeyboardKey.numpadEnter), 1);
    expect(pageTurnForKey(LogicalKeyboardKey.keyA), 0);
  });
}
