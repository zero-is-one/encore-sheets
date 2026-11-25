import 'package:encoresheets/embedded_pdf_info.dart';
import 'package:encoresheets/reader_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pdf;

void main() {
  test(
    'reads PDF title, author, subject and keywords from a real document',
    () async {
      final file = pdf.Document(
        title: 'Étude',
        author: 'Composer',
        subject: 'Op. 12',
        keywords: 'rehearsal, piano',
      );
      file.addPage(pdf.Page(build: (_) => pdf.SizedBox()));
      expect(extractEmbeddedPdfInfo(await file.save()), {
        'Title': 'Étude',
        'Author': 'Composer',
        'Subject': 'Op. 12',
        'Keywords': 'rehearsal, piano',
      });
    },
  );

  test('legacy reader settings preserve annotations and links', () {
    final legacy = ReaderPreferences.fromJson({});
    expect(legacy.embeddedPdfContent, EmbeddedPdfContent.all);
    expect(legacy.embeddedPdfLinks, isTrue);
    final changed = legacy.copyWith(
      embeddedPdfContent: EmbeddedPdfContent.hidden,
      embeddedPdfLinks: false,
    );
    expect(
      ReaderPreferences.fromJson(changed.toJson()).embeddedPdfContent,
      EmbeddedPdfContent.hidden,
    );
    expect(
      ReaderPreferences.fromJson(changed.toJson()).embeddedPdfLinks,
      isFalse,
    );
  });
}
