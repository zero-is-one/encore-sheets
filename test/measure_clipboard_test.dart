import 'dart:io';
import 'dart:ui';

import 'package:encoresheets/measure_clipboard.dart';
import 'package:encoresheets/page_ink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;

  test(
    'captures a PDF region and persists it as an undoable annotation',
    () async {
      final document = await PdfDocument.openFile('assets/first_light.pdf');
      addTearDown(document.dispose);
      final clip = await copyMeasure(
        document.pages.first,
        const Rect.fromLTWH(.1, .1, .5, .2),
      );
      expect(clip.png.take(4), [137, 80, 78, 71]);
      final ink = PageInk();
      addTearDown(ink.dispose);
      ink.pasteRaster(clip.png, const Rect.fromLTWH(.25, .2, .4, .2));
      await ink.prepareImages();
      final saved = ink.snapshot();
      expect(saved.single['raster'], isA<String>());
      ink.undo();
      expect(ink.snapshot(), isEmpty);
      final restored = PageInk(saved: saved);
      addTearDown(restored.dispose);
      await restored.prepareImages();
      expect(restored.snapshot(), saved);
    },
  );
}
