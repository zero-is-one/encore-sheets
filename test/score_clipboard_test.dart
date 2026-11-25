import 'package:encoresheets/score_clipboard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the clipboard only accepts delimited, structured score entries', () {
    expect(
      parseScoreClipboard(
        'encoresheets:clipboard:{"scope":"box","id":"42","name":"Étude.pdf","move":true}',
      ),
      (scope: 'box', id: '42', name: 'Étude.pdf', move: true),
    );
    expect(parseScoreClipboard('Étude.pdf'), isNull);
    expect(parseScoreClipboard('encoresheets:clipboard:{'), isNull);
    expect(
      parseScoreClipboard(
        'encoresheets:clipboard:{"scope":"box","id":"","name":"Étude.pdf","move":true}',
      ),
      isNull,
    );
  });
}
