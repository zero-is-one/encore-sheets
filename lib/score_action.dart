enum ScoreActionKind {
  score('Open score'),
  note('Open page note'),
  audio('Play or pause linked audio'),
  tempo('Set metronome tempo'),
  pitch('Play reference pitch'),
  midi('Send MIDI message');

  const ScoreActionKind(this.label);
  final String label;
}

class ScoreAction {
  const ScoreAction({
    required this.title,
    required this.page,
    required this.x,
    required this.y,
    required this.color,
    required this.kind,
    this.selection,
    this.parameter,
  });

  final String title;
  final int page;
  final double x;
  final double y;
  final int color;
  final ScoreActionKind kind;
  final String? selection;
  final String? parameter;

  static List<int>? midiBytes(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.any((part) => !RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(part)))
      return null;
    final bytes = parts.map((part) => int.parse(part, radix: 16)).toList();
    final status = bytes.first;
    if (status < 0x80 ||
        status >= 0xf0 ||
        bytes.skip(1).any((byte) => byte >= 0x80))
      return null;
    final kind = status & 0xf0;
    return bytes.length == (kind == 0xc0 || kind == 0xd0 ? 2 : 3)
        ? bytes
        : null;
  }

  static bool validParameter(ScoreActionKind kind, String? text) {
    final number = int.tryParse(text ?? '');
    return switch (kind) {
      ScoreActionKind.tempo => number != null && number >= 25 && number <= 280,
      ScoreActionKind.pitch => number != null && number >= 48 && number <= 84,
      ScoreActionKind.midi => midiBytes(text ?? '') != null,
      _ => true,
    };
  }

  ScoreAction reposition(int page, double x, double y) => ScoreAction(
    title: title,
    page: page,
    x: x,
    y: y,
    color: color,
    kind: kind,
    selection: selection,
    parameter: parameter,
  );

  ScoreAction retarget(String id) => ScoreAction(
    title: title,
    page: page,
    x: x,
    y: y,
    color: color,
    kind: kind,
    selection: id,
    parameter: parameter,
  );

  static ScoreAction? fromJson(Object? value) {
    if (value
        case {
          'title': final String title,
          'page': final int page,
          'x': final num x,
          'y': final num y,
          'color': final int color,
          'kind': final String name,
        }
        when title.trim().isNotEmpty &&
            page > 0 &&
            x >= 0 &&
            x <= 1 &&
            y >= 0 &&
            y <= 1 &&
            color >= 0 &&
            color <= 0xffffffff) {
      final kind = ScoreActionKind.values
          .where((item) => item.name == name)
          .firstOrNull;
      final selection = value['selection'];
      final parameter = value['parameter'] is String
          ? value['parameter'] as String
          : null;
      if (kind == null || kind == ScoreActionKind.score && selection is! String)
        return null;
      if (!validParameter(kind, parameter)) return null;
      return ScoreAction(
        title: title,
        page: page,
        x: x.toDouble(),
        y: y.toDouble(),
        color: color,
        kind: kind,
        selection: selection is String ? selection : null,
        parameter: parameter,
      );
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'page': page,
    'x': x,
    'y': y,
    'color': color,
    'kind': kind.name,
    if (selection != null) 'selection': selection,
    if (parameter != null) 'parameter': parameter,
  };
}
