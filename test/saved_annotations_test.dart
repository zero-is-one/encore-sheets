import 'dart:io';

import 'package:encoresheets/library_storage_native.dart';
import 'package:encoresheets/page_ink.dart';
import 'package:encoresheets/score_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'restores annotation tools and keeps pages and scores separate',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'encore_ink_test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final library = ScoreLibrary(NativeLibraryStorage(directory: directory));
      final pen = PageInk();
      final highlight = PageInk();
      addTearDown(pen.dispose);
      addTearDown(highlight.dispose);

      pen.begin(const Offset(.2, .3));
      pen.extend(const Offset(.7, .3));
      pen.finish(commit: true);
      highlight.begin(const Offset(.2, .6), tool: InkTool.highlighter);
      highlight.finish(commit: true);
      await library.writeInk('first', {
        '2': pen.snapshot(),
        '8': highlight.snapshot(),
      });
      await library.writeInk('second', {'2': highlight.snapshot()});

      final reopened = ScoreLibrary(NativeLibraryStorage(directory: directory));
      final first = await reopened.readInk('first');
      expect(first['8'], highlight.snapshot());
      expect((await reopened.readInk('second'))['2'], highlight.snapshot());
      expect(await reopened.readInk('older-score'), isEmpty);

      var changes = 0;
      final restored = PageInk(
        saved: first['2'] as List,
        onChanged: () => changes++,
      );
      addTearDown(restored.dispose);
      expect(restored.snapshot(), pen.snapshot());
      restored.begin(const Offset(.4, .1), tool: InkTool.eraser);
      restored.extend(const Offset(.4, .5));
      restored.finish(commit: false);
      expect(restored.snapshot(), pen.snapshot());
      expect(changes, 0);
      restored.begin(const Offset(.4, .1), tool: InkTool.eraser);
      restored.extend(const Offset(.4, .5));
      restored.finish(commit: true);
      expect(restored.snapshot(), isEmpty);
      expect(changes, 1);
      await reopened.writeInk('first', {'8': first['8']});
      final afterErase = ScoreLibrary(
        NativeLibraryStorage(directory: directory),
      );
      expect((await afterErase.readInk('first')).containsKey('2'), isFalse);
      restored.undo();
      expect(restored.snapshot(), pen.snapshot());
      expect(changes, 2);
      restored.redo();
      expect(restored.snapshot(), isEmpty);
      expect(changes, 3);
    },
  );
}
