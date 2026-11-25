import 'dart:io';

import 'package:archive/archive.dart';
import 'package:encoresheets/library_storage_native.dart';
import 'package:encoresheets/score_library.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'backup restores PDFs, annotations, pages and ordered setlists',
    () async {
      final root = await Directory.systemTemp.createTemp('encore_backup');
      addTearDown(() => root.delete(recursive: true));
      final original = ScoreLibrary(NativeLibraryStorage(directory: root));
      await original.load();
      final pdf = await File('assets/first_light.pdf').readAsBytes();
      final firstFile = await File('${root.path}/First.pdf').writeAsBytes(pdf);
      final secondFile = await File('${root.path}/Second.pdf').writeAsBytes(pdf);
      final (first, _) = await original.import(XFile(firstFile.path));
      final (second, _) = await original.import(XFile(secondFile.path));
      await original.record(second.id, 3);
      final annotation = {
        '3': [
          {
            'tool': 'highlighter',
            'points': [
              [.2, .3],
              [.4, .5],
            ],
          },
        ],
      };
      await original.writeInk(second.id, annotation);
      await original.saveSetlist(
        Setlist('evening', 'Evening set', [second.id, first.id, second.id]),
      );
      final backup = await original.createBackup();

      final target = await Directory('${root.path}/new-install').create();
      final restored = ScoreLibrary(NativeLibraryStorage(directory: target));
      await restored.load();
      expect(await restored.restoreBackup(backup), (scores: 2, setlists: 1));
      final reopened = ScoreLibrary(NativeLibraryStorage(directory: target));
      await reopened.load();
      final ids = reopened.setlists.single.scores;
      expect(ids.first, ids.last);
      expect(ids.map((id) => reopened.lookup(id)?.title), [
        'Second',
        'First',
        'Second',
      ]);
      expect(reopened.lookup(ids.first)?.page, 3);
      expect(await reopened.readInk(ids.first), annotation);
      expect(
        await (await reopened.storage.openScore(ids.first)).readAsBytes(),
        pdf,
      );

      expect(await reopened.restoreBackup(backup), (scores: 2, setlists: 1));
      expect(reopened.recent, hasLength(4));
      expect(reopened.setlists.first.scores, ids);
      expect(reopened.setlists.last.scores.first, isNot(ids.first));

      final originalEntries = ZipDecoder().decodeBytes(
        await backup.readAsBytes(),
      );
      final broken = Archive();
      for (final file in originalEntries) {
        if (file.name != 'scores/1.pdf') broken.add(file);
      }
      final badFile = await File('${root.path}/broken.zip')
          .writeAsBytes(ZipEncoder().encode(broken));
      final filesBefore = await Directory('${target.path}/scores')
          .list()
          .length;
      await expectLater(
        reopened.restoreBackup(XFile(badFile.path)),
        throwsFormatException,
      );
      expect(reopened.recent, hasLength(4));
      expect(
        await Directory('${target.path}/scores').list().length,
        filesBefore,
      );
    },
  );

  test('new catalog preserves indexes written by older versions', () async {
    final root = await Directory.systemTemp.createTemp('encore_legacy_catalog');
    addTearDown(() => root.delete(recursive: true));
    final path = await Directory('${root.path}/scores').create();
    await File('${path.path}/library.json').writeAsString(
      '[{"id":"42","title":"Old","page":3,"openedAt":"2026-01-01T00:00:00Z"}]',
    );
    await File('${path.path}/setlists.json')
        .writeAsString('[{"id":"old","name":"Old set","scores":["42"]}]');
    final library = ScoreLibrary(NativeLibraryStorage(directory: root));
    await library.load();
    await library.record('42', 2);
    final reopened = ScoreLibrary(NativeLibraryStorage(directory: root));
    await reopened.load();
    expect(reopened.lookup('42')?.page, 2);
    expect(reopened.setlists.single.scores, ['42']);
  });
}
