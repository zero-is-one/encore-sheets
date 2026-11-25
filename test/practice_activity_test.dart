import 'dart:io';

import 'package:encoresheets/library_storage_native.dart';
import 'package:encoresheets/practice_activity.dart';
import 'package:encoresheets/score_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'activity is opt-in and persists independent score and setlist counts',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'encore-practice-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final storage = NativeLibraryStorage(directory: directory);
      final activity = PracticeActivity(ScoreLibrary(storage));
      const score = (kind: PracticeKind.score, id: '1', title: 'Rehearsal');
      const set = (kind: PracticeKind.setlist, id: '2', title: 'Friday');
      activity.focus([score], opened: true);
      await activity.suspend();
      expect((await storage.readPreferences())['practiceActivity'], isNull);
      activity.enabled = true;
      activity.focus([score, set], opened: true);
      await activity.flush();
      activity.focus([score], opened: true);
      await activity.suspend();
      final rows = readPracticeActivity(
        (await storage.readPreferences())['practiceActivity'],
      );
      expect(rows.singleWhere((row) => row.selection == score).views, 2);
      expect(rows.singleWhere((row) => row.selection == set).views, 1);
    },
  );
}
