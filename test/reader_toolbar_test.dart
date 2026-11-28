import 'dart:ui' show Size;

import 'package:encoresheets/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reader shortcuts keep the same order on tablet and phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const labels = [
      'Score library',
      'Bookmarks',
      'Setlists',
      'Search library',
      'Audio tools',
      'Reader tools',
    ];

    for (final size in [const Size(834, 1194), const Size(320, 768)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(const EncoreSheets());
      await tester.pump();

      final readerTitle = find.byKey(const ValueKey('reader-title'));
      final positions = [
        for (final label in labels) tester.getCenter(find.byTooltip(label)),
      ];
      expect(
        positions.map((point) => point.dx).toList(),
        orderedEquals(positions.map((point) => point.dx).toList()..sort()),
      );
      expect(positions.map((point) => point.dy).toSet(), hasLength(1));
      if (size.width < 720) {
        expect(tester.getCenter(readerTitle).dy, lessThan(positions.first.dy));
      } else {
        for (final label in ['Display', 'Score actions']) {
          expect(find.byTooltip(label), findsOneWidget);
          expect(find.text(label), findsNothing);
        }
        final display = tester.getRect(find.byTooltip('Display'));
        final title = tester.getRect(readerTitle);
        final scoreActions = tester.getRect(find.byTooltip('Score actions'));
        expect(positions[3].dx, lessThan(display.left));
        final rightButtons = [
          for (final label in [
            'Annotations',
            'Quick access',
            'Audio tools',
            'Reader tools',
          ])
            tester.getCenter(find.byTooltip(label)).dx,
        ];
        expect(rightButtons.first, greaterThan(scoreActions.right));
        expect(rightButtons, orderedEquals([...rightButtons]..sort()));
        expect(title.center.dx, closeTo(size.width / 2, 1));
        expect(title.left, closeTo(display.right, 1));
        expect(title.right, closeTo(scoreActions.left, 1));
      }
      expect(tester.takeException(), isNull);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
