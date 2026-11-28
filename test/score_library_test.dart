import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encoresheets/page_crop.dart';
import 'package:encoresheets/library_storage_native.dart';
import 'package:encoresheets/library_sync.dart';
import 'package:encoresheets/score_library.dart';
import 'package:encoresheets/webdav_library_sync.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
  test('the editable sample is seeded once and stays deleted', () async {
    final folder = await Directory.systemTemp.createTemp('encore_sample');
    addTearDown(() => folder.delete(recursive: true));
    final library = ScoreLibrary(NativeLibraryStorage(directory: folder));
    Future<XFile> samplePdf() async => XFile.fromData(
      await File('assets/first_light.pdf').readAsBytes(),
      name: 'First Light.pdf',
    );

    await library.load();
    await Future.wait([
      library.seedSampleScore(samplePdf),
      library.seedSampleScore(samplePdf),
    ]);
    final sample = library.recent.single;
    expect(sample.title, 'First Light');
    expect(sample.isSample, isTrue);
    expect(await library.storage.openScore(sample.id), isA<XFile>());
    await library.savePageNote(sample.id, 1, 'Rehearse slowly');

    final reopened = ScoreLibrary(NativeLibraryStorage(directory: folder));
    await reopened.load();
    expect(reopened.recent.single.pageNotes[1], 'Rehearse slowly');
    await reopened.trashScores([sample.id]);

    final afterDeletion = ScoreLibrary(NativeLibraryStorage(directory: folder));
    await afterDeletion.load();
    await afterDeletion.seedSampleScore(samplePdf);
    expect(afterDeletion.recent, isEmpty);
    expect(afterDeletion.recentlyDeleted.single.id, sample.id);
  });

  test(
    'shared WebDAV merges offline edits and keeps personal markup local',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'encore_shared_sync',
      );
      addTearDown(() => folder.delete(recursive: true));
      final first = ScoreLibrary(
        NativeLibraryStorage(directory: Directory('${folder.path}/first')),
      );
      final second = ScoreLibrary(
        NativeLibraryStorage(directory: Directory('${folder.path}/second')),
      );
      final files = <String, Uint8List>{};
      final manifests = <String>[];
      WebDavLibrarySync connect(String username) {
        final endpoint = WebDavLibrarySync(
          'https://dav.example.test/Ensemble%20Library/',
          username: username,
          password: 'test-password',
          client: MockClient((request) async {
            expect(request.url.host, 'dav.example.test');
            expect(request.followRedirects, isFalse);
            expect(
              request.headers['authorization'],
              'Basic ${base64Encode(utf8.encode('$username:test-password'))}',
            );
            final path = request.url.path;
            if (request.method == 'PROPFIND') {
              expect(request.headers['depth'], '1');
              final rows =
                  [
                        ...files.keys,
                        'https://other.example.test/Ensemble%20Library/encoresheets-shared-v1-device-stray.json',
                        '/other/encoresheets-shared-v1-device-stray.json',
                      ]
                      .map(
                        (href) =>
                            '<D:response><D:href>$href</D:href></D:response>',
                      )
                      .join();
              return http.Response(
                '<D:multistatus xmlns:D="DAV:">$rows</D:multistatus>',
                207,
              );
            }
            if (request.method == 'GET') {
              return http.Response.bytes(files[path]!, 200);
            }
            expect(request.method, 'PUT');
            if (path.endsWith('.pdf')) {
              expect(request.headers['if-none-match'], '*');
              if (files.containsKey(path)) return http.Response('', 412);
            } else {
              manifests.add(utf8.decode(request.bodyBytes));
            }
            files[path] = request.bodyBytes;
            return http.Response('', 201);
          }),
        );
        addTearDown(endpoint.close);
        return endpoint;
      }

      final a = connect('first');
      final b = connect('second');
      final (score, _) = await first.import(XFile('assets/first_light.pdf'));
      await first.editMetadata(score.id, score.title, {
        'composer': 'Original',
        'genre': 'Old genre',
      });
      await first.saveSetlist(Setlist('program', 'Concert', [score.id]));
      await first.savePageNote(score.id, 2, 'private-first');
      final firstInk = {
        '1': [
          {
            'tool': 'pen',
            'points': [
              [.21, .52],
            ],
          },
        ],
      };
      final secondInk = {
        '2': [
          {
            'tool': 'pen',
            'points': [
              [.31, .62],
            ],
          },
        ],
      };
      await first.writeInk(score.id, firstInk);

      await first.synchronize(a);
      expect(await second.synchronize(b), {score.id});
      expect(await second.readInk(score.id), isEmpty);
      expect(second.lookup(score.id)?.pageNotes, isEmpty);
      expect(second.setlists.single.scores, [score.id]);
      expect(
        await (await second.storage.openScore(score.id)).readAsBytes(),
        await File('assets/first_light.pdf').readAsBytes(),
      );

      await first.editMetadata(score.id, 'New title', {
        'composer': 'New composer',
      });
      await second.editMetadata(score.id, score.title, {
        'genre': '',
        'tags': 'New tag',
      });
      await second.savePageNote(score.id, 2, 'private-second');
      await second.writeInk(score.id, secondInk);
      await first.synchronize(a);
      await second.synchronize(b);
      await first.synchronize(a);

      for (final library in [first, second]) {
        expect(library.lookup(score.id)?.title, 'New title');
        expect(library.lookup(score.id)?.metadata, {
          'composer': 'New composer',
          'tags': 'New tag',
        });
      }
      expect(first.lookup(score.id)?.pageNotes, {2: 'private-first'});
      expect(second.lookup(score.id)?.pageNotes, {2: 'private-second'});
      expect(await first.readInk(score.id), firstInk);
      expect(await second.readInk(score.id), secondInk);
      expect(manifests.join(), isNot(contains('private-')));
      expect(manifests.join(), isNot(contains('"points"')));
      final writes = manifests.length;
      expect(await first.synchronize(a), isEmpty);
      expect(await second.synchronize(b), isEmpty);
      expect(manifests.length, writes);
      expect(files.keys.where((path) => path.endsWith('.pdf')), hasLength(1));
    },
  );

  test('page notes survive reopen and can be removed without affecting other pages', () async {
    final folder = await Directory.systemTemp.createTemp('encore_page_notes');
    addTearDown(() => folder.delete(recursive: true));
    final library = ScoreLibrary(NativeLibraryStorage(directory: folder));
    final (score, _) = await library.import(XFile('assets/first_light.pdf'));
    await library.savePageNote(score.id, 1, ' Breathe before the repeat. ');
    await library.savePageNote(score.id, 2, 'Play under the solo.');
    final reopened = ScoreLibrary(NativeLibraryStorage(directory: folder));
    await reopened.load();
    expect(reopened.lookup(score.id)?.pageNotes, {
      1: 'Breathe before the repeat.',
      2: 'Play under the solo.',
    });
    await reopened.savePageNote(score.id, 1, '');
    expect(reopened.lookup(score.id)?.pageNotes, {2: 'Play under the solo.'});
  });

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

  test(
    'restores crop versions with annotations, bookmarks and setlist references',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'encore_versions',
      );
      addTearDown(() => directory.delete(recursive: true));
      final library = ScoreLibrary(NativeLibraryStorage(directory: directory));
      final (score, _) = await library.import(XFile('assets/first_light.pdf'));
      const bookmark = ScoreBookmark('section', 'Section', 2, endPage: 3);
      await library.updateScore(
        score.id,
        (entry) => entry.copyWith(bookmarks: [bookmark]),
      );
      await library.saveSetlist(
        Setlist('concert', 'Concert', [bookmark.selectionId(score.id)]),
      );
      final ink = {
        '2': [
          {
            'tool': 'pen',
            'points': [
              [.15, .2],
            ],
          },
        ],
      };
      await library.writeInk(score.id, ink);
      await library.saveCrop(score.id, {2: const PageCrop(left: .1)});

      final reopened = ScoreLibrary(NativeLibraryStorage(directory: directory));
      await reopened.load();
      final version = reopened.recentlyUpdated.single;
      expect(reopened.recentlyDeleted, isEmpty);
      final copy = await reopened.restoreScoreVersion(
        version.id,
        replace: false,
      );
      expect(copy.crops, isEmpty);
      expect(copy.bookmarks.single.page, 2);
      expect(await reopened.readInk(copy.id), ink);
      final restored = await reopened.restoreScoreVersion(
        version.id,
        replace: true,
      );
      expect(reopened.lookup(score.id), isNull);
      expect(reopened.setlists.single.scores, [
        bookmark.selectionId(restored.id),
      ]);
      expect(reopened.replacementFor(version)?.id, restored.id);
    },
  );

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
    expect(a.addedAt, isNotNull);
    expect(b.addedAt, isNotNull);
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
    expect(restored.lookup(a.id)?.addedAt, a.addedAt);
    expect(restored.lookup(b.id)?.addedAt, b.addedAt);
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
