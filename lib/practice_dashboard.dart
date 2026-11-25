import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import 'practice_activity.dart';
import 'practice_goals.dart';
import 'practice_report.dart';
import 'score_library.dart';

enum PracticePeriod {
  week('Last 7 days', 7),
  month('Last 30 days', 30),
  all('All time', null);

  const PracticePeriod(this.label, this.days);
  final String label;
  final int? days;

  bool includes(PracticeEntry entry, DateTime now) {
    final duration = days;
    if (duration == null) return true;
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(today.year, today.month, today.day - duration + 1);
    return entry.day.compareTo(practiceDay(start)) >= 0 &&
        entry.day.compareTo(practiceDay(today)) <= 0;
  }
}

String practiceDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  return minutes == 0 ? '${seconds}s' : '${minutes}m';
}

class PracticeDashboard extends StatefulWidget {
  const PracticeDashboard({
    super.key,
    required this.activity,
    required this.library,
  });
  final PracticeActivity activity;
  final ScoreLibrary library;

  @override
  State<PracticeDashboard> createState() => _PracticeDashboardState();
}

class _PracticeDashboardState extends State<PracticeDashboard> {
  var _period = PracticePeriod.week;
  var _category = PracticeKind.score;
  var _reportStyle = PracticeReportStyle.summary;
  List<PracticeEntry> _history = [];
  List<PracticeGoal> _goals = [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.activity.flush();
      final prefs = await widget.library.storage.readPreferences();
      _history = readPracticeActivity(prefs['practiceActivity']);
      _goals = readPracticeGoals(prefs['practiceGoals']);
      if (prefs['practiceReportStyle'] == PracticeReportStyle.log.name) {
        _reportStyle = PracticeReportStyle.log;
      }
    } catch (_) {
      _error = 'Could not read practice history.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.activity.suspend();
      await widget.library.updatePreferences({'practiceTracking': enabled});
      widget.activity.enabled = enabled;
    } catch (_) {
      _error = 'Could not change tracking.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<PracticeSelection> get _goalSelections => [
    for (final score in widget.library.recent) ...[
      (kind: PracticeKind.score, id: score.id, title: score.title),
      for (final bookmark in score.bookmarks.where((item) => item.isItem))
        (
          kind: PracticeKind.bookmark,
          id: bookmark.selectionId(score.id),
          title: '${score.title} · ${bookmark.title}',
        ),
    ],
    for (final list in widget.library.setlists)
      (kind: PracticeKind.setlist, id: list.id, title: list.name),
  ];

  Future<void> _addGoal() async {
    final options = _goalSelections;
    if (options.isEmpty) return;
    final goal = await showDialog<PracticeGoal>(
      context: context,
      builder: (_) => PracticeGoalDialog(selections: options),
    );
    if (goal != null && mounted) await _saveGoals([..._goals, goal]);
  }

  Future<void> _saveGoals(List<PracticeGoal> updated) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.library.updatePreferences({
        'practiceGoals': [
          for (final goal in updated)
            {
              'kind': goal.selection.kind.name,
              'id': goal.selection.id,
              'title': goal.selection.title,
              'unit': goal.unit.name,
              'target': goal.target,
              'days': goal.days,
            },
        ],
      });
      _goals = updated;
    } catch (_) {
      _error = 'Could not save your practice goals.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportReport() async {
    final choice = await showDialog<PracticeReportStyle>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Practice report layout'),
        children: [
          for (final style in [
            _reportStyle,
            ...PracticeReportStyle.values.where((item) => item != _reportStyle),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, style),
              child: Text(style.label),
            ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    final box = context.findRenderObject() as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final now = DateTime.now();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await buildPracticeReport(
        history: _history.where(
          (row) =>
              row.selection.kind == _category && _period.includes(row, now),
        ),
        style: choice,
        period: _period.label,
        category: switch (_category) {
          PracticeKind.score => 'Scores',
          PracticeKind.bookmark => 'Bookmarks',
          PracticeKind.setlist => 'Setlists',
        },
        generated: now,
      );
      await widget.library.updatePreferences({
        'practiceReportStyle': choice.name,
      });
      _reportStyle = choice;
      if (mounted) {
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'Practice report ${practiceDay(now)}.pdf',
          bounds: anchor,
        );
      }
    } catch (_) {
      _error = 'Could not export the practice report.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final results = <String, ({String title, int seconds, int views})>{};
    for (final row in _history) {
      if (row.selection.kind != _category || !_period.includes(row, now))
        continue;
      final previous = results[row.selection.id];
      results[row.selection.id] = (
        title: row.selection.title,
        seconds: (previous?.seconds ?? 0) + row.seconds,
        views: (previous?.views ?? 0) + row.views,
      );
    }
    final rows = results.values.toList()
      ..sort((a, b) => b.seconds.compareTo(a.seconds));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice activity'),
        actions: [
          IconButton(
            tooltip: 'Export practice report',
            onPressed: _busy ? null : _exportReport,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              title: const Text('Track score viewing'),
              subtitle: const Text(
                'Record practice time and views on this device.',
              ),
              value: widget.activity.enabled,
              onChanged: _busy ? null : _setEnabled,
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?) Text(error),
            if (_goals.isNotEmpty || _goalSelections.isNotEmpty) ...[
              Row(
                children: [
                  const Expanded(child: Text('Practice goals')),
                  TextButton.icon(
                    onPressed: _busy || _goalSelections.isEmpty
                        ? null
                        : _addGoal,
                    icon: const Icon(Icons.add),
                    label: const Text('Add goal'),
                  ),
                ],
              ),
              for (final (index, goal) in _goals.indexed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(goal.selection.title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${goalProgress(goal, _history, now).floor()} / '
                        '${goal.target} ${goal.unit.name} in ${goal.days} days',
                      ),
                      LinearProgressIndicator(
                        value: (goalProgress(goal, _history, now) / goal.target)
                            .clamp(0.0, 1.0),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove goal',
                    onPressed: _busy
                        ? null
                        : () => _saveGoals([
                            for (final (other, item) in _goals.indexed)
                              if (other != index) item,
                          ]),
                    icon: const Icon(Icons.close),
                  ),
                ),
              const Divider(),
            ],
            Wrap(
              spacing: 12,
              children: [
                DropdownButton<PracticePeriod>(
                  value: _period,
                  items: [
                    for (final period in PracticePeriod.values)
                      DropdownMenuItem(
                        value: period,
                        child: Text(period.label),
                      ),
                  ],
                  onChanged: (value) => setState(() => _period = value!),
                ),
                DropdownButton<PracticeKind>(
                  value: _category,
                  items: const [
                    DropdownMenuItem(
                      value: PracticeKind.score,
                      child: Text('Scores'),
                    ),
                    DropdownMenuItem(
                      value: PracticeKind.bookmark,
                      child: Text('Bookmarks'),
                    ),
                    DropdownMenuItem(
                      value: PracticeKind.setlist,
                      child: Text('Setlists'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _category = value!),
                ),
              ],
            ),
            if (rows.isEmpty && !_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No practice activity for this view.'),
              ),
            for (final row in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(row.title),
                subtitle: Text(
                  '${row.views} ${row.views == 1 ? 'view' : 'views'}',
                ),
                trailing: Text(practiceDuration(row.seconds)),
              ),
          ],
        ),
      ),
    );
  }
}
