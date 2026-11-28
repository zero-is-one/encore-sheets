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

Map<String, dynamic> _decodeCatalog(String contents) {
  try {
    final catalog = jsonDecode(contents) as Map<String, dynamic>;
    final scores = (catalog['scores'] as List)
        .map((row) => ScoreEntry.fromJson(row as Map<String, dynamic>))
        .toList();
    final setlists = (catalog['setlists'] as List)
        .map((row) => Setlist.fromJson(row as Map<String, dynamic>))
        .toList();
    final safeId = RegExp(r'^[a-zA-Z0-9-]{1,80}$');
    if (scores.any((score) => !safeId.hasMatch(score.id) || score.page < 1) ||
        scores.map((score) => score.id).toSet().length != scores.length ||
        setlists.map((list) => list.id).toSet().length != setlists.length ||
        catalog['preferences'] != null &&
            catalog['preferences'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid library catalog');
    }
    return catalog;
  } on TypeError {
    throw const FormatException('Invalid library catalog');
  }
}

String _catalogDigest(String contents) =>
    sha256.convert(utf8.encode(contents)).toString();

String _snapshotContents(String catalog) => jsonEncode({
  'version': 1,
  'catalog': catalog,
  'sha256': _catalogDigest(catalog),
});

String? _verifiedSnapshot(File file) {
  if (!file.existsSync()) return null;
  try {
    final envelope = jsonDecode(file.readAsStringSync());
    if (envelope
        case {
          'version': 1,
          'catalog': final String data,
          'sha256': final String digest,
        }
        when _catalogDigest(data) == digest) {
      _decodeCatalog(data);
      return data;
    }
  } on FormatException {
    // The other generation may still be intact.
  } on FileSystemException {
    // A missing or unreadable snapshot cannot be used.
  }
  return null;
}

void _atomicCatalogWrite(File file, String contents) {
  final staging = file.parent.createTempSync('.catalog-');
  try {
    final staged = File('${staging.path}/data');
    staged.writeAsStringSync(contents, flush: true);
    for (var attempt = 0; ; attempt++) {
      try {
        staged.renameSync(file.path);
        break;
      } on PathAccessException {
        if (!Platform.isWindows || attempt >= 4) rethrow;
        // Windows can deny replacement while a reader has the file open.
        sleep(const Duration(milliseconds: 20));
      }
    }
  } finally {
    try {
      staging.deleteSync(recursive: true);
    } on FileSystemException {
      // A completed rename remains committed.
    }
  }
}

void _commitCatalog(String root, Map<String, dynamic> catalog) {
  final data = jsonEncode(catalog);
  final latest = File('$root/catalog-recovery.json');
  final prior = File('$root/catalog-recovery-previous.json');
  _atomicCatalogWrite(File('$root/catalog.json'), data);
  try {
    if (_verifiedSnapshot(latest) != null) {
      _atomicCatalogWrite(prior, latest.readAsStringSync());
    }
    _atomicCatalogWrite(latest, _snapshotContents(data));
  } on FileSystemException {
    // The live catalog is already committed. Keep the last verified snapshot.
  }
}

void _seedSnapshot(String root) {
  final live = File('$root/catalog.json');
  final snapshot = File('$root/catalog-recovery.json');
  if (!live.existsSync() || snapshot.existsSync()) return;
  try {
    final data = live.readAsStringSync();
    _decodeCatalog(data);
    _atomicCatalogWrite(snapshot, _snapshotContents(data));
  } on FormatException {
    // Never create a recovery snapshot from a corrupt catalog.
  } on FileSystemException {
    // The app can still open the live catalog.
  }
}

Map<String, dynamic>? _recoverCatalog(String root) {
  final live = File('$root/catalog.json');
  // A write may have repaired the live file since the caller checked it.
  if (live.existsSync()) {
    try {
      return _decodeCatalog(live.readAsStringSync());
    } on FormatException {
      // Check the recovery copies below.
    } on FileSystemException {
      // Check the recovery copies if the live file cannot be read.
    }
  }
  for (final name in [
    'catalog-recovery.json',
    'catalog-recovery-previous.json',
  ]) {
    final contents = _verifiedSnapshot(File('$root/$name'));
    if (contents == null) continue;
    final catalog = _decodeCatalog(contents);
    final scores = (catalog['scores'] as List).map(
      (row) => ScoreEntry.fromJson(row as Map<String, dynamic>),
    );
    if (scores.any(
      (score) => !File('$root/${score.storedPdfId}.pdf').existsSync(),
    )) {
      continue;
    }
    _atomicCatalogWrite(live, contents);
    return catalog;
  }
  if (live.existsSync() ||
      File('$root/catalog-recovery.json').existsSync() ||
      File('$root/catalog-recovery-previous.json').existsSync()) {
    throw const LibraryCatalogRecoveryRequired();
  }
  return null;
}

const _deviceOnlyPreferences = {
  'readerRestrictions',
  'assistantConnection',
  'librarySyncState',
  'localScoreAudio',
  'practiceRecordings',
  'audioPageCues',
};

Map<String, dynamic> _portablePreferences(Map<String, dynamic> source) => {
  for (final row in source.entries)
    if (!_deviceOnlyPreferences.contains(row.key) &&
        !row.key.startsWith('sharedLibrarySync-'))
      row.key: row.value,
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
          if (preferences != null) 'preferencesVersion': 1,
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
  required bool restoreSettings,
  required bool recoveryRequired,
}) {
  final input = InputFileStream(path);
  final written = <File>[];
  try {
    final names = <String>{};
    var duplicate = false;
    final archive = ZipDecoder().decodeStream(
      input,
      verify: true,
      callback: (entry) {
        if (!names.add(entry.name)) duplicate = true;
      },
    );
    if (duplicate) {
      throw const FormatException('Duplicate backup entries');
    }
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
    if (manifest['preferencesVersion'] case final version? when version != 1) {
      throw const FormatException('Unsupported backup preferences version');
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
    if (kind == LibraryArchive.score && sourceScores.single.expired) {
      throw const FormatException('This shared score package has expired.');
    }
    final referencesOnly =
        kind != LibraryArchive.score && manifest['referencesOnly'] == true;
    final metadataOnly = kind == LibraryArchive.library && referencesOnly;
    if (recoveryRequired && metadataOnly) {
      throw const FormatException(
        'A full library backup is required for recovery',
      );
    }
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
        if (metadataOnly && old.deletedAt != null) continue;
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
          if (metadataOnly) {
            mapped[bookmark.selectionId(old.id)] = bookmark.selectionId(
              target.id,
            );
            continue;
          }
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
        if (metadataOnly && !scores.any((score) => score.id == target.id)) {
          final existingExpiry = target.validUntil;
          final incomingExpiry = old.validUntil;
          scores.add(
            old.copyWith(
              id: target.id,
              pdfSourceId: target.pdfSourceId,
              detachPdf: target.pdfSourceId == null,
              validUntil:
                  existingExpiry != null &&
                      (incomingExpiry == null ||
                          existingExpiry.isBefore(incomingExpiry))
                  ? existingExpiry
                  : incomingExpiry,
            ),
          );
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
      if (score.actions.isEmpty && score.versionOf == null) continue;
      scores[index] = score.copyWith(
        versionOf: mapped[score.versionOf],
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
    final mappedLists = <String, String>{};
    for (final old in sourceSetlists) {
      String id;
      do {
        id = '${sequence++}';
      } while (!listIds.add(id));
      mappedLists[old.id] = id;
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

    final preferences = {...existingPreferences};
    if (kind == LibraryArchive.library &&
        restoreSettings &&
        savedPreferences is Map<String, dynamic>) {
      final portable = _portablePreferences(savedPreferences);
      Iterable<String> values(Object? value) =>
          value is List ? value.whereType<String>() : const [];
      preferences.addAll(portable);
      for (final key in ['scoreCollections', 'personalStamps']) {
        preferences[key] = {
          ...values(existingPreferences[key]),
          ...values(portable[key]),
        }.toList();
      }
      preferences['scoreTabs'] = {
        ...values(existingPreferences['scoreTabs']),
        ...values(portable['scoreTabs'])
            .map((id) => mapped[id])
            .whereType<String>(),
      }.toList();
      if (portable['scoreTabPages'] case final Map saved) {
        preferences['scoreTabPages'] = {
          if (existingPreferences['scoreTabPages'] case final Map existing)
            ...existing,
          for (final entry in saved.entries)
            if (mapped[entry.key] case final String target)
              if (entry.value is int) target: entry.value,
        };
      }
      if (portable['activeScoreTab'] case final String selected) {
        preferences['activeScoreTab'] =
            mapped[selected] ?? existingPreferences['activeScoreTab'];
      }
      if (portable['setlistPlayHistory'] case final Map saved) {
        final history = <String, dynamic>{
          ...?existingPreferences['setlistPlayHistory']
              as Map<String, dynamic>?,
        };
        for (final entry in saved.entries) {
          if (entry.key is! String || entry.value is! int) continue;
          final parts = (entry.key as String).split('/');
          final list = mappedLists[parts.first];
          if (list == null) continue;
          if (parts.length == 1) history[list] = entry.value;
          if (mapped[parts.last] case final selection? when parts.length == 2) {
            history['$list/$selection'] = entry.value;
          }
        }
        preferences['setlistPlayHistory'] = history;
      }
      if (portable['practiceActivity'] case final List saved) {
        final existing = existingPreferences['practiceActivity'];
        preferences['practiceActivity'] = [
          if (existing is List) ...existing,
          for (final row in saved)
            if (row case {'id': final String id, 'kind': final String kind})
              if ((kind == 'setlist' ? mappedLists[id] : mapped[id])
                  case final target?)
                {...row as Map<String, dynamic>, 'id': target},
        ];
      }
    }
    final replacing = metadataOnly
        ? scores.map((score) => score.id).toSet()
        : const <String>{};
    final live = File('$root/catalog.json');
    if (recoveryRequired && live.existsSync()) {
      live.copySync('$root/catalog-damaged-${ScoreLibrary.newRecordId()}.json');
    }
    _commitCatalog(
      root,
      _catalog(
        [
          ...existingScores.where((score) => !replacing.contains(score.id)),
          ...scores,
        ],
        [...existingSetlists, ...setlists],
        preferences: preferences,
      ),
    );
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
