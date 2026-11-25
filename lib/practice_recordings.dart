import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'score_library.dart';

class PracticeRecordings {
  PracticeRecordings(this.library, this.selection);

  final ScoreLibrary library;
  final String selection;
  final recorder = AudioRecorder();
  String? _pending;
  static const _unlinked = 'unlinked';

  Future<Map<String, dynamic>> _catalog() async {
    final preferences = await library.storage.readPreferences();
    return (preferences['practiceRecordings'] as Map?)
            ?.cast<String, dynamic>() ??
        {};
  }

  List<String> _takes(Map<String, dynamic> catalog, [String? key]) =>
      (catalog[key ?? selection] as List? ?? const [])
          .whereType<String>()
          .where((file) => RegExp(r'^practice-[0-9]+\.m4a$').hasMatch(file))
          .toList();

  Future<List<String>> list() async => _takes(await _catalog());
  Future<List<String>> unlinked() async => _takes(await _catalog(), _unlinked);

  Future<String> path(String file) async =>
      '${(await getApplicationDocumentsDirectory()).path}/$file';

  Future<bool> start() async {
    if (!await recorder.hasPermission()) return false;
    final file = 'practice-${DateTime.now().microsecondsSinceEpoch}.m4a';
    await recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: await path(file),
    );
    _pending = file;
    return true;
  }

  Future<void> finish({required bool save}) async {
    final file = _pending;
    if (file == null) return;
    final stopped = await recorder.stop();
    _pending = null;
    if (!save || stopped == null) {
      await _delete(file);
      return;
    }
    final catalog = await _catalog();
    try {
      await library.updatePreferences({
        'practiceRecordings': {
          ...catalog,
          selection: [..._takes(catalog), file],
        },
      });
    } catch (_) {
      await _delete(file);
      rethrow;
    }
  }

  Future<void> remove(
    String file, {
    required bool delete,
    bool unlinked = false,
  }) async {
    final catalog = await _catalog();
    final key = unlinked ? _unlinked : selection;
    final takes = _takes(catalog, key);
    if (!takes.remove(file)) return;
    await library.updatePreferences({
      'practiceRecordings': {
        ...catalog,
        key: takes,
        if (!delete && !unlinked)
          _unlinked: [..._takes(catalog, _unlinked), file],
      },
    });
    if (delete) await _delete(file);
  }

  Future<void> _delete(String file) async {
    final target = File(await path(file));
    if (await target.exists()) await target.delete();
  }

  Future<void> dispose() async {
    try {
      await finish(save: false);
    } finally {
      await recorder.dispose();
    }
  }
}
