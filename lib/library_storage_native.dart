import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import 'score_library.dart';

part 'library_backup_native.dart';

LibraryStorage createStorage() => NativeLibraryStorage();

class NativeLibraryStorage implements LibraryStorage {
  NativeLibraryStorage({Directory? directory}) : _override = directory;

  final Directory? _override;
  late final Future<Directory> _root = _prepare();

  @override
  bool get persistent => true;

  @override
  Future<Map<String, dynamic>> readPreferences() async {
    final catalog = await _readCatalog();
    if (catalog?['preferences'] case final Map<String, dynamic> preferred) {
      return preferred;
    }
    final file = await _file('reader-preferences.json');
    return await file.exists()
        ? jsonDecode(await file.readAsString()) as Map<String, dynamic>
        : {};
  }

  @override
  Future<void> writePreferences(Map<String, dynamic> preferences) async =>
      _writeJson(
        'catalog.json',
        _catalog(
          await readIndex(),
          await readSetlists(),
          preferences: preferences,
        ),
      );

  Future<Directory> _prepare() async {
    final documents = _override ?? await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/scores').create(recursive: true);
  }

  Future<File> _file(String name) async => File('${(await _root).path}/$name');

  @override
  Future<List<ScoreEntry>> readIndex() async {
    final catalog = await _readCatalog();
    final file = await _file('library.json');
    final rows =
        catalog?['scores'] as List<dynamic>? ??
        (await file.exists()
            ? jsonDecode(await file.readAsString()) as List<dynamic>
            : []);
    return [
      for (final row in rows) ScoreEntry.fromJson(row as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> writeIndex(List<ScoreEntry> entries) async =>
      writeCatalog(entries, await readSetlists());

  Future<Map<String, dynamic>?> _readCatalog() async {
    final file = await _file('catalog.json');
    return await file.exists()
        ? jsonDecode(await file.readAsString()) as Map<String, dynamic>
        : null;
  }

  @override
  Future<void> writeCatalog(
    List<ScoreEntry> scores,
    List<Setlist> setlists,
  ) async => _writeJson(
    'catalog.json',
    _catalog(scores, setlists, preferences: await readPreferences()),
  );

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
  Future<void> writeInk(String id, Map<String, dynamic> pages) {
    _validateInk(pages);
    return _writeJson('$id.ink.json', pages);
  }

  @override
  Future<List<Setlist>> readSetlists() async {
    final catalog = await _readCatalog();
    final file = await _file('setlists.json');
    final rows =
        catalog?['setlists'] as List<dynamic>? ??
        (await file.exists()
            ? jsonDecode(await file.readAsString()) as List<dynamic>
            : []);
    return [
      for (final row in rows) Setlist.fromJson(row as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> writeSetlists(List<Setlist> setlists) async =>
      writeCatalog(await readIndex(), setlists);

  @override
  Future<XFile> createBackup(
    List<ScoreEntry> scores,
    List<Setlist> setlists,
  ) async {
    final temp = _override ?? await getTemporaryDirectory();
    final folder = await temp.createTemp('encoresheets-backup-');
    final path =
        '${folder.path}/EncoreSheets-${DateTime.now().millisecondsSinceEpoch}.zip';
    final root = (await _root).path;
    final preferences = (await readPreferences())..remove('librarySyncState');
    await Isolate.run(
      () =>
          _exportBackup(root, path, scores, setlists, preferences: preferences),
    );
    final staged = await File(path).copy('$root/latest-backup.zip.tmp');
    await staged.rename('$root/latest-backup.zip');
    return XFile(path, mimeType: 'application/zip');
  }

  @override
  Future<XFile?> latestBackup() async {
    final file = await _file('latest-backup.zip');
    return await file.exists()
        ? XFile(file.path, mimeType: 'application/zip')
        : null;
  }

  @override
  Future<XFile> createScorePackage(
    ScoreEntry score, {
    XFile? extractedPdf,
    Map<String, dynamic>? extractedInk,
  }) async {
    final temp = _override ?? await getTemporaryDirectory();
    final folder = await temp.createTemp('encoresheets-package-');
    final safeTitle = score.title
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim();
    final path =
        '${folder.path}/${safeTitle.isEmpty ? 'Score' : safeTitle}.encorescore.zip';
    final files = <File>[];
    try {
      var root = (await _root).path;
      if (extractedPdf != null) {
        root = folder.path;
        final pdf = File('$root/${score.id}.pdf');
        files.add(pdf);
        await extractedPdf.saveTo(pdf.path);
        if (extractedInk?.isNotEmpty == true) {
          final ink = File('$root/${score.id}.ink.json');
          files.add(ink);
          await ink.writeAsString(jsonEncode(extractedInk), flush: true);
        }
      }
      final packaged = extractedPdf == null
          ? score
          : score.copyWith(detachPdf: true);
      await Isolate.run(
        () => _exportBackup(
          root,
          path,
          [packaged],
          [],
          kind: LibraryArchive.score,
        ),
      );
      return XFile(path, mimeType: 'application/zip');
    } finally {
      for (final file in files) {
        if (await file.exists()) await file.delete();
      }
    }
  }

  @override
  Future<XFile> createSetlistPackage(
    Setlist setlist,
    List<ScoreEntry> scores, {
    required String name,
    required bool includeScores,
  }) async {
    final temp = _override ?? await getTemporaryDirectory();
    final folder = await temp.createTemp('encoresheets-setlist-');
    final path = '${folder.path}/$name.encoreset.zip';
    final root = (await _root).path;
    await Isolate.run(
      () => _exportBackup(
        root,
        path,
        scores,
        [setlist],
        kind: LibraryArchive.setlist,
        includeScores: includeScores,
      ),
    );
    return XFile(path, mimeType: 'application/zip');
  }

  @override
  Future<({List<ScoreEntry> scores, List<Setlist> setlists})> restoreBackup(
    XFile source,
    List<ScoreEntry> scores,
    List<Setlist> setlists, {
    LibraryArchive kind = LibraryArchive.library,
  }) async {
    final root = (await _root).path;
    final path = source.path;
    final existingPreferences = await readPreferences();
    return Isolate.run(
      () => _restoreBackup(
        root,
        path,
        scores,
        setlists,
        kind: kind,
        existingPreferences: existingPreferences,
      ),
    );
  }

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
    final scores = await readIndex();
    final source =
        scores.where((score) => score.id == id).firstOrNull?.storedPdfId ?? id;
    final file = await _file('$source.pdf');
    if (!await file.exists())
      throw FileSystemException('Score is missing', file.path);
    return XFile(file.path);
  }

  @override
  Future<void> removeScore(String id) async {
    for (final name in ['$id.pdf', '$id.ink.json']) {
      final file = await _file(name);
      if (await file.exists()) await file.delete();
    }
  }
}
