part of 'library_storage_native.dart';

String _archiveFormat(LibraryArchive kind) => switch (kind) {
  LibraryArchive.library => 'EncoreSheetsLibrary',
  LibraryArchive.score => 'EncoreSheetsScore',
  LibraryArchive.setlist => 'EncoreSheetsSetlist',
};

Map<String, dynamic> _catalog(
  List<ScoreEntry> scores,
  List<Setlist> setlists, {
  Map<String, dynamic>? preferences,
}) => {
  'scores': [for (final score in scores) score.toJson()],
  'setlists': [for (final setlist in setlists) setlist.toJson()],
  if (preferences != null) 'preferences': preferences,
};

void _exportBackup(
  String root,
  String path,
  List<ScoreEntry> scores,
  List<Setlist> setlists, {
  LibraryArchive kind = LibraryArchive.library,
  bool includeScores = true,
  Map<String, dynamic>? preferences,
}) {
  final zip = ZipFileEncoder()..create(path);
  try {
    zip.addArchiveFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'format': _archiveFormat(kind),
          'version': 1,
          if (!includeScores) 'referencesOnly': true,
          ..._catalog(scores, setlists, preferences: preferences),
        }),
      ),
    );
    if (!includeScores) return;
    for (final (index, score) in scores.indexed) {
      zip.addFileSync(
        File('$root/${score.storedPdfId}.pdf'),
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
  List<Setlist> existingSetlists, {
  LibraryArchive kind = LibraryArchive.library,
  required Map<String, dynamic> existingPreferences,
}) {
  final input = InputFileStream(path);
  final written = <File>[];
  try {
    final archive = ZipDecoder().decodeStream(input, verify: true);
    final manifest = _jsonEntry(archive.find('manifest.json'));
    if (manifest['format'] != _archiveFormat(kind) ||
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
    final savedPreferences = manifest['preferences'];
    if (savedPreferences != null && savedPreferences is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup preferences');
    }
    if (kind == LibraryArchive.score &&
        (sourceScores.length != 1 ||
            sourceSetlists.isNotEmpty ||
            sourceScores.single.deletedAt != null)) {
      throw const FormatException('Invalid editable score package');
    }
    if (kind == LibraryArchive.setlist && sourceSetlists.length != 1) {
      throw const FormatException('Invalid editable setlist package');
    }
    final referencesOnly =
        kind == LibraryArchive.setlist && manifest['referencesOnly'] == true;
    final sourceIds = sourceScores.map((score) => score.id).toSet();
    final validSelections = {
      ...sourceIds,
      for (final score in sourceScores)
        for (final bookmark in score.bookmarks.where((item) => item.isItem))
          bookmark.selectionId(score.id),
    };
    if (sourceIds.length != sourceScores.length ||
        sourceSetlists.map((setlist) => setlist.id).toSet().length !=
            sourceSetlists.length ||
        sourceScores.any(
          (score) => score.page < 1 || score.title.trim().isEmpty,
        ) ||
        sourceSetlists.any(
          (setlist) =>
              setlist.name.trim().isEmpty ||
              setlist.scores.any(
                (id) =>
                    !validSelections.contains(id) &&
                    !setlist.placeholders.containsKey(id),
              ),
        )) {
      throw const FormatException('Invalid library backup catalog');
    }

    final ids = existingScores.map((score) => score.id).toSet();
    final mapped = <String, String>{};
    final sourceTitles = <String, String>{
      for (final score in sourceScores) score.id: score.title,
      for (final score in sourceScores)
        for (final item in score.bookmarks.where((item) => item.isItem))
          item.selectionId(score.id): item.title,
    };
    final scores = <ScoreEntry>[];
    var sequence = DateTime.now().microsecondsSinceEpoch;
    for (final (index, old) in sourceScores.indexed) {
      if (referencesOnly) {
        final matching = existingScores
            .where(
              (score) =>
                  score.deletedAt == null &&
                  (score.id == old.id ||
                      score.title.toLowerCase() == old.title.toLowerCase() &&
                          score.metadata['composer']?.toLowerCase() ==
                              old.metadata['composer']?.toLowerCase()),
            )
            .toList();
        final target =
            matching.where((score) => score.id == old.id).firstOrNull ??
            (matching.length == 1 ? matching.single : null);
        if (target == null) continue;
        mapped[old.id] = target.id;
        for (final bookmark in old.bookmarks.where((item) => item.isItem)) {
          final match = target.bookmarks
              .where(
                (item) =>
                    item.isItem &&
                    item.title == bookmark.title &&
                    item.page == bookmark.page &&
                    item.endPage == bookmark.endPage,
              )
              .firstOrNull;
          if (match != null) {
            mapped[bookmark.selectionId(old.id)] = match.selectionId(target.id);
          }
        }
        continue;
      }
      String id;
      do {
        id = '${sequence++}';
      } while (ids.contains(id) ||
          File('$root/$id.pdf').existsSync() ||
          File('$root/$id.ink.json').existsSync());
      ids.add(id);
      mapped[old.id] = id;
      for (final bookmark in old.bookmarks.where((item) => item.isItem)) {
        mapped[bookmark.selectionId(old.id)] = bookmark.selectionId(id);
      }
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
      scores.add(old.copyWith(id: id, detachPdf: true));
    }

    for (final (index, score) in scores.indexed) {
      if (score.actions.isEmpty) continue;
      scores[index] = score.copyWith(
        actions: [
          for (final action in score.actions)
            if (mapped[action.selection] case final target?)
              action.retarget(target)
            else
              action,
        ],
      );
    }
    final listIds = existingSetlists.map((setlist) => setlist.id).toSet();
    final setlists = <Setlist>[];
    for (final old in sourceSetlists) {
      String id;
      do {
        id = '${sequence++}';
      } while (!listIds.add(id));
      final unresolved = <String, String>{};
      final names = <String, String>{};
      final selections = <String>[];
      for (final selection in old.scores) {
        if (mapped[selection] case final match?) {
          selections.add(match);
        } else {
          final key = unresolved.putIfAbsent(
            selection,
            () => 'missing-$id-${unresolved.length}',
          );
          names[key] =
              old.placeholders[selection] ??
              sourceTitles[selection] ??
              'Missing score';
          selections.add(key);
        }
      }
      setlists.add(
        old.copyWith(id: id, scores: selections, placeholders: names),
      );
    }

    final staged = File('$root/catalog.json.tmp');
    final preferences = {
      if (kind == LibraryArchive.library &&
          existingScores.isEmpty &&
          savedPreferences is Map)
        ...savedPreferences.cast<String, dynamic>(),
      ...existingPreferences,
    };
    if (kind == LibraryArchive.library && savedPreferences is Map) {
      Iterable<String> values(Object? value) =>
          value is List ? value.whereType<String>() : const [];
      for (final key in ['scoreCollections', 'personalStamps']) {
        preferences[key] = {
          ...values(existingPreferences[key]),
          ...values(savedPreferences[key]),
        }.toList();
      }
      preferences['scoreTabs'] = {
        ...values(existingPreferences['scoreTabs']),
        ...values(savedPreferences['scoreTabs'])
            .map((id) => mapped[id])
            .whereType<String>(),
      }.toList();
    }
    written.add(staged);
    staged.writeAsStringSync(
      jsonEncode(
        _catalog(
          [...existingScores, ...scores],
          [...existingSetlists, ...setlists],
          preferences: preferences,
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
  final layers = <String>{};
  if (pages.containsKey('layers')) {
    final data = pages['layers'];
    if (data is! List || data.isEmpty) {
      throw const FormatException('Invalid annotation layers');
    }
    var activeCount = 0;
    for (final layer in data) {
      if (layer
          case {
            'id': final String id,
            'name': final String name,
            'visible': final bool visible,
          }
          when id.isNotEmpty && name.isNotEmpty && layers.add(id)) {
        if (layer['active'] == true && (!visible || ++activeCount > 1)) {
          throw const FormatException('Invalid active annotation layer');
        }
      } else {
        throw const FormatException('Invalid annotation layer');
      }
    }
  } else {
    layers.add('base');
  }
  for (final MapEntry(key: page, value: strokes) in pages.entries) {
    if (page == 'layers') continue;
    if ((int.tryParse(page) ?? 0) < 1 || strokes is! List) {
      throw const FormatException('Invalid annotation page');
    }
    for (final stroke in strokes) {
      if (stroke is! Map ||
          !const {'pen', 'highlighter', 'text'}.contains(stroke['tool']) ||
          stroke['points'] is! List ||
          (stroke['points'] as List).isEmpty) {
        throw const FormatException('Invalid annotation stroke');
      }
      final text = stroke['text'];
      if (!layers.contains(stroke['layer'] ?? 'base')) {
        throw const FormatException('Unknown annotation layer');
      }
      if (stroke['tool'] == 'text'
          ? text is! String || text.isEmpty || text.length > 2000
          : text != null) {
        throw const FormatException('Invalid annotation text');
      }
      final width = stroke['width'];
      final color = stroke['color'];
      final sampleWidths = stroke['sampleWidths'];
      if (sampleWidths != null &&
          (stroke['tool'] != 'pen' ||
              sampleWidths is! List ||
              sampleWidths.length != (stroke['points'] as List).length ||
              sampleWidths.any(
                (value) =>
                    value is! num ||
                    !value.isFinite ||
                    value <= 0 ||
                    value > .1,
              ))) {
        throw const FormatException('Invalid stylus widths');
      }
      if ((width != null &&
              (width is! num || !width.isFinite || width <= 0 || width > .1)) ||
          (color != null &&
              (color is! int || color < 0 || color > 0xffffffff))) {
        throw const FormatException('Invalid annotation style');
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
