import 'package:encoresheets/half_page_turn.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'advances and reverses through mixed half-page views within a setlist item',
    () {
      ({int page, bool preview}) turn(int page, bool preview, int step) =>
          advanceHalfTurn(
            page: page,
            first: 3,
            last: 5,
            preview: preview,
            step: step,
          );

      expect(turn(3, false, 1), (page: 3, preview: true));
      expect(turn(3, true, 1), (page: 4, preview: false));
      expect(turn(4, false, -1), (page: 3, preview: true));
      expect(turn(3, true, -1), (page: 3, preview: false));
      expect(turn(3, false, -1), (page: 3, preview: false));
      expect(turn(5, false, 1), (page: 6, preview: false));
    },
  );
}
