import 'dart:io';

import 'package:encoresheets/library_storage_native.dart';
import 'package:encoresheets/page_ink.dart';
import 'package:encoresheets/score_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clears only the active layer and can undo the edit', () {
    final ink = PageInk();
    addTearDown(ink.dispose);
    ink.begin(const Offset(.1, .2));
    ink.finish(commit: true);
    ink.configureLayers(
      active: 'practice',
      visible: ['base', 'practice'],
      changes: [],
    );
    ink.begin(const Offset(.4, .5));
    ink.finish(commit: true);
    final original = ink.snapshot();
    ink.clearActiveLayer();
    expect(ink.snapshot(), hasLength(1));
    expect(ink.snapshot().single['layer'], isNull);
    expect(ink.hasActiveLayerInk, isFalse);
    ink.undo();
    expect(ink.snapshot(), original);
  });

  test('persists the sampled stylus brush widths with a stroke', () {
    final ink = PageInk();
    addTearDown(ink.dispose);
    ink.begin(const Offset(.1, .2), width: .005, sampleWidth: .002);
    ink.extend(const Offset(.2, .25), sampleWidth: .009);
    ink.finish(commit: true);
    final reopened = PageInk(saved: ink.snapshot());
    addTearDown(reopened.dispose);
    expect(reopened.snapshot().single['sampleWidths'], [.002, .009]);
  });

  test('selects a crossed stroke, moves it, and pastes it to another page', () {
    final source = PageInk();
    final target = PageInk();
    addTearDown(source.dispose);
    addTearDown(target.dispose);
    source.begin(const Offset(.1, .3));
    source.extend(const Offset(.8, .3));
    source.finish(commit: true);

    source.beginSelection(const Offset(.4, .2), freeform: false);
    source.extendSelection(const Offset(.5, .4));
    source.finishSelection(commit: true);
    expect(source.hasSelection, isTrue);
    source.beginSelection(const Offset(.4, .3), freeform: false);
    source.extendSelection(const Offset(.4, .5));
    source.finishSelection(commit: true);
    expect(source.snapshot().single['points'], [
      [.1, .5],
      [.8, .5],
    ]);

    target.pasteSelection(source.copySelection());
    expect(target.hasSelection, isTrue);
    source.deleteSelection();
    expect(source.snapshot(), isEmpty);
    expect(target.snapshot(), hasLength(1));
    source.undo();
    expect(source.snapshot(), hasLength(1));
  });

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
