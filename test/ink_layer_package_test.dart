import 'package:encoresheets/ink_layer_package.dart';
import 'package:encoresheets/page_ink.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transfers only the selected layer into the matching score', () {
    const mark = {
      'tool': 'pen',
      'points': [
        [.1, .2],
        [.3, .4],
      ],
    };
    final bytes = encodeInkLayer(defaultInkLayer, 'source', {
      '1': [
        mark,
        {...mark, 'layer': 'private'},
      ],
      '2': [
        {...mark, 'layer': 'private'},
      ],
    });
    final imported = decodeInkLayer(
      bytes,
      scoreDigest: 'source',
      pageCount: 2,
      layerId: 'incoming',
    );
    expect(imported.name, defaultInkLayer.name);
    expect(imported.pages, {
      1: [
        {...mark, 'layer': 'incoming'},
      ],
    });
    expect(
      () => decodeInkLayer(
        bytes,
        scoreDigest: 'different-score',
        pageCount: 2,
        layerId: 'incoming',
      ),
      throwsFormatException,
    );
  });
}
