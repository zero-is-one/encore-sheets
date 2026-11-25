import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:encoresheets/text_score_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;

  Future<String> convert(List<int> bytes, String extension) async {
    final data = await convertTextScore(
      Uint8List.fromList(bytes),
      extension: extension,
      title: 'Rehearsal',
    );
    final document = await PdfDocument.openData(data);
    addTearDown(document.dispose);
    final text = await document.pages.first.loadText();
    return text?.fullText ?? '';
  }

  test('turns text and RTF content into readable PDFs', () async {
    expect(
      await convert(utf8.encode('Warm up first.'), 'txt'),
      contains('Warm up first.'),
    );
    final text = await convert(
      utf8.encode(
        r'{\rtf1{\fonttbl{\f0 Ignore;}}\f0 Play softly.\par Then louder.}',
      ),
      'rtf',
    );
    expect(text, contains('Play softly.'));
    expect(text, contains('Then louder.'));
    expect(text, isNot(contains('Ignore')));
  });

  test('extracts and decodes the main Word document part', () async {
    final inputs = Archive()
      ..addFile(
        ArchiveFile.string(
          'word/document.xml',
          '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
              '<w:body><w:p><w:r><w:t>Flute &amp; piano</w:t></w:r></w:p></w:body></w:document>',
        ),
      );
    expect(
      await convert(ZipEncoder().encode(inputs), 'docx'),
      contains('Flute & piano'),
    );
  });
}
