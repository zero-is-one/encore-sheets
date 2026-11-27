import 'dart:io';

import 'package:encoresheets/main.dart';
import 'package:encoresheets/library_storage_native.dart';
import 'package:encoresheets/reader_input.dart';
import 'package:encoresheets/reader_appearance_options.dart';
import 'package:encoresheets/reader_preferences.dart';
import 'package:encoresheets/score_library.dart';
import 'package:encoresheets/vertical_score_layout.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'
    show GridView, SizedBox, SliverGridDelegateWithFixedCrossAxisCount;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    show CheckedPopupMenuItem, IconButton, Icons, IconTheme, InputChip, Slider;
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reader auto-scrolls, pauses, and advances through a setlist', (
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
      if (await root.exists()) await root.delete(recursive: true);
    });
    tester.view.physicalSize = const Size(1000, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      final library = ScoreLibrary(NativeLibraryStorage(directory: root));
      final first = await File('assets/first_light.pdf')
          .copy('${root.path}/Transition first.pdf');
      final second = await first.copy('${root.path}/Transition second.pdf');
      final (a, _) = await library.import(XFile(first.path));
      final (b, _) = await library.import(XFile(second.path));
      for (final score in [a, b]) {
        await library.updateScore(
          score.id,
          (entry) => entry.copyWith(scrollMode: ReaderScrollMode.fitWidth),
        );
      }
      await library.saveSetlist(
        Setlist('auto-scroll', 'Scrolling rehearsal', [a.id, b.id]),
      );
      await library.saveSetlist(Setlist('assign', 'Assignment test', []));
      await library.updatePreferences({
        'dockPanels': true,
        'readerShortcuts': {
          shortcutKey(LogicalKeyboardKey.keyS): ReaderShortcut.autoScroll.name,
        },
      });
    });
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
          find.byType(PdfViewer).evaluate().isNotEmpty &&
          viewer().controller!.isReady &&
          find.text('1 / 3').evaluate().isNotEmpty,
    );
    expect(viewer().params.paging, isNotNull);
    await tester.tap(find.byTooltip('Score actions'));
    await tester.pumpAndSettle();
    expect(find.text('Copy a measure first.'), findsOneWidget);
    await tester.tap(find.text('Add page note'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 note'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    final enabledIcons = [
      Icons.library_music_outlined,
      Icons.tune,
      Icons.chevron_right,
    ];
    await waitUntil(
      () => enabledIcons.every(
        (icon) =>
            IconTheme.of(tester.element(find.byIcon(icon))).color ==
            ReaderPalette.classic.text,
      ),
    );
    expect(
      IconTheme.of(tester.element(find.byIcon(Icons.chevron_left))).color,
      isNot(ReaderPalette.classic.text),
    );
    expect(find.byTooltip('Fit mode: Fit page'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    final pageCount = tester.getCenter(find.text('1 / 3'));
    final previous = tester.getCenter(find.byIcon(Icons.chevron_left));
    final next = tester.getCenter(find.byIcon(Icons.chevron_right));
    expect(previous.dx, lessThan(pageCount.dx));
    expect(next.dx, greaterThan(pageCount.dx));
    expect(next.dx - previous.dx, lessThan(160));
    final scoreBounds = tester.getRect(find.byType(PdfViewer));
    expect(find.byTooltip('Open in new tab'), findsNothing);
    final visiblePage = viewer().controller!.visibleRect;
    await tester.tap(find.byIcon(Icons.draw_outlined));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(PdfViewer)), scoreBounds);
    expect(viewer().controller!.visibleRect, visiblePage);
    await tester.tap(find.byTooltip('Annotation layers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF page'));
    await tester.pumpAndSettle();
    final activeReader = viewer().controller!;
    Offset pagePoint(double x, double y, {int page = 1}) {
      final layout = activeReader.layout.pageLayouts[page - 1];
      return tester.getTopLeft(find.byType(PdfViewer)) +
          activeReader.documentToLocal(
            layout.topLeft + Offset(layout.width * x, layout.height * y),
          );
    }

    await tester.dragFrom(
      pagePoint(.2, .25),
      pagePoint(.55, .35) - pagePoint(.2, .25),
    );
    await tester.pumpAndSettle();
    Finder markupButton(String label) => find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == label,
    );
    final copyMusic = markupButton('Copy selected music');
    expect(tester.widget<IconButton>(copyMusic).onPressed, isNotNull);
    await tester.tap(copyMusic);
    final placeMusic = markupButton('Place copied music');
    await waitUntil(
      () => tester.widget<IconButton>(placeMusic).onPressed != null,
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right));
    await waitUntil(() => find.text('2 / 3').evaluate().isNotEmpty);
    await tester.tap(find.byIcon(Icons.draw_outlined));
    await tester.pumpAndSettle();
    await tester.tap(placeMusic);
    await tester.pumpAndSettle();
    expect(find.text('Tap the score to place'), findsOneWidget);
    await tester.tapAt(pagePoint(.2, .45, page: 2));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Selection actions'), findsOneWidget);
    await tester.tap(find.byTooltip('Undo stroke'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left));
    await waitUntil(() => find.text('1 / 3').evaluate().isNotEmpty);
    expect(tester.getRect(find.byType(PdfViewer)), scoreBounds);

    expect(find.byTooltip('Page thumbnails'), findsOneWidget);
    await tester.tap(find.text('1 / 3'));
    await tester.pumpAndSettle();
    final thumbnails = tester.widget<GridView>(find.byType(GridView));
    expect(
      (thumbnails.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      2,
    );
    await tester.tap(find.text('Page 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Display'));
    await tester.pumpAndSettle();
    final option = find.text('Scrolling display · Paged');
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vertical scrolling · Fit width').first);
    await waitUntil(
      () =>
          viewer().params.paging == null &&
          viewer().controller!.isReady &&
          find.text('1 / 3').evaluate().isNotEmpty,
    );
    final controller = viewer().controller!;
    await tester.tap(find.byTooltip('Fit mode: Fit width'));
    await tester.pumpAndSettle();
    final fitWidthItem = find.ancestor(
      of: find.text('Fit width'),
      matching: find.byType(CheckedPopupMenuItem<bool>),
    );
    final fitWidth = tester.widget<CheckedPopupMenuItem<bool>>(fitWidthItem);
    expect(fitWidth.checked, isTrue);
    await tester.tap(fitWidthItem);
    await tester.pumpAndSettle();
    expect(
      controller.layout.pageLayouts[1].top,
      greaterThan(controller.layout.pageLayouts.first.bottom),
    );
    await tester.tap(find.byTooltip('Display'));
    await tester.pumpAndSettle();
    final automatic = find.text('Automatic scrolling');
    await tester.ensureVisible(automatic);
    await tester.tap(automatic);
    await tester.pumpAndSettle();
    expect(find.text('20 seconds per screen'), findsOneWidget);
    await tester.tap(find.text('Start scrolling'));
    final stop = find.byTooltip('Stop automatic scrolling');
    await waitUntil(() => stop.evaluate().isNotEmpty);
    expect(find.byTooltip('Scroll slower'), findsOneWidget);
    await tester.tap(find.byTooltip('Scroll faster'));
    await tester.pump();
    final start = controller.visibleRect.top;
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.visibleRect.top, greaterThan(start));
    await tester.tap(stop);
    await tester.pump();
    final paused = controller.visibleRect.top;
    await tester.pump(const Duration(milliseconds: 500));
    expect(stop, findsNothing);
    expect(controller.visibleRect.top, closeTo(paused, .01));

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
    await tester.tap(find.byTooltip('Display'));
    await tester.pumpAndSettle();
    final scrolling = find.text(
      'Scrolling display · Vertical scrolling · Fit width',
    );
    await tester.ensureVisible(scrolling);
    await tester.tap(scrolling);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paged').first);
    await waitUntil(
      () =>
          viewer().params.paging != null &&
          viewer().controller!.isReady &&
          find.text('2 / 3').evaluate().isNotEmpty,
    );
    await tester.tap(find.byTooltip('Setlists'));
    await waitUntil(
      () => find.text('Scrolling rehearsal').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Scrolling rehearsal'));
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Transition first'), findsOneWidget);
    expect(find.text('Transition second'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit setlist'));
    await tester.pumpAndSettle();
    expect(find.text('Search scores'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    await waitUntil(
      () =>
          find.byType(PdfViewer).evaluate().length == 1 &&
          viewer().params.paging == null &&
          viewer().controller!.isReady &&
          find.text('Transition first').evaluate().isNotEmpty,
    );
    final firstScore = viewer().controller!;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await waitUntil(() => stop.evaluate().isNotEmpty);
    await firstScore.goToPosition(
      documentOffset: Offset(
        firstScore.visibleRect.left,
        firstScore.layout.documentSize.height,
      ),
    );
    for (var frame = 0; frame < 85; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await waitUntil(
      () =>
          viewer().controller != firstScore &&
          viewer().controller!.isReady &&
          find.text('Transition second').evaluate().isNotEmpty,
    );
    expect(stop, findsOneWidget);
    var lastScore = viewer().controller!;
    await lastScore.goToPosition(
      documentOffset: Offset(
        lastScore.visibleRect.left,
        lastScore.layout.documentSize.height,
      ),
    );
    await waitUntil(() => stop.evaluate().isEmpty);

    await lastScore.goToPosition(documentOffset: Offset.zero);
    await waitUntil(() => lastScore.visibleRect.top <= 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await waitUntil(
      () =>
          viewer().controller != lastScore &&
          viewer().controller!.isReady &&
          find.text('Transition first').evaluate().isNotEmpty &&
          find.text('3 / 3').evaluate().isNotEmpty,
    );
    final reopenedFirst = viewer().controller!;
    await reopenedFirst.goToPosition(
      documentOffset: Offset(0, reopenedFirst.layout.documentSize.height),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await waitUntil(
      () =>
          viewer().controller != reopenedFirst &&
          viewer().controller!.isReady &&
          find.text('Transition second').evaluate().isNotEmpty,
    );
    lastScore = viewer().controller!;

    await lastScore.goToPosition(
      documentOffset: Offset(
        lastScore.visibleRect.left,
        lastScore.layout.pageLayouts[1].top,
      ),
    );
    await waitUntil(() => lastScore.visibleRect.top > 20);
    await tester.tap(find.byTooltip('Score library'));
    await waitUntil(
      () => find.byTooltip('Add to setlist').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byType(PdfViewer)).dx,
      greaterThanOrEqualTo(368),
    );
    final beforeDockedTurn = viewer().controller!.visibleRect.top;
    await tester.tap(find.byTooltip('Scroll down'));
    await tester.pumpAndSettle();
    expect(viewer().controller!.visibleRect.top, greaterThan(beforeDockedTurn));
    expect(find.text('Score library'), findsOneWidget);
    await tester.tap(find.byTooltip('Add to setlist').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assignment test'));
    await waitUntil(
      () => find.text('Score added to setlist.').evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      final library = ScoreLibrary(NativeLibraryStorage(directory: root));
      await library.load();
      final setlist = library.setlists.firstWhere(
        (list) => list.id == 'auto-scroll',
      );
      await library.updatePreferences({
        'scoreTabs': setlist.scores,
        'scoreTabPages': {setlist.scores.last: 2},
        'activeScoreTab': setlist.scores.last,
      });
    });
    await tester.pumpWidget(const EncoreSheets());
    InputChip tab(String title) =>
        tester.widget<InputChip>(find.widgetWithText(InputChip, title));
    await waitUntil(
      () =>
          find.byType(PdfViewer).evaluate().isNotEmpty &&
          viewer().controller!.isReady &&
          find
              .widgetWithText(InputChip, 'Transition second')
              .evaluate()
              .isNotEmpty &&
          tab('Transition second').selected &&
          find.text('2 / 3').evaluate().isNotEmpty,
    );
    tab('Transition second').onDeleted!();
    await waitUntil(
      () =>
          viewer().controller!.isReady &&
          tab('Transition first').selected &&
          find
              .widgetWithText(InputChip, 'Transition second')
              .evaluate()
              .isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      final deleted = await tester.runAsync(() async {
        try {
          if (await root.exists()) await root.delete(recursive: true);
          return true;
        } on FileSystemException catch (error) {
          if (!Platform.isWindows ||
              !const {5, 32, 145}.contains(error.osError?.errorCode)) {
            rethrow;
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return false;
        }
      });
      if (deleted == true) break;
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  test('scroll settings round-trip and older scores inherit the default', () {
    final global = const ReaderPreferences().copyWith(
      scrollMode: ReaderScrollMode.fitWidth,
      autoScrollSeconds: 35,
      autoScrollSetlist: false,
    );
    final preferences = ReaderPreferences.fromJson(global.toJson());
    expect(preferences.autoScrollSeconds, 35);
    expect(preferences.autoScrollSetlist, isFalse);
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
