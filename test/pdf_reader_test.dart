import 'dart:io';

import 'package:encoresheets/bookmark_import.dart';
import 'package:encoresheets/pdf_assembly.dart';
import 'package:encoresheets/page_crop.dart';
import 'package:encoresheets/pdf_export.dart';
import 'package:encoresheets/pdf_rearrange.dart';
import 'package:encoresheets/reflow_screen.dart';
import 'package:encoresheets/score_library.dart';
import 'package:encoresheets/score_text_search.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show ListView, MaterialApp;
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;

  testWidgets('reflow advances hands-free and pauses in place', (tester) async {
    final document = (await tester.runAsync(
      () => openRearrangeDocument(XFile('assets/first_light.pdf')),
    ))!;
    addTearDown(document.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ReflowScreen(
          document: document,
          first: 1,
          last: 3,
          initialPage: 1,
          saved: [
            for (var page = 1; page <= 3; page++)
              (page: page, top: .2, bottom: .3),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Continuous scroll'));
    await tester.pump();
    final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
    expect(scroll.offset, 0);
    await tester.tap(find.text('Play'));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(scroll.offset, greaterThan(0));
    await tester.tap(find.text('Pause'));
    await tester.pump();
    final paused = scroll.offset;
    await tester.pump(const Duration(seconds: 1));
    expect(scroll.offset, paused);
    await tester.pumpWidget(const MaterialApp());
  });

  test(
    'imports bookmark tables with quoted fields, ranges, and matched pages',
    () async {
      final document = await openRearrangeDocument(
        XFile('assets/first_light.pdf'),
      );
      addTearDown(document.dispose);
      final index = BookmarkPageIndex(document);
      final result = await index.importTable(
        'Title,Start page,End page\r\n"Part, one",2,3\r\nFirst Light,,\r\nInvalid,99,',
        ',',
      );
      expect(result.skipped, 1);
      expect(result.candidates.first, (
        title: 'Part, one',
        page: 2,
        endPage: 3,
      ));
      expect(result.candidates.last.page, 1);
      expect(
        parseBookmarkTable('Page\tTitle\n1\t"Second ""piece"""\n', '\t').last,
        ['1', 'Second "piece"'],
      );
    },
  );

  test('finds PDF text, annotation text, and page notes by page', () async {
    final document = await openRearrangeDocument(
      XFile('assets/first_light.pdf'),
    );
    addTearDown(document.dispose);
    final matches = await searchScoreText(
      document: document,
      query: 'first  LIGHT',
      firstPage: 1,
      lastPage: 2,
      notes: {2: 'First Light at half tempo'},
      annotations: {
        '1': [
          {'tool': 'text', 'text': 'Play First Light as written'},
        ],
      },
    ).toList();
    expect(
      matches.any(
        (match) => match.source == ScoreTextSource.pdf && match.page == 1,
      ),
      isTrue,
    );
    expect(
      matches.any(
        (match) =>
            match.source == ScoreTextSource.annotation && match.page == 1,
      ),
      isTrue,
    );
    expect(
      matches.any(
        (match) => match.source == ScoreTextSource.note && match.page == 2,
      ),
      isTrue,
    );
  });

  test('finds content margins for the bundled score', () async {
    final document = await openRearrangeDocument(
      XFile('assets/first_light.pdf'),
    );
    try {
      final crop = await detectPageMargins(document.pages.first);
      expect(crop.isIdentity, isFalse);
      expect(crop.pdfBounds(document.pages.first).isNotEmpty, isTrue);
      expect(PageCrop.fromJson(crop.toJson())?.toJson(), crop.toJson());
    } finally {
      await document.dispose();
    }
  });

  test('rearranges and rotates PDF pages and remaps saved marks', () async {
    final document = await openRearrangeDocument(
      XFile('assets/first_light.pdf'),
    );
    addTearDown(document.dispose);
    final pages = [
      EditedPdfPage(document.pages[1], originalPage: 2).rotate(),
      EditedPdfPage(document.pages[0], originalPage: 1),
      EditedPdfPage(document.pages[1], originalPage: 2),
    ];
    final remapped = remapScorePages(
      ScoreEntry(
        id: 'source',
        title: 'Original',
        openedAt: DateTime.now(),
        page: 2,
        flags: [2],
        bookmarks: [const ScoreBookmark('b', 'Part', 1, endPage: 2)],
        jumps: [
          const ScoreJump(
            'Repeat',
            JumpPoint(2, .2, .25),
            JumpPoint(1, .4, .1),
          ),
        ],
      ),
      {
        '2': [
          {
            'tool': 'pen',
            'points': [
              [.2, .25],
            ],
          },
        ],
      },
      pages,
    );
    expect(remapped.score.flags, [1, 3]);
    expect(remapped.score.jumps.first.source.toJson(), {
      'page': 1,
      'x': .75,
      'y': .2,
    });
    expect(remapped.score.jumps.first.target.page, 2);
    expect(remapped.score.bookmarks.single.endPage, 3);
    expect(remapped.annotations['1'].single['points'], [
      [.75, .2],
    ]);
    final file = await writeRearrangedPdf('rearranged.pdf', pages);
    final reopened = await PdfDocument.openData(
      await file.readAsBytes(),
      sourceName: file.name,
    );
    addTearDown(reopened.dispose);
    expect(reopened.pages, hasLength(3));
    expect(reopened.pages.first.width, closeTo(document.pages[1].height, .01));
  });

  test(
    'exports original bytes and renders a flattened single-page range',
    () async {
      final source = XFile('assets/first_light.pdf');
      final original = await exportScorePdf(
        source: source,
        name: 'original.pdf',
        first: 1,
        last: 3,
        pageCount: 3,
      );
      expect(original, await source.readAsBytes());
      final flattened = await exportScorePdf(
        source: source,
        name: 'annotated.pdf',
        first: 2,
        last: 2,
        pageCount: 3,
        annotations: {
          '2': [
            {
              'tool': 'pen',
              'color': 0xffbb3311,
              'points': [
                [.14, .12],
                [.4, .12],
              ],
            },
          ],
        },
      );
      final document = await PdfDocument.openData(
        flattened,
        sourceName: 'annotated.pdf',
      );
      try {
        expect(document.pages, hasLength(1));
        final image = await document.pages.first.render(
          width: 128,
          height: 166,
        );
        expect(image, isNotNull);
        image?.dispose();
      } finally {
        await document.dispose();
      }
    },
  );

  test(
    'combines page ranges into a new PDF and rejects invalid ranges',
    () async {
      final source = XFile('assets/first_light.pdf');
      final result = await assemblePdf('combined.pdf', [
        (file: source, first: 2, last: 3),
        (file: source, first: 1, last: 1),
      ]);
      final document = await PdfDocument.openData(
        await result.readAsBytes(),
        sourceName: result.name,
      );
      try {
        expect(document.pages, hasLength(3));
        final image = await document.pages.first.render(
          width: 128,
          height: 166,
        );
        expect(image, isNotNull);
        image?.dispose();
      } finally {
        await document.dispose();
      }
      await expectLater(
        assemblePdf('invalid.pdf', [(file: source, first: 2, last: 4)]),
        throwsRangeError,
      );
    },
  );

  test('opens the bundled score and renders its first page offline', () async {
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openFile('assets/first_light.pdf');
    try {
      expect(document.pages, hasLength(3));
      final image = await document.pages.first.render(width: 128, height: 166);
      expect(image, isNotNull);
      image?.dispose();
    } finally {
      await document.dispose();
    }
  });
}
