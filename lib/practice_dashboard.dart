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

typedef _ReportPreset = ({
  String name,
  PracticePeriod period,
  PracticeKind category,
  PracticeReportStyle style,
});

_ReportPreset? _readReportPreset(Object? row) {
  if (row is! Map || row['name'] is! String) return null;
  final name = (row['name'] as String).trim();
  final period = PracticePeriod.values
      .where((value) => value.name == row['period'])
      .firstOrNull;
  final category = PracticeKind.values
      .where((value) => value.name == row['category'])
      .firstOrNull;
  final style = PracticeReportStyle.values
      .where((value) => value.name == row['style'])
      .firstOrNull;
  if (name.isEmpty || period == null || category == null || style == null)
    return null;
  return (name: name, period: period, category: category, style: style);
}

class PracticeDashboard extends StatefulWidget {
  const PracticeDashboard({
    super.key,
    required this.activity,
    required this.library,
    this.allowExport = true,
  });
  final PracticeActivity activity;
  final ScoreLibrary library;
  final bool allowExport;

  @override
  State<PracticeDashboard> createState() => _PracticeDashboardState();
}

class _PracticeDashboardState extends State<PracticeDashboard> {
  var _period = PracticePeriod.week;
  var _category = PracticeKind.score;
  var _reportStyle = PracticeReportStyle.summary;
  List<PracticeEntry> _history = [];
  List<PracticeGoal> _goals = [];
  List<_ReportPreset> _presets = [];
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
      if (prefs['practiceReportPresets'] case final List rows) {
        _presets = rows.map(_readReportPreset).nonNulls.toList();
      }
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

  Future<PracticeReportStyle?> _chooseReportStyle() =>
      showDialog<PracticeReportStyle>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: const Text('Practice report layout'),
          children: [
            for (final style in [
              _reportStyle,
              ...PracticeReportStyle.values.where(
                (item) => item != _reportStyle,
              ),
            ])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, style),
                child: Text(style.label),
              ),
          ],
        ),
      );

  Future<void> _exportReport({_ReportPreset? preset}) async {
    final choice = preset?.style ?? await _chooseReportStyle();
    if (!mounted || choice == null) return;
    final period = preset?.period ?? _period;
    final category = preset?.category ?? _category;
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
          (row) => row.selection.kind == category && period.includes(row, now),
        ),
        style: choice,
        period: period.label,
        category: switch (category) {
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

  Future<void> _saveReportPresets(List<_ReportPreset> updated) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.library.updatePreferences({
        'practiceReportPresets': [
          for (final preset in updated)
            {
              'name': preset.name,
              'period': preset.period.name,
              'category': preset.category.name,
              'style': preset.style.name,
            },
        ],
      });
      _presets = updated;
    } catch (_) {
      _error = 'Could not save report settings.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newReportPreset() async {
    final style = await _chooseReportStyle();
    if (!mounted || style == null) return;
    var name = '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Name this report'),
        content: TextField(
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Report name'),
          onChanged: (value) => name = value.trim(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true || name.isEmpty) return;
    await _saveReportPresets([
      ..._presets,
      (name: name, period: _period, category: _category, style: style),
    ]);
  }

  Future<void> _showReportPresets() async {
    final action = await showDialog<({int index, bool remove})>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Saved practice reports'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialog, (index: -1, remove: false)),
            child: const Text('Save current report settings'),
          ),
          for (final (index, preset) in _presets.indexed)
            ListTile(
              title: Text(preset.name),
              subtitle: Text(
                '${preset.period.label} · ${preset.category.name} · ${preset.style.label}',
              ),
              onTap: () => Navigator.pop(dialog, (index: index, remove: false)),
              trailing: IconButton(
                tooltip: 'Remove ${preset.name}',
                onPressed: () =>
                    Navigator.pop(dialog, (index: index, remove: true)),
                icon: const Icon(Icons.close),
              ),
            ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action.index < 0) {
      await _newReportPreset();
    } else if (action.remove) {
      await _saveReportPresets([..._presets]..removeAt(action.index));
    } else {
      await _exportReport(preset: _presets[action.index]);
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
          if (widget.allowExport)
            IconButton(
              tooltip: 'Saved practice reports',
              onPressed: _busy ? null : _showReportPresets,
              icon: const Icon(Icons.bookmark_outline),
            ),
          if (widget.allowExport)
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
