import 'package:file_selector/file_selector.dart';

import 'score_library.dart';

LibraryStorage createStorage() => _MemoryLibraryStorage();

class _MemoryLibraryStorage implements LibraryStorage {
  final _files = <String, XFile>{};
  final _ink = <String, Map<String, dynamic>>{};
  List<Setlist> _setlists = [];
  Map<String, dynamic> _preferences = {};

  @override
  Future<Map<String, dynamic>> readPreferences() async => _preferences;

  @override
  Future<void> writePreferences(Map<String, dynamic> preferences) async {
    _preferences = Map.unmodifiable(preferences);
  }

  @override
  Future<XFile> createBackup(List<ScoreEntry> scores, List<Setlist> setlists) =>
      Future.error(
        UnsupportedError('Library backup requires the installed app'),
      );

  @override
  Future<XFile> createScorePackage(
    ScoreEntry score, {
    XFile? extractedPdf,
    Map<String, dynamic>? extractedInk,
  }) async =>
      throw UnsupportedError('Score packages require the installed app');

  @override
  Future<({List<ScoreEntry> scores, List<Setlist> setlists})> restoreBackup(
    XFile source,
    List<ScoreEntry> scores,
    List<Setlist> setlists, {
    bool scorePackage = false,
  }) => Future.error(
    UnsupportedError('Library restore requires the installed app'),
  );

  @override
  Future<List<Setlist>> readSetlists() async => _setlists;

  @override
  Future<void> writeSetlists(List<Setlist> setlists) async {
    _setlists = List.unmodifiable(setlists);
  }

  @override
  Future<Map<String, dynamic>> readInk(String id) async => _ink[id] ?? {};

  @override
  Future<void> writeInk(String id, Map<String, dynamic> pages) async {
    _ink[id] = pages;
  }

  @override
  bool get persistent => false;

  @override
  Future<XFile?> latestBackup() async => null;

  @override
  Future<List<ScoreEntry>> readIndex() async => [];

  @override
  Future<void> writeIndex(List<ScoreEntry> entries) async {}

  @override
  Future<void> writeCatalog(List<ScoreEntry> entries, List<Setlist> setlists) =>
      writeSetlists(setlists);

  @override
  Future<XFile> copyScore(String id, XFile source) async {
    final copy = XFile.fromData(await source.readAsBytes(), name: source.name);
    _files[id] = copy;
    return copy;
  }

  @override
  Future<XFile> openScore(String id) async => _files[id]!;

  @override
  Future<void> removeScore(String id) async {
    _files.remove(id);
    _ink.remove(id);
  }
}
