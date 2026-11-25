part of 'library_storage_native.dart';

Map<String, dynamic> _catalog(
  List<ScoreEntry> scores,
  List<Setlist> setlists,
) => {
  'scores': [for (final score in scores) score.toJson()],
  'setlists': [for (final setlist in setlists) setlist.toJson()],
};

void _exportBackup(
  String root,
  String path,
  List<ScoreEntry> scores,
  List<Setlist> setlists,
) {
  final zip = ZipFileEncoder()..create(path);
  try {
    zip.addArchiveFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'format': 'EncoreSheetsLibrary',
          'version': 1,
          ..._catalog(scores, setlists),
        }),
      ),
    );
    for (final (index, score) in scores.indexed) {
      zip.addFileSync(
        File('$root/${score.id}.pdf'),
        'scores/$index.pdf',
        ZipFileEncoder.store,
      );
      final ink = File('$root/${score.id}.ink.json');
      if (ink.existsSync()) zip.addFileSync(ink, 'scores/$index.ink.json');
    }
  } finally {
    zip.closeSync();
  }
}

({List<ScoreEntry> scores, List<Setlist> setlists}) _restoreBackup(
  String root,
  String path,
  List<ScoreEntry> existingScores,
  List<Setlist> existingSetlists,
) {
  final input = InputFileStream(path);
  final written = <File>[];
  try {
    final archive = ZipDecoder().decodeStream(input, verify: true);
    final manifest = _jsonEntry(archive.find('manifest.json'));
    if (manifest['format'] != 'EncoreSheetsLibrary' ||
        manifest['version'] != 1) {
      throw const FormatException('Unsupported library backup');
    }
    final sourceScores = [
      for (final row in manifest['scores'] as List)
        ScoreEntry.fromJson(row as Map<String, dynamic>),
    ];
    final sourceSetlists = [
      for (final row in manifest['setlists'] as List)
        Setlist.fromJson(row as Map<String, dynamic>),
    ];
    final sourceIds = sourceScores.map((score) => score.id).toSet();
    if (sourceIds.length != sourceScores.length ||
        sourceSetlists.map((setlist) => setlist.id).toSet().length !=
            sourceSetlists.length ||
        sourceScores.any(
          (score) => score.page < 1 || score.title.trim().isEmpty,
        ) ||
        sourceSetlists.any(
          (setlist) =>
              setlist.name.trim().isEmpty ||
              setlist.scores.any((id) => !sourceIds.contains(id)),
        )) {
      throw const FormatException('Invalid library backup catalog');
    }

    final ids = existingScores.map((score) => score.id).toSet();
    final mapped = <String, String>{};
    final scores = <ScoreEntry>[];
    var sequence = DateTime.now().microsecondsSinceEpoch;
    for (final (index, old) in sourceScores.indexed) {
      String id;
      do {
        id = '${sequence++}';
      } while (ids.contains(id) ||
          File('$root/$id.pdf').existsSync() ||
          File('$root/$id.ink.json').existsSync());
      ids.add(id);
      mapped[old.id] = id;
      final pdf = archive.find('scores/$index.pdf');
      if (pdf == null || !pdf.isFile || pdf.isSymbolicLink || pdf.size < 5) {
        throw const FormatException('Missing backup PDF');
      }
      final destination = File('$root/$id.pdf');
      written.add(destination);
      final output = OutputFileStream(destination.path);
      try {
        pdf.writeContent(output);
      } finally {
        output.closeSync();
      }
      final handle = destination.openSync();
      try {
        if (!latin1.decode(handle.readSync(1024)).contains('%PDF-')) {
          throw const FormatException('Invalid PDF in backup');
        }
      } finally {
        handle.closeSync();
      }
      final ink = archive.find('scores/$index.ink.json');
      if (ink != null) {
        final pages = _jsonEntry(ink);
        _validateInk(pages);
        final destination = File('$root/$id.ink.json');
        written.add(destination);
        destination.writeAsStringSync(jsonEncode(pages), flush: true);
      }
      scores.add(
        ScoreEntry(
          id: id,
          title: old.title,
          page: old.page,
          openedAt: old.openedAt,
        ),
      );
    }

    final listIds = existingSetlists.map((setlist) => setlist.id).toSet();
    final setlists = <Setlist>[];
    for (final old in sourceSetlists) {
      String id;
      do {
        id = '${sequence++}';
      } while (!listIds.add(id));
      setlists.add(Setlist(id, old.name, old.scores.map((id) => mapped[id]!)));
    }

    final staged = File('$root/catalog.json.tmp');
    written.add(staged);
    staged.writeAsStringSync(
      jsonEncode(
        _catalog(
          [...existingScores, ...scores],
          [...existingSetlists, ...setlists],
        ),
      ),
      flush: true,
    );
    staged.renameSync('$root/catalog.json');
    return (scores: scores, setlists: setlists);
  } catch (_) {
    for (final file in written.reversed) {
      try {
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // Keep the original error. Unpublished files are ignored by the catalog.
      }
    }
    rethrow;
  } finally {
    input.closeSync();
  }
}

Map<String, dynamic> _jsonEntry(ArchiveFile? entry) {
  if (entry == null ||
      !entry.isFile ||
      entry.isSymbolicLink ||
      entry.size > 64 * 1024 * 1024) {
    throw const FormatException('Invalid backup entry');
  }
  return jsonDecode(utf8.decode(entry.content)) as Map<String, dynamic>;
}

void _validateInk(Map<String, dynamic> pages) {
  for (final MapEntry(key: page, value: strokes) in pages.entries) {
    if ((int.tryParse(page) ?? 0) < 1 || strokes is! List) {
      throw const FormatException('Invalid annotation page');
    }
    for (final stroke in strokes) {
      if (stroke is! Map ||
          (stroke['tool'] != 'pen' && stroke['tool'] != 'highlighter') ||
          stroke['points'] is! List ||
          (stroke['points'] as List).isEmpty) {
        throw const FormatException('Invalid annotation stroke');
      }
      for (final point in stroke['points'] as List) {
        if (point is! List ||
            point.length != 2 ||
            point.any(
              (value) =>
                  value is! num || !value.isFinite || value < 0 || value > 1,
            )) {
          throw const FormatException('Invalid annotation point');
        }
      }
    }
  }
}
