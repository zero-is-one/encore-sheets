import 'dart:convert';

import 'package:flutter/services.dart';

typedef ScoreClipboard = ({String scope, String id, String name, bool move});

const _prefix = 'encoresheets:clipboard:';

Future<void> writeScoreClipboard(ScoreClipboard item) => Clipboard.setData(
  ClipboardData(
    text:
        '$_prefix${jsonEncode({'scope': item.scope, 'id': item.id, 'name': item.name, 'move': item.move})}',
  ),
);

Future<ScoreClipboard?> readScoreClipboard() async =>
    parseScoreClipboard((await Clipboard.getData(Clipboard.kTextPlain))?.text);

ScoreClipboard? parseScoreClipboard(String? payload) {
  if (payload == null ||
      payload.length > 4096 ||
      !payload.startsWith(_prefix)) {
    return null;
  }
  try {
    final data = jsonDecode(payload.substring(_prefix.length));
    if (data
        case {
          'scope': final String scope,
          'id': final String id,
          'name': final String name,
          'move': final bool move,
        }
        when id.isNotEmpty && name.isNotEmpty) {
      return (scope: scope, id: id, name: name, move: move);
    }
  } on FormatException {
    return null;
  }
  return null;
}

Future<void> clearMovedScoreClipboard(ScoreClipboard item) async {
  if (item.move && await readScoreClipboard() == item) {
    await Clipboard.setData(const ClipboardData(text: ''));
  }
}
