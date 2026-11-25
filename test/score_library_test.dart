import 'dart:io';

import 'package:encoresheets/library_storage_native.dart';
import 'package:encoresheets/score_library.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    final (a, _) = await library.import(XFile(first.path));
    final (b, _) = await library.import(XFile(second.path));
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
