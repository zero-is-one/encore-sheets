import 'package:encoresheets/face_page_turn.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('head gestures need calibration and a return to center', () {
    final turns = FacePageTurn();
    for (var index = 0; index < 8; index++) {
      expect(turns.update(4), 0);
    }
    expect(turns.calibrated, isTrue);
    expect([for (var i = 0; i < 5; i++) turns.update(33)], [0, 0, 1, 0, 0]);
    expect(turns.update(null), 0);
    expect([for (var i = 0; i < 3; i++) turns.update(-25)], [0, 0, 0]);
    expect(turns.update(4), 0);
    expect([for (var i = 0; i < 3; i++) turns.update(-25)], [0, 0, -1]);
  });

  test('winks can turn either way and looking away clears pending turns', () {
    final mode = FaceGestureMode.wink;
    final turns = FacePageTurn(mode: mode, threshold: .5);
    for (var index = 0; index < 8; index++) {
      expect(turns.update(.04), 0);
    }
    expect(turns.update(.8), 0);
    expect(turns.update(mode.readSample({'yaw': 30, 'wink': .8})), 0);
    expect([for (var i = 0; i < 3; i++) turns.update(.8)], [0, 0, 0]);
    expect(turns.update(.04), 0);
    expect([for (var i = 0; i < 3; i++) turns.update(.8)], [0, 0, 1]);
    expect(turns.update(.04), 0);
    expect([for (var i = 0; i < 3; i++) turns.update(-.8)], [0, 0, -1]);
  });

  test('mouth opening is measured relative to the resting position', () {
    final turns = FacePageTurn(mode: FaceGestureMode.mouth, threshold: .1);
    for (var index = 0; index < 8; index++) {
      expect(turns.update(.14), 0);
    }
    expect([for (var i = 0; i < 3; i++) turns.update(.02)], [0, 0, 0]);
    expect([for (var i = 0; i < 5; i++) turns.update(.28)], [0, 0, 1, 0, 0]);
    expect(turns.update(.14), 0);
    expect([for (var i = 0; i < 3; i++) turns.update(.28)], [0, 0, 1]);
  });
}
