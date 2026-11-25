import 'dart:io';

import 'package:encoresheets/library_storage_native.dart';
import 'package:encoresheets/score_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'duplicates a setlist into its folder while preserving repeated scores',
    () async {
      final root = await Directory.systemTemp.createTemp('encore_setlists');
      addTearDown(() => root.delete(recursive: true));
      final library = ScoreLibrary(NativeLibraryStorage(directory: root));
      final original = Setlist('concert', 'Concert', [
        'a',
        'b',
        'a',
      ], folder: 'Spring');
      await library.saveSetlist(original);
      await library.duplicateSetlist(original);
      await library.duplicateSetlist(original);
      final reopened = ScoreLibrary(NativeLibraryStorage(directory: root));
      await reopened.load();
      expect(reopened.setlists.map((list) => list.folder), [
        'Spring',
        'Spring',
        'Spring',
      ]);
      expect(reopened.setlists.map((list) => list.name), [
        'Concert',
        'Concert copy',
        'Concert copy 2',
      ]);
      expect(reopened.setlists.last.scores, ['a', 'b', 'a']);
      expect(reopened.setlists.map((list) => list.id).toSet(), hasLength(3));
    },
  );

  test('setlist order, repeated scores, and edits survive reopening', () async {
    final root = await Directory.systemTemp.createTemp('encore_setlists');
    addTearDown(() => root.delete(recursive: true));
    final library = ScoreLibrary(NativeLibraryStorage(directory: root));
    await library.load();
    expect(library.setlists, isEmpty);

    await library.saveSetlist(Setlist('concert', 'Concert', ['a', 'b', 'c']));
    await library.saveSetlist(Setlist('practice', 'Practice', []));
    await library.saveSetlist(
      Setlist('concert', 'Evening set', ['c', 'a', 'a']),
    );

    final reopened = ScoreLibrary(NativeLibraryStorage(directory: root));
    await reopened.load();
    expect(reopened.setlists.map((setlist) => setlist.name), [
      'Evening set',
      'Practice',
    ]);
    expect(reopened.setlists.first.scores, ['c', 'a', 'a']);
    expect(reopened.setlists.last.scores, isEmpty);
  });
}
