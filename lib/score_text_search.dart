import 'dart:math' as math;

import 'package:pdfrx/pdfrx.dart';

enum ScoreTextSource {
  pdf('PDF text'),
  annotation('Annotation'),
  note('Page note');

  const ScoreTextSource(this.label);
  final String label;
}

typedef ScoreTextMatch = ({int page, ScoreTextSource source, String excerpt});

Stream<ScoreTextMatch> searchScoreText({
  required PdfDocument document,
  required String query,
  required int firstPage,
  required int lastPage,
  required Map<String, dynamic> annotations,
  required Map<int, String> notes,
}) async* {
  final phrase = query.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (phrase.isEmpty) return;
  final pattern = RegExp(
    RegExp.escape(phrase),
    caseSensitive: false,
    unicode: true,
  );

  for (var page = firstPage; page <= lastPage; page++) {
    final entries = <(ScoreTextSource, String)>[
      if (notes[page] case final note?) (ScoreTextSource.note, note),
      if (annotations['$page'] case final List strokes)
        for (final mark in strokes)
          if (mark case {'tool': 'text', 'text': final String text})
            (ScoreTextSource.annotation, text),
      if (await document.pages[page - 1].loadText() case final content?)
        (ScoreTextSource.pdf, content.fullText),
    ];
    for (final (source, text) in entries) {
      final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (pattern.firstMatch(clean) case final match?) {
        final start = math.max(0, match.start - 55);
        final end = math.min(clean.length, match.end + 75);
        yield (
          page: page,
          source: source,
          excerpt:
              '${start > 0 ? '…' : ''}${clean.substring(start, end)}${end < clean.length ? '…' : ''}',
        );
      }
    }
  }
}
