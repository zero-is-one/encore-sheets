import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import 'score_library.dart';

LibraryStorage createStorage() => NativeLibraryStorage();

class NativeLibraryStorage implements LibraryStorage {
  NativeLibraryStorage({Directory? directory}) : _override = directory;

  final Directory? _override;
  late final Future<Directory> _root = _prepare();

  @override
  bool get persistent => true;

  Future<Directory> _prepare() async {
    final documents = _override ?? await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/scores').create(recursive: true);
  }

  Future<File> _file(String name) async => File('${(await _root).path}/$name');

  @override
  Future<List<ScoreEntry>> readIndex() async {
    final file = await _file('library.json');
    if (!await file.exists()) return [];
    final rows = jsonDecode(await file.readAsString()) as List<dynamic>;
    return [
      for (final row in rows) ScoreEntry.fromJson(row as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> writeIndex(List<ScoreEntry> entries) async {
    await _writeJson(
      'library.json',
      entries.map((entry) => entry.toJson()).toList(),
    );
  }

  Future<void> _writeJson(String name, Object value) async {
    final file = await _file(name);
    final staged = await _file('$name.tmp');
    await staged.writeAsString(jsonEncode(value), flush: true);
    await staged.rename(file.path);
  }

  @override
  Future<Map<String, dynamic>> readInk(String id) async {
    final file = await _file('$id.ink.json');
    if (!await file.exists()) return {};
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  @override
  Future<void> writeInk(String id, Map<String, dynamic> pages) =>
      _writeJson('$id.ink.json', pages);

  @override
  Future<List<Setlist>> readSetlists() async {
    final file = await _file('setlists.json');
    if (!await file.exists()) return [];
    final rows = jsonDecode(await file.readAsString()) as List<dynamic>;
    return [
      for (final row in rows) Setlist.fromJson(row as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> writeSetlists(List<Setlist> setlists) => _writeJson(
    'setlists.json',
    setlists.map((setlist) => setlist.toJson()).toList(),
  );

  @override
  Future<XFile> copyScore(String id, XFile source) async {
    final destination = await _file('$id.pdf');
    final staged = await _file('$id.pdf.tmp');
    try {
      await source.saveTo(staged.path);
      await staged.rename(destination.path);
      return XFile(destination.path);
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }

  @override
  Future<XFile> openScore(String id) async {
    final file = await _file('$id.pdf');
    if (!await file.exists())
      throw FileSystemException('Score is missing', file.path);
    return XFile(file.path);
  }

  @override
  Future<void> removeScore(String id) async {
    final file = await _file('$id.pdf');
    if (await file.exists()) await file.delete();
  }
}
