import 'package:encoresheets/library_storage_memory.dart' as memory;
import 'package:encoresheets/score_library.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('assistant setlists preserve order and are safe to replay', () async {
    final storage = memory.createStorage();
    final library = ScoreLibrary(storage);
    final (bach, _) = await library.import(XFile('assets/first_light.pdf'));
    final debussy = await library.duplicateScore(bach.id);
    final request = Setlist('assistant-request', 'Friday', [
      debussy.id,
      bach.id,
      debussy.id,
    ]);

    expect(await library.applyAssistantSetlist(request), isTrue);
    final reopened = ScoreLibrary(storage);
    await reopened.load();
    expect(await reopened.applyAssistantSetlist(request), isTrue);
    expect(reopened.setlists.single.scores, request.scores);

    await reopened.trashScores([bach.id]);
    final stale = request.copyWith(id: 'assistant-stale');
    expect(await reopened.applyAssistantSetlist(stale), isFalse);
    expect(reopened.setlists.map((setlist) => setlist.id), [request.id]);
  });
}
