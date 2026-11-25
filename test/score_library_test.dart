import 'dart:io';

import 'package:encoresheets/library_storage_native.dart';
import 'package:encoresheets/library_sync.dart';
import 'package:encoresheets/score_library.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestEndpoint implements LibrarySyncEndpoint {
  final devices = <String, Map<String, dynamic>>{};
  final pdfs = <String, XFile>{};

  @override
  Future<XFile> fetchPdf(String id) async => pdfs[id]!;

  @override
  Future<void> publishPdf(String id, XFile file) async {
    pdfs[id] = XFile.fromData(await file.readAsBytes(), name: file.name);
  }

  @override
  Future<Map<String, Map<String, dynamic>>> readDevices() async => devices;

  @override
  Future<void> writeDevice(String device, Map<String, dynamic> records) async {
    devices[device] = records;
  }
}

void main() {
  test(
    'score copies share their PDF and keep independent saved markup',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'encore_score_clone',
      );
      addTearDown(() => folder.delete(recursive: true));
      final library = ScoreLibrary(NativeLibraryStorage(directory: folder));
      final (original, _) = await library.import(
        XFile('assets/first_light.pdf'),
      );
      final marks = {
        '1': [
          {
            'tool': 'pen',
            'points': [
              [.2, .5],
            ],
          },
        ],
      };
      await library.writeInk(original.id, marks);
      final duplicate = await library.duplicateScore(original.id);
      final secondDuplicate = await library.duplicateScore(duplicate.id);
      expect(secondDuplicate.storedPdfId, original.id);
      expect(
        (await library.storage.openScore(duplicate.id)).path,
        (await library.storage.openScore(original.id)).path,
      );
      expect(await library.readInk(duplicate.id), marks);
      await library.writeInk(duplicate.id, {});
      expect(await library.readInk(original.id), marks);
      final package = await library.createScorePackage(duplicate);
      final restored = await library.restoreScorePackage(package);
      expect(restored.pdfSourceId, isNull);
      expect(
        await (await library.storage.openScore(restored.id)).readAsBytes(),
        await (await library.storage.openScore(original.id)).readAsBytes(),
      );
    },
  );

  test('syncs score files, markup, edits, and deletions without creating duplicates', () async {
    final folder = await Directory.systemTemp.createTemp('encore_sync_test');
    addTearDown(() => folder.delete(recursive: true));
    final first = ScoreLibrary(
      NativeLibraryStorage(directory: Directory('${folder.path}/first')),
    );
    final second = ScoreLibrary(
      NativeLibraryStorage(directory: Directory('${folder.path}/second')),
    );
    final endpoint = _TestEndpoint();
    final (score, _) = await first.import(XFile('assets/first_light.pdf'));
    await first.writeInk(score.id, {
      '2': [
        {
          'tool': 'pen',
          'points': [
            [.15, .2],
          ],
        },
      ],
    });
    await first.saveSetlist(Setlist('practice', 'Practice', [score.id]));

    await first.synchronize(endpoint);
    expect(await second.synchronize(endpoint), {score.id});
    expect(await second.readInk(score.id), await first.readInk(score.id));
    expect(second.setlists.single.scores, [score.id]);
    expect(
      await (await second.storage.openScore(score.id)).readAsBytes(),
      await File('assets/first_light.pdf').readAsBytes(),
    );
    await second.editMetadata(score.id, 'Rehearsal', {});
    await second.synchronize(endpoint);
    await first.synchronize(endpoint);
    expect(first.recent.single.title, 'Rehearsal');
    expect(await first.synchronize(endpoint), isEmpty);

    await first.trashScores([score.id]);
    await first.synchronize(endpoint);
    await second.synchronize(endpoint);
    expect(second.recent, isEmpty);
    expect(second.recentlyDeleted.single.id, score.id);
    await second.recoverScore(score.id);
    await second.synchronize(endpoint);
    await first.synchronize(endpoint);
    expect(first.recent.single.id, score.id);
  });

  test('recovers a deleted score with its PDF and setlist reference', () async {
    final directory = await Directory.systemTemp.createTemp(
      'encoresheets_test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = await File('${directory.path}/Music.pdf')
        .writeAsString('music');
    final library = ScoreLibrary(NativeLibraryStorage(directory: directory));
    final (score, _) = await library.import(XFile(source.path));
    await library.saveSetlist(Setlist('concert', 'Concert', [score.id]));
    await library.trashScores([score.id]);

    final reopened = ScoreLibrary(NativeLibraryStorage(directory: directory));
    await reopened.load();
    expect(reopened.recent, isEmpty);
    expect(reopened.lookupSelection(score.id), isNull);
    expect(reopened.recentlyDeleted.single.id, score.id);
    await reopened.recoverScore(score.id);
    expect(reopened.recent.single.id, score.id);
    expect(reopened.setlists.single.scores, [score.id]);
    expect(
      await (await reopened.storage.openScore(score.id)).readAsString(),
      'music',
    );
  });

  test('copies two scores and restores separate page positions', () async {
    final directory = await Directory.systemTemp.createTemp(
      'encoresheets_test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final first = await File('${directory.path}/First.pdf')
        .writeAsString('first');
    final second = await File('${directory.path}/Second.pdf')
        .writeAsString('second');

    final library = ScoreLibrary(NativeLibraryStorage(directory: directory));
    await library.load();
    final [(a, aCopy), (b, bCopy)] = await Future.wait([
      library.import(XFile(first.path)),
      library.import(XFile(second.path)),
    ]);
    expect(a.id, isNot(b.id));
    expect(aCopy.path, isNot(first.path));
    expect(bCopy.path, isNot(second.path));
    await first.delete();
    await second.delete();
    await Future.wait([
      library.record(a.id, 2),
      library.record(b.id, 3),
      library.record(a.id, 4, opened: true),
    ]);

    final restored = ScoreLibrary(NativeLibraryStorage(directory: directory));
    await restored.load();
    expect(restored.recent.map((score) => score.title), ['First', 'Second']);
    expect(restored.lookup(a.id)?.page, 4);
    expect(restored.lookup(b.id)?.page, 3);
    expect(
      await (await restored.storage.openScore(a.id)).readAsString(),
      'first',
    );
    expect(
      await (await restored.storage.openScore(b.id)).readAsString(),
      'second',
    );
  });
}
