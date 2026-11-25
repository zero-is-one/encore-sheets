import 'package:file_selector/file_selector.dart';

import 'score_library.dart';

LibraryStorage createStorage() => _MemoryLibraryStorage();

class _MemoryLibraryStorage implements LibraryStorage {
  final _files = <String, XFile>{};
  final _ink = <String, Map<String, dynamic>>{};
  List<Setlist> _setlists = [];

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
  Future<List<ScoreEntry>> readIndex() async => [];

  @override
  Future<void> writeIndex(List<ScoreEntry> entries) async {}

  @override
  Future<XFile> copyScore(String id, XFile source) async {
    final copy = XFile.fromData(await source.readAsBytes(), name: source.name);
    _files[id] = copy;
    return copy;
  }

  @override
  Future<XFile> openScore(String id) async => _files[id]!;

  @override
  Future<void> removeScore(String id) async => _files.remove(id);
}
