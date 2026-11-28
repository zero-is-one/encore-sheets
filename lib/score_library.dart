import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';

import 'library_sync.dart';
import 'page_crop.dart';
import 'program_duration.dart';
import 'reader_preferences.dart';
import 'score_action.dart';
import 'reflow_zones.dart';
import 'library_storage_memory.dart'
    if (dart.library.io) 'library_storage_native.dart'
    as platform;

class ScoreBookmark {
  const ScoreBookmark(this.id, this.title, this.page, {this.endPage});

  factory ScoreBookmark.fromJson(Map<String, dynamic> json) => ScoreBookmark(
    json['id'] as String,
    json['title'] as String,
    json['page'] as int,
    endPage: json['endPage'] as int?,
  );

  final String id;
  final String title;
  final int page;
  final int? endPage;
  bool get isItem => endPage != null;
  String selectionId(String scoreId) => '$scoreId:$id';

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'page': page,
    if (endPage != null) 'endPage': endPage,
  };
}

class JumpPoint {
  const JumpPoint(this.page, this.x, this.y);
  factory JumpPoint.fromJson(Map<String, dynamic> data) => JumpPoint(
    data['page'] as int,
    (data['x'] as num).toDouble(),
    (data['y'] as num).toDouble(),
  );
  final int page;
  final double x;
  final double y;
  Map<String, dynamic> toJson() => {'page': page, 'x': x, 'y': y};
}

class ScoreJump {
  const ScoreJump(this.title, this.source, this.target);
  factory ScoreJump.fromJson(Map<String, dynamic> data) => ScoreJump(
    data['title'] as String,
    JumpPoint.fromJson(data['source'] as Map<String, dynamic>),
    JumpPoint.fromJson(data['target'] as Map<String, dynamic>),
  );
  final String title;
  final JumpPoint source;
  final JumpPoint target;
  Map<String, dynamic> toJson() => {
    'title': title,
    'source': source.toJson(),
    'target': target.toJson(),
  };
}

class ScoreEntry {
  static const sampleMetadataKey = 'bundledSample';

  bool get isSample => metadata[sampleMetadataKey] == 'firstLight';

  const ScoreEntry({
    required this.id,
    required this.title,
    required this.page,
    required this.openedAt,
    this.addedAt,
    this.metadata = const {},
    this.collections = const [],
    this.bookmarks = const [],
    this.flags = const [],
    this.jumps = const [],
    this.halfSplits = const {},
    this.crops = const {},
    this.pageNotes = const {},
    this.actions = const [],
    this.reflowZones = const [],
    this.pdfSourceId,
    this.deletedAt,
    this.validUntil,
    this.scrollMode,
  });

  factory ScoreEntry.fromJson(Map<String, dynamic> json) => ScoreEntry(
    id: json['id'] as String,
    title: json['title'] as String,
    page: json['page'] as int,
    openedAt: DateTime.parse(json['openedAt'] as String),
    addedAt: DateTime.tryParse(json['addedAt'] as String? ?? ''),
    pdfSourceId: switch (json['pdfSourceId']) {
      final String id when RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(id) => id,
      _ => null,
    },
    deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
    scrollMode: ReaderScrollMode.fromJson(json['scrollMode']),
    validUntil: switch (json['validUntil']) {
      null => null,
      final String value => DateTime.parse(value).toUtc(),
      _ => throw const FormatException('Invalid score expiration'),
    },
    metadata: (json['metadata'] as Map?)?.cast<String, String>() ?? const {},
    collections: (json['collections'] as List?)?.cast<String>() ?? const [],
    bookmarks: [
      for (final item in (json['bookmarks'] as List? ?? const []))
        ScoreBookmark.fromJson(item as Map<String, dynamic>),
    ],
    flags: (json['flags'] as List?)?.cast<int>() ?? const [],
    jumps: [
      for (final item in (json['jumps'] as List? ?? const []))
        ScoreJump.fromJson(item as Map<String, dynamic>),
    ],
    halfSplits: {
      for (final entry in (json['halfSplits'] as Map? ?? const {}).entries)
        if (int.tryParse(entry.key.toString()) case final page?)
          if (entry.value is num &&
              (entry.value as num).isFinite &&
              (entry.value as num) >= .2 &&
              (entry.value as num) <= .8)
            page: (entry.value as num).toDouble(),
    },
    crops: {
      for (final entry in (json['crops'] as Map? ?? const {}).entries)
        if (int.tryParse(entry.key.toString()) case final page? when page > 0)
          if (PageCrop.fromJson(entry.value) case final crop?) page: crop,
    },
    pageNotes: {
      for (final row in (json['pageNotes'] as Map? ?? const {}).entries)
        if (int.tryParse(row.key.toString()) case final page? when page > 0)
          if (row.value case final String text when text.isNotEmpty) page: text,
    },
    actions: [
      for (final raw in (json['actions'] as List? ?? const []))
        if (ScoreAction.fromJson(raw) case final action?) action,
    ],
    reflowZones: [
      for (final raw in (json['reflowZones'] as List? ?? const []))
        if (raw case [int page, num top, num bottom]
            when page > 0 && top >= 0 && bottom <= 1 && bottom > top)
          (page: page, top: top.toDouble(), bottom: bottom.toDouble()),
    ],
  );

