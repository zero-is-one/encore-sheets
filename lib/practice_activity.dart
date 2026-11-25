import 'dart:async';

import 'score_library.dart';

enum PracticeKind { score, bookmark, setlist }

typedef PracticeSelection = ({PracticeKind kind, String id, String title});
typedef PracticeEntry = ({
  PracticeSelection selection,
  String day,
  int seconds,
  int views,
});

String practiceDay(DateTime time) =>
    '${time.year.toString().padLeft(4, '0')}-'
    '${time.month.toString().padLeft(2, '0')}-'
    '${time.day.toString().padLeft(2, '0')}';

List<PracticeEntry> readPracticeActivity(Object? saved) {
  if (saved is! List) return [];
  return [
    for (final row in saved)
      if (row
          case {
            'kind': final String kind,
            'id': final String id,
            'title': final String title,
            'day': final String day,
            'seconds': final int seconds,
            'views': final int views,
          }
          when seconds >= 0 &&
              views >= 0 &&
              RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day))
        if (PracticeKind.values.where((item) => item.name == kind).firstOrNull
            case final PracticeKind category)
          (
            selection: (kind: category, id: id, title: title),
            day: day,
            seconds: seconds,
            views: views,
          ),
  ];
}

class PracticeActivity {
  PracticeActivity(this.library);

  final ScoreLibrary library;
  bool enabled = false;
  List<PracticeSelection> _selection = [];
  final _clock = Stopwatch();
  Timer? _timer;
  Future<void> _writes = Future.value();
  final _pending = <(String, PracticeKind, String), PracticeEntry>{};

  void focus(List<PracticeSelection> selection, {bool opened = false}) {
    _collect();
    _selection = selection;
    if (!enabled || selection.isEmpty) return;
    if (opened) _increment(views: 1);
    _clock.start();
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(flush().catchError((Object _) {}));
    });
  }

  Future<void> suspend() {
    _collect();
    _timer?.cancel();
    _timer = null;
    return _write();
  }

  void _collect() {
    if (!_clock.isRunning) return;
    _clock.stop();
    final seconds = _clock.elapsed.inSeconds;
    _clock.reset();
    if (seconds > 0) _increment(seconds: seconds);
  }

  void _increment({int seconds = 0, int views = 0}) {
    final day = practiceDay(DateTime.now());
    for (final selection in _selection) {
      final key = (day, selection.kind, selection.id);
      final previous = _pending[key];
      _pending[key] = (
        selection: selection,
        day: day,
        seconds: (previous?.seconds ?? 0) + seconds,
        views: (previous?.views ?? 0) + views,
      );
    }
  }

  Future<void> flush() {
    final running = _clock.isRunning;
    _collect();
    if (running && enabled) _clock.start();
    return _write();
  }

  Future<void> _write() {
    final operation = _writes.then((_) async {
      if (_pending.isEmpty) return;
      final batch = Map.of(_pending);
      _pending.clear();
      try {
        final prefs = await library.storage.readPreferences();
        final merged = {
          for (final entry in readPracticeActivity(prefs['practiceActivity']))
            (entry.day, entry.selection.kind, entry.selection.id): entry,
        };
        for (final item in batch.entries) {
          final existing = merged[item.key];
          final row = item.value;
          merged[item.key] = (
            selection: row.selection,
            day: row.day,
            seconds: row.seconds + (existing?.seconds ?? 0),
            views: row.views + (existing?.views ?? 0),
          );
        }
        await library.updatePreferences({
          'practiceActivity': [
            for (final row in merged.values)
              {
                'kind': row.selection.kind.name,
                'id': row.selection.id,
                'title': row.selection.title,
                'day': row.day,
                'seconds': row.seconds,
                'views': row.views,
              },
          ],
        });
      } catch (_) {
        for (final item in batch.entries) {
          final existing = _pending[item.key];
          final row = item.value;
          _pending[item.key] = (
            selection: existing?.selection ?? row.selection,
            day: row.day,
            seconds: row.seconds + (existing?.seconds ?? 0),
            views: row.views + (existing?.views ?? 0),
          );
        }
        rethrow;
      }
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }
}
