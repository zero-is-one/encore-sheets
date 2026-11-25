import 'package:file_selector/file_selector.dart';

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
  const ScoreEntry({
    required this.id,
    required this.title,
    required this.page,
    required this.openedAt,
    this.metadata = const {},
    this.collections = const [],
    this.bookmarks = const [],
    this.flags = const [],
    this.jumps = const [],
  });

  factory ScoreEntry.fromJson(Map<String, dynamic> json) => ScoreEntry(
    id: json['id'] as String,
    title: json['title'] as String,
    page: json['page'] as int,
    openedAt: DateTime.parse(json['openedAt'] as String),
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
  );

  final String id;
  final String title;
  final int page;
  final DateTime openedAt;
  final Map<String, String> metadata;
  final List<String> collections;
  final List<ScoreBookmark> bookmarks;
  final List<int> flags;
  final List<ScoreJump> jumps;

  ScoreEntry copyWith({
    String? id,
    String? title,
    int? page,
    DateTime? openedAt,
    Map<String, String>? metadata,
    List<String>? collections,
    List<ScoreBookmark>? bookmarks,
    List<int>? flags,
    List<ScoreJump>? jumps,
  }) => ScoreEntry(
    id: id ?? this.id,
    title: title ?? this.title,
    page: page ?? this.page,
    openedAt: openedAt ?? this.openedAt,
    metadata: metadata ?? this.metadata,
    collections: collections ?? this.collections,
    bookmarks: bookmarks ?? this.bookmarks,
    flags: flags ?? this.flags,
    jumps: jumps ?? this.jumps,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'page': page,
    'openedAt': openedAt.toIso8601String(),
    if (metadata.isNotEmpty) 'metadata': metadata,
    if (collections.isNotEmpty) 'collections': collections,
    if (bookmarks.isNotEmpty)
      'bookmarks': bookmarks.map((item) => item.toJson()).toList(),
    if (flags.isNotEmpty) 'flags': flags,
    if (jumps.isNotEmpty) 'jumps': jumps.map((item) => item.toJson()).toList(),
  };
}

class Setlist {
  Setlist(this.id, this.name, Iterable<String> scores)
    : scores = List.unmodifiable(scores);

  factory Setlist.fromJson(Map<String, dynamic> row) => Setlist(
    row['id'] as String,
    row['name'] as String,
    (row['scores'] as List<dynamic>).cast<String>(),
  );

  final String id;
  final String name;
  final List<String> scores;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'scores': scores};
}

abstract class LibraryStorage {
  static LibraryStorage create() => platform.createStorage();

  bool get persistent;
  Future<Map<String, dynamic>> readPreferences();
  Future<void> writePreferences(Map<String, dynamic> preferences);
  Future<List<ScoreEntry>> readIndex();
  Future<void> writeIndex(List<ScoreEntry> entries);
  Future<XFile> copyScore(String id, XFile source);
  Future<XFile> openScore(String id);
  Future<void> removeScore(String id);
  Future<Map<String, dynamic>> readInk(String id);
  Future<void> writeInk(String id, Map<String, dynamic> pages);
  Future<List<Setlist>> readSetlists();
  Future<void> writeSetlists(List<Setlist> setlists);
  Future<XFile> createBackup(List<ScoreEntry> scores, List<Setlist> setlists);
  Future<({List<ScoreEntry> scores, List<Setlist> setlists})> restoreBackup(
    XFile source,
    List<ScoreEntry> scores,
    List<Setlist> setlists,
  );
}

class ScoreLibrary {
  ScoreLibrary(this.storage);

  final LibraryStorage storage;
  final _scores = <String, ScoreEntry>{};
  final _setlists = <String, Setlist>{};
  final _collections = <String>{};
  Future<void> _pending = Future.value();

  List<ScoreEntry> get recent =>
      _scores.values.toList()..sort((a, b) => b.openedAt.compareTo(a.openedAt));

  ScoreEntry? lookup(String id) => _scores[id];
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
    final updated = {..._setlists, setlist.id: setlist};
    await storage.writeSetlists(updated.values.toList());
    _setlists[setlist.id] = setlist;
  });
  Future<void> flush() => _pending;

  Future<XFile> createBackup() =>
      _serialize(() => storage.createBackup(_scores.values.toList(), setlists));

  Future<({int scores, int setlists})> restoreBackup(XFile source) =>
      _serialize(() async {
        final restored = await storage.restoreBackup(
          source,
          _scores.values.toList(),
          setlists,
        );
        for (final score in restored.scores) {
          _scores[score.id] = score;
        }
        for (final setlist in restored.setlists) {
          _setlists[setlist.id] = setlist;
        }
        return (
          scores: restored.scores.length,
          setlists: restored.setlists.length,
        );
      });

  Future<Map<String, dynamic>> readInk(String id) =>
      _serialize(() => storage.readInk(id));

  Future<void> writeInk(String id, Map<String, dynamic> pages) =>
      _serialize(() => storage.writeInk(id, pages));

  Future<void> load() async {
    final preferences = await storage.readPreferences();
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

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<(ScoreEntry, XFile)> import(XFile source) => _serialize(() async {
    final now = DateTime.now().toUtc();
    var number = now.microsecondsSinceEpoch;
    while (_scores.containsKey('$number')) {
      number++;
    }
    final title = source.name
        .split(RegExp(r'[/\\]'))
        .last
        .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')
        .trim();
    final score = ScoreEntry(
      id: '$number',
      title: title.isEmpty ? 'Untitled score' : title,
      page: 1,
      openedAt: now,
    );
    final local = await storage.copyScore(score.id, source);
    try {
      await storage.writeIndex([..._scores.values, score]);
    } catch (_) {
      await storage.removeScore(score.id);
      rethrow;
    }
    _scores[score.id] = score;
    return (score, local);
  });

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