  final String id;
  final String title;
  final int page;
  final DateTime openedAt;
  final DateTime? addedAt;
  final DateTime? deletedAt;
  final DateTime? validUntil;
  final ReaderScrollMode? scrollMode;
  bool get expired => validUntil?.isAfter(DateTime.now()) == false;
  final Map<String, String> metadata;
  final List<String> collections;
  final List<ScoreBookmark> bookmarks;
  final List<int> flags;
  final List<ScoreJump> jumps;
  final Map<int, double> halfSplits;
  final Map<int, PageCrop> crops;
  final Map<int, String> pageNotes;
  final List<ScoreAction> actions;
  final List<ReflowZone> reflowZones;
  final String? pdfSourceId;
  String get storedPdfId => pdfSourceId ?? id;

  ScoreEntry copyWith({
    String? id,
    String? title,
    int? page,
    DateTime? openedAt,
    DateTime? addedAt,
    Map<String, String>? metadata,
    List<String>? collections,
    List<ScoreBookmark>? bookmarks,
    List<int>? flags,
    List<ScoreJump>? jumps,
    Map<int, double>? halfSplits,
    Map<int, PageCrop>? crops,
    Map<int, String>? pageNotes,
    List<ScoreAction>? actions,
    List<ReflowZone>? reflowZones,
    String? pdfSourceId,
    bool detachPdf = false,
    DateTime? deletedAt,
    bool recover = false,
    DateTime? validUntil,
    ReaderScrollMode? scrollMode,
    bool inheritScrollMode = false,
  }) => ScoreEntry(
    id: id ?? this.id,
    title: title ?? this.title,
    page: page ?? this.page,
    openedAt: openedAt ?? this.openedAt,
    addedAt: addedAt ?? this.addedAt,
    metadata: metadata ?? this.metadata,
    collections: collections ?? this.collections,
    bookmarks: bookmarks ?? this.bookmarks,
    flags: flags ?? this.flags,
    jumps: jumps ?? this.jumps,
    halfSplits: halfSplits ?? this.halfSplits,
    crops: crops ?? this.crops,
    pageNotes: pageNotes ?? this.pageNotes,
    actions: actions ?? this.actions,
    reflowZones: reflowZones ?? this.reflowZones,
    pdfSourceId: detachPdf ? null : pdfSourceId ?? this.pdfSourceId,
    deletedAt: recover ? null : deletedAt ?? this.deletedAt,
    validUntil: validUntil ?? this.validUntil,
    scrollMode: inheritScrollMode ? null : scrollMode ?? this.scrollMode,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'page': page,
    'openedAt': openedAt.toIso8601String(),
    if (addedAt != null) 'addedAt': addedAt!.toIso8601String(),
    if (pdfSourceId != null) 'pdfSourceId': pdfSourceId,
    if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
    if (validUntil != null) 'validUntil': validUntil!.toUtc().toIso8601String(),
    if (scrollMode != null) 'scrollMode': scrollMode!.name,
    if (metadata.isNotEmpty) 'metadata': metadata,
    if (collections.isNotEmpty) 'collections': collections,
    if (bookmarks.isNotEmpty)
      'bookmarks': bookmarks.map((item) => item.toJson()).toList(),
    if (flags.isNotEmpty) 'flags': flags,
    if (jumps.isNotEmpty) 'jumps': jumps.map((item) => item.toJson()).toList(),
    if (halfSplits.isNotEmpty)
      'halfSplits': {
        for (final entry in halfSplits.entries)
          entry.key.toString(): entry.value,
      },
    if (crops.isNotEmpty)
      'crops': {
        for (final entry in crops.entries) '${entry.key}': entry.value.toJson(),
      },
    if (pageNotes.isNotEmpty)
      'pageNotes': {
        for (final row in pageNotes.entries) '${row.key}': row.value,
      },
    if (actions.isNotEmpty)
      'actions': [for (final action in actions) action.toJson()],
    if (reflowZones.isNotEmpty)
      'reflowZones': [
        for (final zone in reflowZones) [zone.page, zone.top, zone.bottom],
      ],
  };
}

class Setlist {
  Setlist(
    this.id,
    this.name,
    Iterable<String> scores, {
    this.folder = '',
    this.label = '',
    this.notes = '',
    Map<String, String> placeholders = const {},
  }) : scores = List.unmodifiable(scores),
       placeholders = Map.unmodifiable(placeholders);

  factory Setlist.fromJson(Map<String, dynamic> row) => Setlist(
    row['id'] as String,
    row['name'] as String,
    (row['scores'] as List<dynamic>).cast<String>(),
    folder: row['folder'] as String? ?? '',
    label: row['label'] as String? ?? '',
    notes: row['notes'] as String? ?? '',
    placeholders:
        (row['placeholders'] as Map?)?.cast<String, String>() ?? const {},
  );

