import 'package:file_selector/file_selector.dart';

import 'library_storage_memory.dart'
    if (dart.library.io) 'library_storage_native.dart'
    as platform;

class ScoreEntry {
  const ScoreEntry({
    required this.id,
    required this.title,
    required this.page,
    required this.openedAt,
  });

  factory ScoreEntry.fromJson(Map<String, dynamic> json) => ScoreEntry(
    id: json['id'] as String,
    title: json['title'] as String,
    page: json['page'] as int,
    openedAt: DateTime.parse(json['openedAt'] as String),
  );

  final String id;
  final String title;
  final int page;
  final DateTime openedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'page': page,
    'openedAt': openedAt.toIso8601String(),
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
  Future<void> _pending = Future.value();

  List<ScoreEntry> get recent =>
      _scores.values.toList()..sort((a, b) => b.openedAt.compareTo(a.openedAt));

  ScoreEntry? lookup(String id) => _scores[id];
  List<Setlist> get setlists => List.unmodifiable(_setlists.values);

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
        final updated = ScoreEntry(
          id: id,
          title: old.title,
          page: page,
          openedAt: opened ? DateTime.now().toUtc() : old.openedAt,
        );
        await storage.writeIndex([
          for (final entry in _scores.values) entry.id == id ? updated : entry,
        ]);
        _scores[id] = updated;
      });
}
