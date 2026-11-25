import 'dart:convert';

import 'package:file_selector/file_selector.dart';

import 'pdf_assembly.dart';
import 'score_library.dart';

enum SetlistShareFormat {
  text('Text list'),
  pdf('Combined PDF'),
  withScores('Editable package with scores'),
  references('Editable package with placeholders');

  const SetlistShareFormat(this.label);
  final String label;
}

Future<XFile> exportSetlist(
  ScoreLibrary library,
  Setlist setlist,
  SetlistShareFormat format,
) async {
  final safeName = setlist.name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .trim();
  final name = safeName.isEmpty ? 'Setlist' : safeName;
  if (format == SetlistShareFormat.text) {
    final text = [
      setlist.name,
      if (setlist.label.isNotEmpty) setlist.label,
      if (setlist.notes.isNotEmpty) setlist.notes,
      '',
      for (final (index, id) in setlist.scores.indexed)
        '${index + 1}. ${_setlistItemTitle(library, setlist, id)}',
    ].join('\n');
    return XFile.fromData(
      utf8.encode(text),
      name: '$name.txt',
      mimeType: 'text/plain',
    );
  }
  if (format == SetlistShareFormat.pdf) {
    final sources = <({XFile file, int? first, int? last})>[];
    for (final selection in setlist.scores) {
      final item = library.lookupSelection(selection);
      if (item == null)
        throw StateError('Resolve missing scores before compiling a PDF.');
      sources.add((
        file: await library.storage.openScore(item.$1.id),
        first: item.$2?.page,
        last: item.$2?.endPage,
      ));
    }
    return assemblePdf('$name.pdf', sources);
  }
  return library.createSetlistPackage(
    setlist,
    name: name,
    includeScores: format == SetlistShareFormat.withScores,
  );
}

String _setlistItemTitle(ScoreLibrary library, Setlist setlist, String id) {
  final item = library.lookupSelection(id);
  return item?.$2?.title ??
      item?.$1.title ??
      setlist.placeholders[id] ??
      'Missing score';
}
