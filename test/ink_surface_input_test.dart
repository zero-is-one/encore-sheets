import 'package:encoresheets/page_ink.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'finger suppression covers placement and the stylus takes priority',
    (tester) async {
      final ink = PageInk();
      var textTaps = 0;
      Future<void> show(InkTool tool, {required bool finger}) =>
          tester.pumpWidget(
            Center(
              child: SizedBox(
                width: 250,
                height: 250,
                child: InkSurface(
                  ink: ink,
                  enabled: true,
                  allowFinger: finger,
                  tool: tool,
                  onTextTap: (_, _) => textTaps++,
                ),
              ),
            ),
          );
      final surface = find.byType(InkSurface);
      await show(InkTool.pen, finger: true);
      await tester.drag(surface, const Offset(30, 20));
      expect(ink.snapshot(), hasLength(1));
      await show(InkTool.pen, finger: false);
      await tester.drag(surface, const Offset(30, 20));
      expect(ink.snapshot(), hasLength(1));
      await tester.drag(
        surface,
        const Offset(30, 20),
        kind: PointerDeviceKind.stylus,
      );
      expect(ink.snapshot(), hasLength(2));
      await show(InkTool.text, finger: false);
      await tester.tap(surface);
      expect(textTaps, 0);
      await tester.tap(surface, kind: PointerDeviceKind.stylus);
      expect(textTaps, 1);

      await show(InkTool.pen, finger: true);
      final center = tester.getCenter(surface);
      final palm = await tester.startGesture(center);
      await tester.dragFrom(
        center + const Offset(40, 40),
        const Offset(30, 20),
        kind: PointerDeviceKind.stylus,
      );
      await palm.cancel();
      expect(ink.snapshot(), hasLength(3));
      final beforeClear = ink.snapshot();
      ink.clearAllInk();
      expect(ink.hasInk, isFalse);
      ink.undo();
      expect(ink.snapshot(), beforeClear);

      await tester.pumpWidget(const SizedBox.shrink());
      ink.dispose();
    },
  );
}
