import 'dart:io';

import 'package:encoresheets/library_score_preview.dart';
import 'package:encoresheets/library_storage_native.dart';
import 'package:encoresheets/score_library.dart';
import 'package:encoresheets/score_metadata_screen.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Properties returns the selected preview page when saved', (
    tester,
  ) async {
    final score = ScoreEntry(
      id: 'test',
      title: 'Rehearsal',
      page: 1,
      openedAt: DateTime.utc(2026),
    );
    ScoreMetadataEdit? edit;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              edit = await editScoreMetadata(
                context,
                score,
                preview: (page) async => (image: null, page: page, total: 3),
                setlists: const [],
                libraries: const [],
              );
            },
            child: const Text('Open Properties'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Properties'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Next preview page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);
    await tester.tap(find.text('Save and open page'));
    await tester.pumpAndSettle();
    expect(edit?.openPage, 2);
  });

  test(
    'renders the requested score page and bounds preview navigation',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'encoresheets_preview',
      );
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(paths, (_) async => folder.path);
      addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
      addTearDown(() => folder.delete(recursive: true));
      final library = ScoreLibrary(NativeLibraryStorage(directory: folder));
      final (score, _) = await library.import(XFile('assets/first_light.pdf'));

      final first = (await renderLibraryScorePreview(library, score))!;
      final second = (await renderLibraryScorePreview(
        library,
        score,
        pageNumber: 2,
      ))!;
      final last = (await renderLibraryScorePreview(
        library,
        score,
        pageNumber: 999,
      ))!;

      expect(first.page, 1);
      expect(second.page, 2);
      expect(last.page, last.total);
      expect(first.image, isNotEmpty);
      expect(second.image, isNot(equals(first.image)));
    },
  );
}
