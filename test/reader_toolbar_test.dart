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

      final positions = [
        for (final label in labels) tester.getCenter(find.byTooltip(label)),
      ];
      expect(
        positions.map((point) => point.dx).toList(),
        orderedEquals(positions.map((point) => point.dx).toList()..sort()),
      );
      expect(positions.map((point) => point.dy).toSet(), hasLength(1));
      if (size.width < 720) {
        expect(
          tester.getCenter(find.text('First Light')).dy,
          lessThan(positions.first.dy),
        );
      } else {
        for (final label in ['Display', 'Score actions']) {
          expect(find.byTooltip(label), findsOneWidget);
          expect(find.text(label), findsNothing);
        }
      }
      expect(tester.takeException(), isNull);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