  final String id;
  final String name;
  final List<String> scores;
  final String folder;
  final String label;
  final String notes;
  final Map<String, String> placeholders;

  Setlist copyWith({
    String? id,
    String? name,
    Iterable<String>? scores,
    String? folder,
    String? label,
    String? notes,
    Map<String, String>? placeholders,
  }) => Setlist(
    id ?? this.id,
    name ?? this.name,
    scores ?? this.scores,
    folder: folder ?? this.folder,
    label: label ?? this.label,
    notes: notes ?? this.notes,
    placeholders: placeholders ?? this.placeholders,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'scores': scores,
    if (folder.isNotEmpty) 'folder': folder,
    if (label.isNotEmpty) 'label': label,
    if (notes.isNotEmpty) 'notes': notes,
    if (placeholders.isNotEmpty) 'placeholders': placeholders,
  };
}

enum LibraryArchive { library, score, setlist }

class LibraryCatalogRecoveryRequired extends FormatException {
  const LibraryCatalogRecoveryRequired()
    : super('No valid library catalog recovery snapshot');
}

abstract class LibraryStorage {
  static LibraryStorage create() => platform.createStorage();

  bool get persistent;
  Future<Map<String, dynamic>> readPreferences();
  Future<void> writePreferences(Map<String, dynamic> preferences);
  Future<List<ScoreEntry>> readIndex();
  Future<void> writeIndex(List<ScoreEntry> entries);
  Future<void> writeCatalog(List<ScoreEntry> entries, List<Setlist> setlists);
  Future<XFile> copyScore(String id, XFile source);
  Future<XFile> openScore(String id);
  Future<void> removeScore(String id);
  Future<Map<String, dynamic>> readInk(String id);
  Future<void> writeInk(String id, Map<String, dynamic> pages);
  Future<List<Setlist>> readSetlists();
  Future<void> writeSetlists(List<Setlist> setlists);
  Future<XFile> createBackup(
    List<ScoreEntry> scores,
    List<Setlist> setlists, {
    bool includeScores = true,
  });
  Future<XFile?> latestBackup();
  Future<XFile> createScorePackage(
    ScoreEntry score, {
    XFile? extractedPdf,
    Map<String, dynamic>? extractedInk,
  });
  Future<XFile> createSetlistPackage(
    Setlist setlist,
    List<ScoreEntry> scores, {
    required String name,
    required bool includeScores,
  });
  Future<({List<ScoreEntry> scores, List<Setlist> setlists})> restoreBackup(
    XFile source,
    List<ScoreEntry> scores,
    List<Setlist> setlists, {
    LibraryArchive kind = LibraryArchive.library,
    bool restoreSettings = true,
  });
}

class ScoreLibrary {
  ScoreLibrary(this.storage);

  final LibraryStorage storage;
  final _scores = <String, ScoreEntry>{};
  final _setlists = <String, Setlist>{};
  final _setlistPlayed = <String, int>{};
  final _collections = <String>{};
  Future<void> _pending = Future.value();

  List<ScoreEntry> get recent =>
      _scores.values
          .where((score) => score.deletedAt == null && !score.expired)
          .toList()
        ..sort((a, b) => b.openedAt.compareTo(a.openedAt));

