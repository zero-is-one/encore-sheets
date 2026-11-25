enum ScoreActionKind {
  score('Open score'),
  note('Open page note');

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
  });

  final String title;
  final int page;
  final double x;
  final double y;
  final int color;
  final ScoreActionKind kind;
  final String? selection;

  ScoreAction reposition(int page, double x, double y) => ScoreAction(
    title: title,
    page: page,
    x: x,
    y: y,
    color: color,
    kind: kind,
    selection: selection,
  );

  ScoreAction retarget(String id) => ScoreAction(
    title: title,
    page: page,
    x: x,
    y: y,
    color: color,
    kind: kind,
    selection: id,
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
      if (kind == null || kind == ScoreActionKind.score && selection is! String)
        return null;
      return ScoreAction(
        title: title,
        page: page,
        x: x.toDouble(),
        y: y.toDouble(),
        color: color,
        kind: kind,
        selection: selection is String ? selection : null,
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
  };
}
