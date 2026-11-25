import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opens the bundled score and renders its first page offline', () async {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
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