  List<ScoreEntry> get recentlyDeleted =>
      _scores.values.where((score) => score.deletedAt != null).toList()
        ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));

  ScoreEntry? lookup(String id) {
    final score = _scores[id];
    return score != null && score.deletedAt == null && !score.expired
        ? score
        : null;
  }

  Future<void> trashScores(Iterable<String> ids) => _serialize(() async {
    final deletedAt = DateTime.now();
    final next = Map.of(_scores);
    for (final id in ids) {
      if (lookup(id) case final score?) {
        next[id] = score.copyWith(deletedAt: deletedAt);
      }
    }
    await storage.writeIndex(next.values.toList());
    _scores.addAll(next);
  });

  Future<void> recoverScore(String id) =>
      updateScore(id, (score) => score.copyWith(recover: true));
  (ScoreEntry, ScoreBookmark?)? lookupSelection(String id) {
    final parts = id.split(':');
    final score = lookup(parts.first);
    if (score == null) return null;
    if (parts.length == 1) return (score, null);
    final bookmark = score.bookmarks
        .where((item) => item.isItem && item.id == parts.last)
        .firstOrNull;
    return bookmark == null ? null : (score, bookmark);
  }

  bool isInSetlist(String id) =>
      _setlists.values.any((setlist) => setlist.scores.contains(id));
  List<String> get collections => {
    ..._collections,
    for (final score in _scores.values) ...score.collections,
  }.toList()..sort();

  Future<void> updatePreferences(Map<String, dynamic> changes) => _serialize(
    () async => storage.writePreferences({
      ...await storage.readPreferences(),
      ...changes,
    }),
  );

  Future<void> createCollection(String name) => _serialize(() async {
    final title = name.trim();
    if (title.isEmpty || collections.contains(title)) return;
    final next = {..._collections, title};
    await storage.writePreferences({
      ...await storage.readPreferences(),
      'scoreCollections': next.toList(),
    });
    _collections.add(title);
  });

  Future<void> assignCollections(String id, Iterable<String> names) =>
      updateScore(
        id,
        (old) => old.copyWith(collections: List.unmodifiable(names.toSet())),
      );

  Future<void> applyMetadataTable(
    Map<String, ({String? title, Map<String, String> fields})> edits,
  ) => _serialize(() async {
    final updated = Map.of(_scores);
    for (final row in edits.entries) {
      final score = lookup(row.key);
      if (score == null) continue;
      final metadata = Map.of(score.metadata);
      for (final field in row.value.fields.entries) {
        if (field.value.isEmpty) {
          metadata.remove(field.key);
        } else {
          metadata[field.key] = field.value;
        }
      }
      updated[row.key] = score.copyWith(
        title: row.value.title,
        metadata: metadata,
      );
    }
    await storage.writeIndex(updated.values.toList());
    _scores.addAll(updated);
  });

  Future<void> savePageNote(String id, int page, String text) {
    if (page < 1) throw ArgumentError.value(page, 'page');
    return updateScore(id, (score) {
      final notes = Map.of(score.pageNotes);
      final cleaned = text.trim();
      if (cleaned.isEmpty) {
        notes.remove(page);
      } else {
        notes[page] = cleaned;
      }
      return score.copyWith(pageNotes: notes);
    });
  }

  Future<void> togglePageFlag(String id, int page) => updateScore(id, (score) {
    final flags = score.flags.toSet();
    if (!flags.remove(page)) flags.add(page);
    return score.copyWith(flags: flags.toList()..sort());
  });

  Future<void> updateScore(String id, ScoreEntry Function(ScoreEntry) update) =>
      _serialize(() async {
        final old = _scores[id];
        if (old == null) return;
        final changed = update(old);
        await storage.writeIndex([
          for (final score in _scores.values) score.id == id ? changed : score,
        ]);
        _scores[id] = changed;
      });

  Future<void> editMetadata(
    String id,
    String title,
    Map<String, String> fields,
  ) => _serialize(() async {
    final old = _scores[id];
    if (old == null) return;
    final metadata = {...old.metadata};
    for (final MapEntry(key: key, value: value) in fields.entries) {
      if (value.isEmpty) {
        metadata.remove(key);
      } else {
        metadata[key] = value;
      }
    }
    final updated = old.copyWith(title: title, metadata: metadata);
    await storage.writeIndex([
      for (final score in _scores.values) score.id == id ? updated : score,
    ]);
    _scores[id] = updated;
  });
  List<Setlist> get setlists => List.unmodifiable(_setlists.values);

  ({Duration total, int missing}) estimateSetlistDuration(
    Iterable<String> selections,
  ) {
    var total = Duration.zero;
    var missing = 0;
    for (final id in selections) {
      final item = lookupSelection(id);
      final duration = item == null || item.$2 != null
          ? null
          : parseScoreDuration(item.$1.metadata['duration']);
      if (duration == null) {
        missing++;
      } else {
        total += duration;
      }
    }
    return (total: total, missing: missing);
  }

  int? lastSetlistPlay(String id, [String? selection]) =>
      _setlistPlayed[selection == null ? id : '$id/$selection'];

  Future<void> recordSetlistPlay(String id, String selection) =>
      _serialize(() async {
        final now = DateTime.now().microsecondsSinceEpoch;
        final history = {..._setlistPlayed, id: now, '$id/$selection': now};
        await storage.writePreferences({
          ...await storage.readPreferences(),
          'setlistPlayHistory': history,
        });
        _setlistPlayed.addAll(history);
      });

  Future<void> moveSetlist(String id, String adjacentId) =>
      _serialize(() async {
        final ordered = setlists.toList();
        final start = ordered.indexWhere((list) => list.id == id);
        final end = ordered.indexWhere((list) => list.id == adjacentId);
        if (start < 0 || end < 0 || start == end) return;
        ordered.insert(end, ordered.removeAt(start));
        await storage.writeSetlists(ordered);
        _setlists
          ..clear()
          ..addEntries(ordered.map((list) => MapEntry(list.id, list)));
      });

  Future<void> batchMetadata(
    Set<String> ids,
    String field,
    String value, {
    required bool append,
  }) => _serialize(() async {
    final updated = {
      for (final old in _scores.values)
        old.id: ids.contains(old.id)
            ? _patchScoreField(old, field, value, append: append)
            : old,
    };
    await storage.writeIndex(updated.values.toList());
    _scores.addAll(updated);
  });

  ScoreEntry _patchScoreField(
    ScoreEntry old,
    String field,
    String value, {
    required bool append,
  }) {
    final metadata = {...old.metadata};
    final combined = append
        ? {
            for (final part in '${metadata[field] ?? ''},$value'.split(','))
              if (part.trim().isNotEmpty) part.trim(),
          }.join(', ')
        : value;
    if (combined.isEmpty) {
      metadata.remove(field);
    } else {
      metadata[field] = combined;
    }
    return old.copyWith(metadata: metadata);
  }

  Future<void> saveSetlist(Setlist setlist) => _serialize(() async {
    await _writeSetlist(setlist);
  });

  Future<bool> applyAssistantSetlist(Setlist setlist) => _serialize(() async {
    if (_setlists.containsKey(setlist.id)) return true;
    if (setlist.name.trim().isEmpty ||
        setlist.scores.isEmpty ||
        setlist.scores.any((id) {
          final score = lookup(id);
          return score == null || score.validUntil != null;
        })) {
      return false;
    }
    await _writeSetlist(setlist);
    return true;
  });

  Future<void> _writeSetlist(Setlist setlist) async {
    final updated = {..._setlists, setlist.id: setlist};
    await storage.writeSetlists(updated.values.toList());
    _setlists[setlist.id] = setlist;
  }

  Future<void> appendToSetlist(String id, String scoreId) =>
      _serialize(() async {
        final target = _setlists[id];
        if (target == null || lookupSelection(scoreId) == null) {
          throw StateError('The setlist or score is no longer available.');
        }
        final amended = target.copyWith(scores: [...target.scores, scoreId]);
        final updated = {..._setlists, id: amended};
        await storage.writeSetlists(updated.values.toList());
        _setlists[id] = amended;
      });

  Future<void> duplicateSetlist(Setlist setlist) => _serialize(() async {
    final names = _setlists.values
        .where((list) => list.folder == setlist.folder)
        .map((list) => list.name.toLowerCase())
        .toSet();
    var name = '${setlist.name} copy';
    var suffix = 2;
    while (names.contains(name.toLowerCase())) {
      name = '${setlist.name} copy ${suffix++}';
    }
    final copy = setlist.copyWith(id: newRecordId(), name: name);
    await storage.writeSetlists([..._setlists.values, copy]);
    _setlists[copy.id] = copy;
  });
  Future<void> flush() => _pending;

  Future<ScoreEntry> duplicateScore(String id) => _serialize(() async {
    final original = lookup(id);
    if (original == null) throw StateError('The source score is missing.');
    final now = DateTime.now().toUtc();
    final titles = _scores.values
        .map((score) => score.title.toLowerCase())
        .toSet();
    var name = '${original.title} copy';
    var suffix = 2;
    while (titles.contains(name.toLowerCase())) {
      name = '${original.title} copy ${suffix++}';
    }
    final copy = original.copyWith(
      id: newRecordId(),
      title: name,
      openedAt: now,
      addedAt: now,
      pdfSourceId: original.storedPdfId,
      metadata: {...original.metadata}..remove(ScoreEntry.sampleMetadataKey),
    );
    final annotations = await storage.readInk(original.id);
    try {
      if (annotations.isNotEmpty) await storage.writeInk(copy.id, annotations);
      await storage.writeIndex([..._scores.values, copy]);
    } catch (_) {
      await storage.removeScore(copy.id);
      rethrow;
    }
    _scores[copy.id] = copy;
    return copy;
  });

  Future<void> resetSyncState() =>
      updatePreferences({'librarySyncState': null});

  static String newRecordId() {
    final random = math.Random.secure();
    return List.generate(
      4,
      (_) => random.nextInt(1 << 30).toRadixString(16).padLeft(8, '0'),
    ).join();
  }

  static const _sharedScoreFields = {
    'id',
    'title',
    'addedAt',
    'collections',
    'bookmarks',
    'deletedAt',
  };
  static const _sharedSetlistFields = {
    'id',
    'name',
    'scores',
    'folder',
    'label',
    'notes',
    'placeholders',
  };
  static const _metadataFieldPrefix = 'metadata-';
  static final _metadataField = RegExp(r'^metadata-[a-zA-Z0-9_=-]{1,1024}$');

  Future<Set<String>> synchronize(
    LibrarySyncEndpoint endpoint, {
    bool Function()? mayApply,
  }) => _serialize(() async {
    String fingerprint(Map<String, dynamic> data) =>
        sha256.convert(utf8.encode(jsonEncode(data))).toString();
    final shared = endpoint is SharedLibrarySyncEndpoint;
    final stateKey = shared ? endpoint.stateKey : 'librarySyncState';
    final preferences = await storage.readPreferences();
    final state = preferences[stateKey] as Map? ?? {};
    final device = state['device'] as String? ?? newRecordId();
    final known = state['known'] as Map? ?? {};
    final heads = await endpoint.readDevices();
    final latest =
        <String, ({int revision, String device, Map<String, dynamic> data})>{};
    var sequence = shared ? 0 : DateTime.now().microsecondsSinceEpoch;
    for (final head in heads.entries) {
      for (final record in head.value.entries) {
        final parts = record.key.split(':');
        if (parts.length != (shared ? 3 : 2) ||
            (parts.first != 's' && parts.first != 'l') ||
            !RegExp(r'^[a-zA-Z0-9-]{1,80}$').hasMatch(parts[1]))
          continue;
        if (shared &&
            (parts.first == 's'
                ? !_sharedScoreFields.contains(parts.last) &&
                      !_metadataField.hasMatch(parts.last)
                : !_sharedSetlistFields.contains(parts.last)))
          continue;
        if (record.value case {
          'revision': final int revision,
          'data': final Map<String, dynamic> data,
        }) {
          if (shared &&
              (revision < 1 ||
                  revision >= (1 << 30) ||
                  !data.containsKey('value'))) {
            throw const FormatException('Invalid shared library revision');
          }
          final existing = latest[record.key];
          if (existing == null ||
              revision > existing.revision ||
              revision == existing.revision &&
                  head.key.compareTo(existing.device) > 0) {
            latest[record.key] = (
              revision: revision,
              device: head.key,
              data: data,
            );
          }
          sequence = math.max(sequence, revision);
        }
      }
    }
    final local = <String, Map<String, dynamic>>{};
    for (final score in _scores.values) {
      if (shared) {
        if (score.validUntil != null) continue;
        final data = score.toJson();
        for (final field in _sharedScoreFields) {
          local['s:${score.id}:$field'] = {'value': data[field]};
        }
        for (final entry in score.metadata.entries) {
          final field =
              '$_metadataFieldPrefix${base64Url.encode(utf8.encode(entry.key))}';
          if (_metadataField.hasMatch(field)) {
            local['s:${score.id}:$field'] = {'value': entry.value};
          }
        }
        continue;
      }
      final data = score.toJson()
        ..remove('pdfSourceId')
        ..remove('openedAt')
        ..remove('page');
      local['s:${score.id}'] = {
        'score': data,
        'ink': await storage.readInk(score.id),
      };
    }
    for (final setlist in _setlists.values) {
      final data = setlist.toJson();
      if (shared) {
        for (final field in _sharedSetlistFields) {
          local['l:${setlist.id}:$field'] = {'value': data[field]};
        }
      } else {
        local['l:${setlist.id}'] = data;
      }
    }
    if (shared) {
      for (final key in known.keys.whereType<String>()) {
        final parts = key.split(':');
        if (parts.length != 3 || local.containsKey(key)) continue;
        if (parts.first == 's' && _metadataField.hasMatch(parts.last)) {
          if (_scores[parts[1]] case ScoreEntry(validUntil: null)) {
            local[key] = {'value': null};
          }
        }
      }
    }
    if (state['device'] == null) {
      preferences[stateKey] = {'device': device, 'known': known};
      await storage.writePreferences(preferences);
    }
    final outbound = {...?heads[device]};
    var changed = false;
    for (final row in local.entries) {
      final remote = latest[row.key]?.data;
      final serialized = fingerprint(row.value);
      final recordKey = shared
          ? row.key.substring(0, row.key.lastIndexOf(':'))
          : '';
      final newMetadataField =
          shared &&
          row.key.startsWith('$recordKey:$_metadataFieldPrefix') &&
          known.containsKey('$recordKey:id');
      if (remote != null &&
          (serialized == known[row.key] ||
              serialized == fingerprint(remote) ||
              !known.containsKey(row.key) && !newMetadataField)) {
        continue;
      }
      if (remote == null &&
          row.key.startsWith('s:') &&
          (!shared || row.key.endsWith(':id'))) {
        final id = row.key.split(':')[1];
        await endpoint.publishPdf(id, await storage.openScore(id));
      }
      final revision = ++sequence;
      outbound[row.key] = {'revision': revision, 'data': row.value};
      latest[row.key] = (revision: revision, device: device, data: row.value);
      changed = true;
    }
    if (changed) await endpoint.writeDevice(device, outbound);
    if (mayApply?.call() == false)
      throw StateError('Library changes are deferred while editing.');

    final scores = Map.of(_scores);
    final setlists = Map.of(_setlists);
    final updated = <String>{};
    final staged = <String>[];
    final previousInk = <String, Map<String, dynamic>>{};
    var receivedLists = false;
    final incomingRecords = <String, Map<String, dynamic>>{};
    for (final row in latest.entries) {
      if (shared) {
        final split = row.key.lastIndexOf(':');
        final record = incomingRecords.putIfAbsent(
          row.key.substring(0, split),
          () => {},
        );
        final field = row.key.substring(split + 1);
        final value = row.value.data['value'];
        if (field.startsWith(_metadataFieldPrefix)) {
          final key = utf8.decode(
            base64Url.decode(field.substring(_metadataFieldPrefix.length)),
          );
          final metadata = record.putIfAbsent(
            'metadata',
            () => <String, String?>{},
          ) as Map<String, String?>;
          metadata[key] = value as String?;
        } else {
          record[field] = value;
        }
      } else {
        incomingRecords[row.key] = row.value.data;
      }
    }
    try {
      for (final row in incomingRecords.entries) {
        final incoming = row.value;
        final previous = local[row.key];
        if (previous != null && fingerprint(previous) == fingerprint(incoming))
          continue;
        final id = row.key.substring(2);
        if (row.key.startsWith('l:')) {
          final setlist = Setlist.fromJson(incoming);
          if (setlist.id != id)
            throw const FormatException('Invalid shared setlist');
          if (!shared ||
              fingerprint(_setlists[id]?.toJson() ?? {}) !=
                  fingerprint(setlist.toJson())) {
            setlists[id] = setlist;
            receivedLists = true;
          }
          continue;
        }
        final existing = _scores[id];
        if (shared && existing?.validUntil != null) continue;
        if (shared && existing == null && incoming['deletedAt'] != null)
          continue;
        if (incoming['metadata'] case final Map<String, String?> edits
            when shared) {
          final metadata = {...?existing?.metadata};
          for (final edit in edits.entries) {
            if (edit.value case final value?) {
              metadata[edit.key] = value;
            } else {
              metadata.remove(edit.key);
            }
          }
          incoming['metadata'] = metadata;
        }
        final score = ScoreEntry.fromJson({
          if (shared) ...?existing?.toJson(),
          ...(shared ? incoming : incoming['score'] as Map<String, dynamic>),
          'pdfSourceId': existing?.pdfSourceId,
          'page': existing?.page ?? 1,
          'openedAt': (existing?.openedAt ?? DateTime.now()).toIso8601String(),
          if (existing?.addedAt case final added?)
            'addedAt': added.toIso8601String(),
        });
        if (score.id != id) throw const FormatException('Invalid shared score');
        if (shared &&
            existing != null &&
            fingerprint(existing.toJson()) == fingerprint(score.toJson()))
          continue;
        if (existing == null) {
          final pdf = await endpoint.fetchPdf(id);
          await storage.copyScore(id, pdf);
          staged.add(id);
        } else if (!shared) {
          previousInk[id] = previous!['ink'] as Map<String, dynamic>;
        }
        if (!shared) {
          await storage.writeInk(id, incoming['ink'] as Map<String, dynamic>);
        }
        scores[id] = score;
        updated.add(id);
      }
      if (updated.isNotEmpty || receivedLists) {
        if (mayApply?.call() == false)
          throw StateError('Library changes are deferred while editing.');
        await storage.writeCatalog(
          scores.values.toList(),
          setlists.values.toList(),
        );
      }
    } catch (_) {
      for (final id in staged) {
        await storage.removeScore(id);
      }
      for (final entry in previousInk.entries) {
        await storage.writeInk(entry.key, entry.value);
      }
      rethrow;
    }
    _scores.addAll(scores);
    _setlists.addAll(setlists);
    final nextKnown = {
      for (final row in latest.entries) row.key: fingerprint(row.value.data),
    };
    if (state['device'] != device ||
        known.length != nextKnown.length ||
        nextKnown.entries.any((row) => known[row.key] != row.value)) {
      await storage.writePreferences({
        ...preferences,
        stateKey: {'device': device, 'known': nextKnown},
      });
    }
    return updated;
  });

  Future<XFile> createBackup({bool includeScores = true}) => _serialize(
    () => storage.createBackup(
      _scores.values.toList(),
      setlists,
      includeScores: includeScores,
    ),
  );

  Future<XFile> createScorePackage(
    ScoreEntry score, {
    XFile? extractedPdf,
    Map<String, dynamic>? extractedInk,
  }) => _serialize(
    () => storage.createScorePackage(
      score,
      extractedPdf: extractedPdf,
      extractedInk: extractedInk,
    ),
  );

  Future<ScoreEntry> restoreScorePackage(XFile source) => _serialize(() async {
    final restored = await storage.restoreBackup(
      source,
      _scores.values.toList(),
      setlists,
      kind: LibraryArchive.score,
    );
    final score = restored.scores.single;
    _scores[score.id] = score;
    return score;
  });

  Future<XFile> createSetlistPackage(
    Setlist setlist, {
    required String name,
    required bool includeScores,
  }) => _serialize(() {
    final scores = <String, ScoreEntry>{};
    final placeholders = <String, String>{};
    for (final id in setlist.scores) {
      final match = lookupSelection(id);
      if (match == null) {
        placeholders[id] = setlist.placeholders[id] ?? 'Missing score';
      } else {
        scores[match.$1.id] = match.$1;
      }
    }
    return storage.createSetlistPackage(
      setlist.copyWith(placeholders: placeholders),
      scores.values.toList(),
      name: name,
      includeScores: includeScores,
    );
  });

  Future<Setlist> restoreSetlistPackage(XFile source) => _serialize(() async {
    final restored = await storage.restoreBackup(
      source,
      _scores.values.toList(),
      setlists,
      kind: LibraryArchive.setlist,
    );
    for (final score in restored.scores) {
      _scores[score.id] = score;
    }
    final setlist = restored.setlists.single;
    _setlists[setlist.id] = setlist;
    return setlist;
  });

  Future<({int scores, int setlists})> restoreBackup(
    XFile source, {
    bool restoreSettings = true,
  }) => _serialize(() async {
    final restored = await storage.restoreBackup(
      source,
      _scores.values.toList(),
      setlists,
      restoreSettings: restoreSettings,
    );
    for (final score in restored.scores) {
      _scores[score.id] = score;
    }
    for (final setlist in restored.setlists) {
      _setlists[setlist.id] = setlist;
    }
    final preferences = await storage.readPreferences();
    _readSetlistPlayHistory(preferences);
    if (preferences['scoreCollections'] case final List names) {
      _collections.addAll(names.whereType<String>());
    }
    return (scores: restored.scores.length, setlists: restored.setlists.length);
  });

  Future<Map<String, dynamic>> readInk(String id) =>
      _serialize(() => storage.readInk(id));

  Future<void> writeInk(String id, Map<String, dynamic> pages) =>
      _serialize(() => storage.writeInk(id, pages));

  Future<void> load() async {
    final preferences = await storage.readPreferences();
    _readSetlistPlayHistory(preferences);
    _collections.addAll(
      (preferences['scoreCollections'] as List?)?.whereType<String>() ?? [],
    );
    for (final score in await storage.readIndex()) {
      _scores[score.id] = score;
    }
    for (final setlist in await storage.readSetlists()) {
      _setlists[setlist.id] = setlist;
    }
  }

  void _readSetlistPlayHistory(Map<String, dynamic> preferences) {
    final history = preferences['setlistPlayHistory'];
    if (history is Map) {
      for (final row in history.entries) {
        if (row.key is String && row.value is int)
          _setlistPlayed[row.key] = row.value;
      }
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> seedSampleScore(Future<XFile> Function() source) =>
      _serialize(() async {
        final preferences = await storage.readPreferences();
        if (preferences['firstLightSeeded'] == true) return;
        if (!_scores.values.any((score) => score.isSample)) {
          await _import(await source(), bundledSample: true);
        }
        await storage.writePreferences({
          ...preferences,
          'firstLightSeeded': true,
        });
      });

  Future<(ScoreEntry, XFile)> import(
    XFile source, {
    ScoreEntry? template,
    Map<String, dynamic> annotations = const {},
    bool replace = false,
  }) => _serialize(
    () => _import(
      source,
      template: template,
      annotations: annotations,
      replace: replace,
    ),
  );

  Future<(ScoreEntry, XFile)> _import(
    XFile source, {
    ScoreEntry? template,
    Map<String, dynamic> annotations = const {},
    bool replace = false,
    bool bundledSample = false,
  }) async {
    final now = DateTime.now().toUtc();
    final previous = replace && template != null ? lookup(template.id) : null;
    if (replace && previous == null)
      throw StateError('The source score is missing.');
    final title = source.name
        .split(RegExp(r'[/\\]'))
        .last
        .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')
        .trim();
    var score = ScoreEntry(
      id: newRecordId(),
      title: bundledSample
          ? 'First Light'
          : (title.isEmpty ? 'Untitled score' : title),
      page: 1,
      openedAt: now,
      addedAt: now,
      metadata: bundledSample
          ? const {ScoreEntry.sampleMetadataKey: 'firstLight'}
          : const {},
    );
    if (template != null) {
      final metadata = {...template.metadata}
        ..remove(ScoreEntry.sampleMetadataKey);
      if (previous?.isSample == true) {
        metadata[ScoreEntry.sampleMetadataKey] = 'firstLight';
      }
      score = template.copyWith(
        id: score.id,
        title: previous?.title ?? score.title,
        openedAt: now,
        addedAt: previous == null ? now : previous.addedAt,
        recover: true,
        detachPdf: true,
        metadata: metadata,
      );
    }
    final entries = Map.of(_scores);
    entries[score.id] = score;
    final lists = Map.of(_setlists);
    if (previous != null) {
      entries[previous.id] = previous.copyWith(deletedAt: now);
      final remaining = score.bookmarks
          .where((bookmark) => bookmark.isItem)
          .map((bookmark) => bookmark.id)
          .toSet();
      for (final old in _setlists.values) {
        lists[old.id] = old.copyWith(
          scores: old.scores.expand((selection) {
            final parts = selection.split(':');
            if (parts.first != previous.id) return [selection];
            if (parts.length == 1) return [score.id];
            return remaining.contains(parts.last)
                ? ['${score.id}:${parts.last}']
                : <String>[];
          }),
        );
      }
    }
    final local = await storage.copyScore(score.id, source);
    try {
      if (annotations.isNotEmpty) await storage.writeInk(score.id, annotations);
      if (previous == null) {
        await storage.writeIndex(entries.values.toList());
      } else {
        await storage.writeCatalog(
          entries.values.toList(),
          lists.values.toList(),
        );
      }
    } catch (_) {
      await storage.removeScore(score.id);
      rethrow;
    }
    _scores.addAll(entries);
    _setlists.addAll(lists);
    return (score, local);
  }

  Future<void> record(String id, int page, {bool opened = false}) =>
      _serialize(() async {
        final old = _scores[id];
        if (old == null || (!opened && old.page == page)) return;
        final updated = old.copyWith(
          page: page,
          openedAt: opened ? DateTime.now().toUtc() : null,
        );
        await storage.writeIndex([
          for (final entry in _scores.values) entry.id == id ? updated : entry,
        ]);
        _scores[id] = updated;
      });
}
