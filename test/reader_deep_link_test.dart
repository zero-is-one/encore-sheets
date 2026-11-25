import 'package:encoresheets/reader_deep_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only accepts read navigation to known EncoreSheets destinations', () {
    expect(parseReaderLink('encoresheets://score/42?page=8'), (
      target: ReaderLinkTarget.score,
      id: '42',
      name: null,
      page: 8,
    ));
    expect(
      parseReaderLink('encoresheets://setlist?name=Friday%20Night')?.name,
      'Friday Night',
    );
    expect(parseReaderLink('encoresheets://score/42/43'), isNull);
    expect(parseReaderLink('encoresheets://score/42?page=0'), isNull);
    expect(parseReaderLink('encoresheets://delete/42'), isNull);
    expect(parseReaderLink('https://score/42'), isNull);
  });
}
