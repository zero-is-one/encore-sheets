import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:encoresheets/library_storage_native.dart';
import 'package:encoresheets/score_action.dart';
import 'package:encoresheets/score_library.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('automatically recovers the latest verified catalog or its prior generation', () async {
    final root = await Directory.systemTemp.createTemp(
      'encore_catalog_recovery',
    );
    addTearDown(() => root.delete(recursive: true));
    ScoreLibrary open() => ScoreLibrary(NativeLibraryStorage(directory: root));
    final original = open();
    final (score, _) = await original.import(XFile('assets/first_light.pdf'));
    await original.saveSetlist(Setlist('program', 'Program', [score.id]));
    await original.updatePreferences({'landscapeWidth': true});

    final catalog = File('${root.path}/scores/catalog.json');
    final latest = File('${root.path}/scores/catalog-recovery.json');
    await catalog.writeAsString('{"scores":[],"setlists":"damaged"}');
    final recovered = open();
    await recovered.load();
    expect(recovered.lookup(score.id)?.title, score.title);
    expect(recovered.setlists.single.scores, [score.id]);
    expect(
      (await recovered.storage.readPreferences())['landscapeWidth'],
      isTrue,
    );
    expect(jsonDecode(await catalog.readAsString())['scores'], hasLength(1));

    final tampered =
        jsonDecode(await latest.readAsString()) as Map<String, dynamic>;
    tampered['catalog'] = '{"scores":[],"setlists":[]}';
    await latest.writeAsString(jsonEncode(tampered));
    await catalog.delete();
    final fallback = open();
    await fallback.load();
    expect(fallback.setlists.single.scores, [score.id]);
    expect(fallback.lookup(score.id), isNotNull);
    expect(
      (await fallback.storage.readPreferences())['landscapeWidth'],
      isNull,
    );
    final fullBackup = await fallback.createBackup();
    final metadataBackup = await fallback.createBackup(includeScores: false);
    await catalog.writeAsString('broken catalog');
    final prior = File('${root.path}/scores/catalog-recovery-previous.json');
    await prior.writeAsString('bad checksum envelope');
    final manual = open();
    await expectLater(
      manual.load(),
      throwsA(isA<LibraryCatalogRecoveryRequired>()),
    );
    await expectLater(
      manual.restoreBackup(metadataBackup),
      throwsFormatException,
    );
    expect(await catalog.readAsString(), 'broken catalog');
    expect(await manual.restoreBackup(fullBackup), (scores: 1, setlists: 1));
    await manual.load();
    expect(manual.setlists.single.scores, [manual.recent.single.id]);
    expect(
      await Directory('${root.path}/scores')
          .list()
          .any((entry) => entry.path.contains('catalog-damaged-')),
      isTrue,
    );
  });

  test(
    'backup settings restore is optional and device-only settings stay local',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'encore_backup_settings',
      );
      addTearDown(() => root.delete(recursive: true));
      final source = ScoreLibrary(NativeLibraryStorage(directory: root));
      await source.updatePreferences({
        'landscapeWidth': true,
        'readerLanguage': 'fr',
        'assistantConnection': {'token': 'secret'},
        'sharedLibrarySync-folder': {'device': 'source-device'},
      });
      final backup = await source.createBackup();
      final archive = ZipDecoder().decodeBytes(await backup.readAsBytes());
      final manifest = jsonDecode(
        utf8.decode(archive.find('manifest.json')!.content),
      ) as Map<String, dynamic>;
      expect(manifest['preferencesVersion'], 1);
      expect(manifest['preferences'], {
        'landscapeWidth': true,
        'readerLanguage': 'fr',
      });

      final target = ScoreLibrary(
        NativeLibraryStorage(directory: Directory('${root.path}/target')),
      );
      await target.updatePreferences({
        'readerLanguage': 'en',
        'assistantConnection': {'token': 'local-token'},
      });
      await target.restoreBackup(backup, restoreSettings: false);
      expect((await target.storage.readPreferences())['readerLanguage'], 'en');
      await target.restoreBackup(backup);
      final preferences = await target.storage.readPreferences();
      expect(preferences['readerLanguage'], 'fr');
      expect(preferences['landscapeWidth'], isTrue);
      expect(preferences['assistantConnection'], {'token': 'local-token'});
      expect(preferences['sharedLibrarySync-folder'], isNull);

      final legacy = Archive()
        ..add(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode(manifest..remove('preferencesVersion')),
          ),
        );
      final legacyFile = await File('${root.path}/legacy.zip')
          .writeAsBytes(ZipEncoder().encode(legacy));
      expect(await target.restoreBackup(XFile(legacyFile.path)), (
        scores: 0,
        setlists: 0,
      ));
    },
  );

  test(
    'editable score packages retain and enforce their access deadline',
    () async {
      final folder = await Directory.systemTemp.createTemp('encore_expiry');
      addTearDown(() => folder.delete(recursive: true));
      final library = ScoreLibrary(NativeLibraryStorage(directory: folder));
      final (score, _) = await library.import(XFile('assets/first_light.pdf'));
      final future = DateTime.now().toUtc().add(const Duration(days: 7));
      final shared = await library.createScorePackage(
        score.copyWith(validUntil: future),
      );
      final restored = await library.restoreScorePackage(shared);
      expect(restored.validUntil, future);
      final expired = await library.createScorePackage(
        score.copyWith(
          validUntil: DateTime.now().toUtc().subtract(const Duration(days: 1)),
        ),
      );
      await expectLater(
        library.restoreScorePackage(expired),
        throwsFormatException,
      );
    },
  );
  test(
    'backup restores PDFs, annotations, pages and ordered setlists',
    () async {
      final root = await Directory.systemTemp.createTemp('encore_backup');
      addTearDown(() => root.delete(recursive: true));
      final original = ScoreLibrary(NativeLibraryStorage(directory: root));
      await original.load();
      final pdf = await File('assets/first_light.pdf').readAsBytes();
      final firstFile = await File('${root.path}/First.pdf').writeAsBytes(pdf);
      final secondFile = await File('${root.path}/Second.pdf')
          .writeAsBytes(pdf);
      final (first, _) = await original.import(XFile(firstFile.path));
      final (second, _) = await original.import(XFile(secondFile.path));
      await original.record(second.id, 3);
      const movement = ScoreBookmark('movement', 'Movement', 2, endPage: 3);
      await original.updateScore(
        second.id,
        (score) => score.copyWith(
          bookmarks: [movement],
          flags: [3],
          jumps: const [
            ScoreJump('Repeat', JumpPoint(3, .4, .6), JumpPoint(2, .2, .4)),
          ],
          halfSplits: {2: .6},
          actions: [
            ScoreAction(
              title: 'Open first score',
              page: 3,
              x: .3,
              y: .4,
              color: 0xff254a73,
              kind: ScoreActionKind.score,
              selection: first.id,
            ),
          ],
        ),
      );
      await original.createCollection('Choir');
      await original.createCollection('Empty library');
      await original.updatePreferences({
        'landscapeWidth': true,
        'scoreTabs': [first.id, movement.selectionId(second.id)],
        'scoreTabPages': {movement.selectionId(second.id): 3},
        'personalStamps': ['dolce'],
      });
      await original.assignCollections(second.id, ['Choir']);
      final annotation = {
        'layers': [
          {'id': 'base', 'name': 'Annotations', 'visible': true},
          {
            'id': 'practice',
            'name': 'Practice',
            'visible': true,
            'active': true,
          },
        ],
        '3': [
          {
            'tool': 'highlighter',
            'width': .02,
            'color': 0x663391ff,
            'points': [
              [.2, .3],
              [.4, .5],
            ],
          },
          {
            'tool': 'text',
            'text': 'Bring out the melody',
            'layer': 'practice',
            'width': .03,
            'points': [
              [.12, .65],
            ],
          },
        ],
      };
      await original.writeInk(second.id, annotation);
      await original.saveSetlist(
        Setlist('evening', 'Evening set', [
          second.id,
          first.id,
          movement.selectionId(second.id),
        ]),
      );
      final backup = await original.createBackup();
      final scorePackage = await original.createScorePackage(
        original.lookup(second.id)!,
      );
      expect(scorePackage.name, endsWith('.encorescore.zip'));

      final target = await Directory('${root.path}/new-install').create();
      final restored = ScoreLibrary(NativeLibraryStorage(directory: target));
      await restored.load();
      final packageTarget = ScoreLibrary(
        NativeLibraryStorage(
          directory: await Directory('${root.path}/package-install').create(),
        ),
      );
      final packaged = await packageTarget.restoreScorePackage(scorePackage);
      expect(packaged.title, 'Second');
      expect(packaged.bookmarks.single.title, 'Movement');
      expect(await packageTarget.readInk(packaged.id), annotation);
      expect(packageTarget.setlists, isEmpty);
      expect(await restored.restoreBackup(backup), (scores: 2, setlists: 1));
      final reopened = ScoreLibrary(NativeLibraryStorage(directory: target));
      await reopened.load();
      final ids = reopened.setlists.single.scores;
      expect(reopened.lookupSelection(ids.last)?.$1.id, ids.first);
      expect(reopened.lookupSelection(ids.last)?.$2?.endPage, 3);
      final score = reopened.lookup(ids.first)!;
      expect(score.collections, ['Choir']);
      expect(reopened.collections, ['Choir', 'Empty library']);
      final preferences = await reopened.storage.readPreferences();
      expect(preferences['landscapeWidth'], isTrue);
      expect(preferences['scoreTabs'], [ids[1], ids.last]);
      expect(preferences['scoreTabPages'], {ids.last: 3});
      expect(preferences['personalStamps'], ['dolce']);
      expect(score.flags, [3]);
      expect(score.jumps.single.target.page, 2);
      expect(score.halfSplits, {2: .6});
      expect(score.actions.single.selection, ids[1]);
      final originalReopened = ScoreLibrary(
        NativeLibraryStorage(directory: root),
      );
      await originalReopened.load();
      expect(originalReopened.collections, ['Choir', 'Empty library']);
      expect(ids.map((id) => reopened.lookupSelection(id)?.$1.title), [
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
