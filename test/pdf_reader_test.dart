import 'dart:io';

import 'package:encoresheets/pdf_assembly.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;

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
