import 'dart:io';

import 'package:encoresheets/library_storage_native.dart';
import 'package:encoresheets/score_library.dart';
import 'package:encoresheets/wifi_library_sync.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encrypted pairing merges both libraries and keeps local ink', () async {
    final root = await Directory.systemTemp.createTemp('encoresheets-wifi');
    addTearDown(() => root.delete(recursive: true));
    final hostLibrary = ScoreLibrary(
      NativeLibraryStorage(directory: Directory('${root.path}/host')),
    );
    final joinLibrary = ScoreLibrary(
      NativeLibraryStorage(directory: Directory('${root.path}/join')),
    );
    final pdf = await File('assets/first_light.pdf').readAsBytes();
    final (a, _) = await hostLibrary.import(
      XFile.fromData(pdf, name: 'Host.pdf'),
    );
    final (b, _) = await joinLibrary.import(
      XFile.fromData(pdf, name: 'Join.pdf'),
    );
    await hostLibrary.updateScore(
      a.id,
      (score) => score.copyWith(title: 'Host'),
    );
    await joinLibrary.updateScore(
      b.id,
      (score) => score.copyWith(title: 'Join'),
    );
    await joinLibrary.saveSetlist(Setlist('program', 'Program', [b.id]));
    final marks = {
      '1': [
        {
          'tool': 'pen',
          'points': [
            [.1, .2],
            [.3, .4],
          ],
        },
      ],
    };
    await hostLibrary.writeInk(a.id, marks);

    final host = await WifiLibraryHost.start(
      (endpoint) async {
        await hostLibrary.synchronize(endpoint);
      },
      bindAddress: InternetAddress.loopbackIPv4,
      storeDirectory: Directory('${root.path}/exchange'),
    );
    addTearDown(host.close);
    final token = host.code.indexOf('/') + 1;
    final wrongCode = host.code.replaceRange(
      token,
      token + 1,
      host.code[token] == 'A' ? 'B' : 'A',
    );
    await expectLater(
      WifiLibraryPeer.connect(wrongCode, allowLoopback: true),
      throwsA(isA<WifiSyncException>()),
    );
    final peer = await WifiLibraryPeer.connect(host.code, allowLoopback: true);
    addTearDown(peer.close);
    await joinLibrary.synchronize(peer);
    await peer.complete();

    expect(hostLibrary.lookup(b.id)?.title, 'Join');
    expect(joinLibrary.lookup(a.id)?.title, 'Host');
    expect(hostLibrary.setlists.single.name, 'Program');
    expect(
      await (await hostLibrary.storage.openScore(b.id)).readAsBytes(),
      pdf,
    );
    expect(
      await (await joinLibrary.storage.openScore(a.id)).readAsBytes(),
      pdf,
    );
    expect(await hostLibrary.readInk(a.id), marks);
    expect(await joinLibrary.readInk(a.id), isEmpty);
    await joinLibrary.updateScore(
      a.id,
      (score) => score.copyWith(title: 'Updated'),
    );
    await joinLibrary.synchronize(peer);
    await peer.complete();
    expect(hostLibrary.lookup(a.id)?.title, 'Updated');
  });

  test(
    'personal pairing transfers markings and preserves offline conflicts',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'encore-personal-wifi',
      );
      addTearDown(() => root.delete(recursive: true));
      final first = ScoreLibrary(
        NativeLibraryStorage(directory: Directory('${root.path}/first')),
      );
      final second = ScoreLibrary(
        NativeLibraryStorage(directory: Directory('${root.path}/second')),
      );
      final (score, _) = await first.import(XFile('assets/first_light.pdf'));
      final baseInk = {
        '1': [
          {
            'tool': 'pen',
            'points': [
              [.1, .2],
            ],
          },
        ],
      };
      final firstEdit = {
        '1': [
          {
            'tool': 'pen',
            'points': [
              [.3, .4],
            ],
          },
        ],
      };
      final secondEdit = {
        '1': [
          {
            'tool': 'pen',
            'points': [
              [.5, .6],
            ],
          },
        ],
      };
      await first.writeInk(score.id, baseInk);
      await first.updateScore(
        score.id,
        (row) => row.copyWith(pageNotes: {1: 'Original note'}),
      );

      Future<void> pair() async {
        final host = await WifiLibraryHost.start(
          (endpoint) async {
            await first.synchronize(endpoint);
          },
          bindAddress: InternetAddress.loopbackIPv4,
          storeDirectory: Directory('${root.path}/exchange'),
          includeMarkings: true,
        );
        try {
          final peer = await WifiLibraryPeer.connect(
            host.code,
            allowLoopback: true,
          );
          try {
            expect(peer.includesMarkings, isTrue);
            await second.synchronize(peer);
            await peer.complete();
          } finally {
            peer.close();
          }
        } finally {
          await host.close();
        }
      }

      await pair();
      expect(await second.readInk(score.id), baseInk);
      expect(second.lookup(score.id)?.pageNotes, {1: 'Original note'});
      await first.writeInk(score.id, firstEdit);
      await first.updateScore(
        score.id,
        (row) => row.copyWith(pageNotes: {1: 'First device'}),
      );
      await second.writeInk(score.id, secondEdit);
      await second.updateScore(
        score.id,
        (row) => row.copyWith(pageNotes: {1: 'Second device'}),
      );
      await pair();

      expect(await first.readInk(score.id), secondEdit);
      expect(first.lookup(score.id)?.pageNotes, {1: 'Second device'});
      final alternate = second.recentlyUpdated.single;
      expect(alternate.pageNotes, {1: 'First device'});
      expect(await second.readInk(alternate.id), firstEdit);
    },
  );
}
