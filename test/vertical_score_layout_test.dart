import 'dart:io';

import 'package:encoresheets/main.dart';
import 'package:encoresheets/reader_preferences.dart';
import 'package:encoresheets/score_library.dart';
import 'package:encoresheets/vertical_score_layout.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reader can switch to continuous vertical scrolling', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('encoresheets_scroll'),
    ))!;
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      paths,
      (_) async => root.path,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        paths,
        null,
      );
      await root.delete(recursive: true);
    });
    tester.view.physicalSize = const Size(1000, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(pdfrxFlutterInitialize);
    await tester.pumpWidget(const EncoreSheets());
    PdfViewer viewer() => tester.widget<PdfViewer>(find.byType(PdfViewer));
    Future<void> waitUntil(bool Function() condition) async {
      for (var attempt = 0; attempt < 150 && !condition(); attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(condition(), isTrue);
    }

    await waitUntil(
      () =>
          viewer().controller!.isReady &&
          find.text('1 / 3').evaluate().isNotEmpty,
    );
    expect(viewer().params.paging, isNotNull);
    await tester.tap(find.byTooltip('Reader tools'));
    await tester.pumpAndSettle();
    final option = find.text('Scrolling display · Paged');
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vertical scrolling · Fit width'));
    await waitUntil(
      () =>
          viewer().params.paging == null &&
          viewer().controller!.isReady &&
          find.text('1 / 3').evaluate().isNotEmpty,
    );
    final controller = viewer().controller!;
    expect(
      controller.layout.pageLayouts[1].top,
      greaterThan(controller.layout.pageLayouts.first.bottom),
    );
    final swipe = await tester.startGesture(
      tester.getCenter(find.byType(PdfViewer)),
    );
    for (var step = 0; step < 5; step++) {
      await swipe.moveBy(const Offset(0, -70));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await swipe.up();
    await tester.pump(const Duration(milliseconds: 250));
    expect(controller.visibleRect.top, greaterThan(30));

    await controller.goToPosition(
      documentOffset: Offset(0, controller.layout.pageLayouts[1].top),
    );
    await waitUntil(() => find.text('2 / 3').evaluate().isNotEmpty);
    await tester.tap(find.byTooltip('Reader tools'));
    await tester.pumpAndSettle();
    final scrolling = find.text(
      'Scrolling display · Vertical scrolling · Fit width',
    );
    await tester.ensureVisible(scrolling);
    await tester.tap(scrolling);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paged'));
    await waitUntil(
      () =>
          viewer().params.paging != null &&
          viewer().controller!.isReady &&
          find.text('2 / 3').evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  test('scroll settings round-trip and older scores inherit the default', () {
    final global = const ReaderPreferences().copyWith(
      scrollMode: ReaderScrollMode.fitWidth,
    );
    expect(
      ReaderPreferences.fromJson(global.toJson()).scrollMode,
      ReaderScrollMode.fitWidth,
    );
    final original = ScoreEntry(
      id: 'score',
      title: 'Score',
      page: 2,
      openedAt: DateTime.utc(2026, 1, 1),
    );
    expect(ScoreEntry.fromJson(original.toJson()).scrollMode, isNull);
    final override = original.copyWith(scrollMode: ReaderScrollMode.paged);
    final restored = ScoreEntry.fromJson(override.toJson());
    expect(restored.scrollMode, ReaderScrollMode.paged);
    expect(restored.page, 2);
    expect(restored.copyWith(inheritScrollMode: true).scrollMode, isNull);
  });

  test(
    'fits pages continuously and limits item bookmarks to their range',
    () async {
      await pdfrxFlutterInitialize();
      final document = await PdfDocument.openFile('assets/first_light.pdf');
      try {
        const viewport = Size(1000, 500);
        final context = PdfPageLayoutContext(
          pages: document.pages,
          viewport: viewport,
        );
        const fitWidth = SequentialPagesLayout(fitMode: PdfFitMode.fill);
        const fitPage = SequentialPagesLayout(fitMode: PdfFitMode.fit);
        final full = fitWidth.resolve(context);
        final fitted = fitPage.resolve(context);
        expect(full.pageLayouts.first.height, greaterThan(viewport.height));
        expect(fitted.pageLayouts.first.height, lessThan(viewport.height));
        expect(
          full.pageLayouts[1].top,
          greaterThan(full.pageLayouts.first.bottom),
        );

        final excerpt = const VerticalExcerptLayout(
          fitWidth,
          2,
          3,
        ).resolve(context);
        expect(excerpt.pageLayouts.first.isEmpty, isTrue);
        expect(excerpt.pageLayouts[1].top, excerpt.margin);
        expect(excerpt.documentSize.height, lessThan(full.documentSize.height));
        expect(
          verticalPageAt(
            Offset.zero & viewport,
            excerpt.pageLayouts,
            first: 2,
            last: 3,
          ),
          2,
        );
        expect(
          verticalPageAt(
            Offset(0, excerpt.documentSize.height - viewport.height) & viewport,
            excerpt.pageLayouts,
            first: 2,
            last: 3,
          ),
          3,
        );
      } finally {
        await document.dispose();
      }
    },
  );
}
