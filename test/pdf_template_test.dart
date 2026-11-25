import 'dart:io';

import 'package:encoresheets/pdf_template.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;

  test('creates the requested number and size of staff-paper pages', () async {
    final bytes = await createTemplatePdf((
      title: 'Grand staff',
      style: ScoreTemplate.grandStaff,
      pages: 3,
      letter: true,
    ));
    final pdf = await PdfDocument.openData(bytes);
    addTearDown(pdf.dispose);
    expect(pdf.pages, hasLength(3));
    expect(pdf.pages.first.width, closeTo(612, 1));
    expect(pdf.pages.first.height, closeTo(792, 1));
  });
}
