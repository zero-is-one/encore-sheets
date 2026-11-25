import 'package:encoresheets/turn_touch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Turn Touch buttons and gestures provide distinct shortcut codes', () {
    expect(turnTouchShortcut([0xfe, 0]), 'turntouch:North');
    expect(turnTouchShortcut([0xfd, 0]), 'turntouch:East');
    expect(turnTouchShortcut([0xdf, 0]), 'turntouch:East double tap');
    expect(turnTouchShortcut([0xfd, 0xff]), 'turntouch:East hold');
    expect(turnTouchShortcut([0xff, 0]), isNull);
    expect(turnTouchShortcut([0xfe]), isNull);
  });
}
