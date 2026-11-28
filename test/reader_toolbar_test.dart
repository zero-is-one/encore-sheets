import 'dart:ui' show Size;

import 'package:encoresheets/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show IconButton;

void main() {
  testWidgets(
    'reader shortcuts keep the same order on tablet and phone',
    (tester) async {
      for (final name in ['encoresheets/import', 'encoresheets/links']) {
        final channel = MethodChannel(name);
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (_) async => <String>[]);
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      }
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const left = ['Score library', 'Bookmarks', 'Setlists', 'Services'];
      const right = [
        'Annotations',
        'Search library',
        'Audio utilities',
        'Reader tools',
      ];

      for (final size in [const Size(834, 1194), const Size(320, 768)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(const EncoreSheets());
        await tester.pump();

        final readerTitle = find.byKey(const ValueKey('reader-title'));
        final positions = [
          for (final label in left) tester.getCenter(find.byTooltip(label)),
        ];
        expect(
          positions.map((point) => point.dx).toList(),
          orderedEquals(positions.map((point) => point.dx).toList()..sort()),
        );
        expect(positions.map((point) => point.dy).toSet(), hasLength(1));
        if (size.width < 720) {
          expect(
            tester.getCenter(readerTitle).dy,
            lessThan(positions.first.dy),
          );
        } else {
          for (final label in ['Display', 'Score actions']) {
            expect(find.byTooltip(label), findsOneWidget);
            expect(find.text(label), findsNothing);
          }
          final display = tester.getRect(find.byTooltip('Display'));
          final title = tester.getRect(readerTitle);
          final scoreActions = tester.getRect(find.byTooltip('Score actions'));
          expect(positions[3].dx, lessThan(display.left));
          expect(
            tester.getCenter(find.byTooltip(right.first)).dx,
            greaterThan(scoreActions.right),
          );
          expect(title.center.dx, closeTo(size.width / 2, 1));
          expect(title.left, closeTo(display.right, 8));
          expect(title.right, closeTo(scoreActions.left, 8));
        }
        final rightButtons = [
          for (final label in right) tester.getCenter(find.byTooltip(label)).dx,
        ];
        expect(rightButtons, orderedEquals([...rightButtons]..sort()));
        if (size.width < 720) {
          expect(rightButtons.first, greaterThan(positions.last.dx));
        }
        if (defaultTargetPlatform == TargetPlatform.android &&
            size.width >= 720) {
          final audio = find.byWidgetPredicate(
            (widget) =>
                widget is IconButton && widget.tooltip == 'Audio utilities',
          );
          for (
            var attempt = 0;
            attempt < 50 && tester.widget<IconButton>(audio).onPressed == null;
            attempt++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          expect(tester.widget<IconButton>(audio).onPressed, isNotNull);
          await tester.tap(audio);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          expect(
            find.text('Metronome'),
            findsOneWidget,
            reason: 'Audio Utilities should open on the tablet',
          );
          expect(find.text('Pitch'), findsOneWidget);
          expect(find.text('Tuner'), findsOneWidget);
          expect(find.text('Tap tempo'), findsOneWidget);
          await tester.tap(find.text('Pitch'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          expect(find.text('Play reference tone'), findsOneWidget);
          await tester.tap(find.text('Done'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
        }
        expect(tester.takeException(), isNull);
      }
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.android,
    }),
  );
}
