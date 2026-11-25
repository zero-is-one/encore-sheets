import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:encoresheets/text_score_pdf.dart';
import 'package:encoresheets/pdf_text_font.dart';
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
      fontData: await loadPdfTextFont(),
    );
    final document = await PdfDocument.openData(data);
    addTearDown(document.dispose);
    final text = await document.pages.first.loadText();
    return text?.fullText ?? '';
  }

  test('turns text and RTF content into readable PDFs', () async {
    expect(
      await convert(utf8.encode('Étude — Δοκιμή — Репетиция'), 'txt'),
      contains('Étude — Δοκιμή — Репетиция'),
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

  test('converts main text from a legacy Word piece table', () async {
    const message = 'Play quietly.';
    final bytes = ByteData(19 * 512);
    void short(int at, int value) => bytes.setUint16(at, value, Endian.little);
    void long(int at, int value) => bytes.setUint32(at, value, Endian.little);
    int sector(int id) => (id + 1) * 512;

    long(0, 0xe011cfd0);
    long(4, 0xe11ab1a1);
    short(26, 3);
    short(28, 0xfffe);
    short(30, 9);
    short(32, 6);
    long(44, 1);
    long(48, 1);
    long(56, 4096);
    long(60, 0xfffffffe);
    long(68, 0xfffffffe);
    long(76, 0);
    for (var i = 0; i < 128; i++) long(sector(0) + i * 4, 0xffffffff);
    long(sector(0), 0xfffffffd);
    long(sector(0) + 4, 0xfffffffe);
    for (var i = 2; i <= 17; i++) {
      long(sector(0) + i * 4, i == 9 || i == 17 ? 0xfffffffe : i + 1);
    }
    void directory(int offset, String name, int kind, int head, int length) {
      final start = sector(1) + offset;
      for (final (index, code) in name.codeUnits.indexed) {
        short(start + index * 2, code);
      }
      short(start + 64, (name.length + 1) * 2);
      bytes.setUint8(start + 66, kind);
      long(start + 116, head);
      long(start + 120, length);
    }

    directory(0, 'Root Entry', 5, 0xfffffffe, 0);
    directory(128, 'WordDocument', 2, 2, 4096);
    directory(256, '0Table', 2, 10, 4096);
    final word = sector(2);
    short(word, 0xa5ec);
    short(word + 2, 0x00c1);
    short(word + 32, 14);
    short(word + 62, 22);
    long(word + 76, message.length);
    short(word + 152, 34);
    long(word + 422, 21);
    for (final (index, char) in message.codeUnits.indexed) {
      bytes.setUint8(word + 1024 + index, char);
    }
    final table = sector(10);
    bytes.setUint8(table, 2);
    long(table + 1, 16);
    long(table + 9, message.length);
    long(table + 15, 0x40000800);

    expect(await convert(bytes.buffer.asUint8List(), 'doc'), contains(message));
  });
}
