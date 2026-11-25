import 'dart:io';

import 'package:encoresheets/library_storage_native.dart';
import 'package:encoresheets/program_duration.dart';
import 'package:encoresheets/score_library.dart';
import 'package:encoresheets/setlist_order.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'counts repeated pieces and reports excerpts without independent timings',
    () async {
      final root = await Directory.systemTemp.createTemp('encore_duration');
      addTearDown(() => root.delete(recursive: true));
      final library = ScoreLibrary(NativeLibraryStorage(directory: root));
      final (score, _) = await library.import(XFile('assets/first_light.pdf'));
      const excerpt = ScoreBookmark('excerpt', 'Excerpt', 1, endPage: 2);
      await library.updateScore(
        score.id,
        (old) =>
            old.copyWith(metadata: {'duration': '3:45'}, bookmarks: [excerpt]),
      );
      final program = Setlist(
        'concert',
        'Winter recital',
        [score.id, excerpt.selectionId(score.id), score.id],
        label: 'Choir',
        notes: 'Ten-minute interval after the second piece.',
      );
      await library.saveSetlist(program);
      final estimate = library.estimateSetlistDuration(program.scores);
      expect(estimate.missing, 1);
      expect(formatProgramDuration(estimate.total), '7:30');
      expect(parseScoreDuration('1:07:30')!.inSeconds, 4050);
      expect(parseScoreDuration('4:61'), isNull);
      expect(Setlist.fromJson(program.toJson()).notes, program.notes);
    },
  );

  test(
    'persists manual program order and sorts unplayed pieces first',
    () async {
      final root = await Directory.systemTemp.createTemp('encore_setlists');
      addTearDown(() => root.delete(recursive: true));
      final library = ScoreLibrary(NativeLibraryStorage(directory: root));
      await library.saveSetlist(Setlist('a', 'Evening', ['a1', 'a2', 'a1']));
      await library.saveSetlist(Setlist('b', 'Morning', []));
      await library.moveSetlist('b', 'a');
      await library.recordSetlistPlay('a', 'a1');

      final reopened = ScoreLibrary(NativeLibraryStorage(directory: root));
      await reopened.load();
      expect(reopened.setlists.map((list) => list.id), ['b', 'a']);
      final scores = reopened.setlists.last.scores;
      expect(
        orderSetlistItems(
          scores,
          SetlistOrder.leastRecent,
          title: (id) => id,
          lastPlayed: (id) => reopened.lastSetlistPlay('a', id),
        ),
        ['a2', 'a1', 'a1'],
      );
      expect(
        orderSetlistItems(
          scores,
          SetlistOrder.shuffle,
          title: (id) => id,
          lastPlayed: (_) => null,
        ),
        unorderedEquals(scores),
      );
    },
  );

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
