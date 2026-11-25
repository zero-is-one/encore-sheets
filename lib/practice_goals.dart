import 'package:material_ui/material_ui.dart';

import 'practice_activity.dart';

enum PracticeGoalUnit { minutes, views }

typedef PracticeGoal = ({
  PracticeSelection selection,
  PracticeGoalUnit unit,
  int target,
  int days,
});

List<PracticeGoal> readPracticeGoals(Object? value) {
  if (value is! List) return [];
  return [
    for (final item in value)
      if (item
          case {
            'kind': final String kind,
            'id': final String id,
            'title': final String title,
            'unit': final String unit,
            'target': final int target,
            'days': final int days,
          }
          when target > 0 && (days == 7 || days == 30))
        if (PracticeKind.values.where((item) => item.name == kind).firstOrNull
            case final PracticeKind category)
          if (PracticeGoalUnit.values
                  .where((item) => item.name == unit)
                  .firstOrNull
              case final PracticeGoalUnit metric)
            (
              selection: (kind: category, id: id, title: title),
              unit: metric,
              target: target,
              days: days,
            ),
  ];
}

double goalProgress(
  PracticeGoal goal,
  Iterable<PracticeEntry> history,
  DateTime date,
) {
  final start = practiceDay(
    DateTime(date.year, date.month, date.day - goal.days + 1),
  );
  final end = practiceDay(date);
  var count = 0;
  for (final row in history) {
    if (row.selection.id != goal.selection.id ||
        row.selection.kind != goal.selection.kind ||
        row.day.compareTo(start) < 0 ||
        row.day.compareTo(end) > 0)
      continue;
    count += goal.unit == PracticeGoalUnit.minutes ? row.seconds : row.views;
  }
  return goal.unit == PracticeGoalUnit.minutes ? count / 60 : count.toDouble();
}

class PracticeGoalDialog extends StatefulWidget {
  const PracticeGoalDialog({super.key, required this.selections});
  final List<PracticeSelection> selections;

  @override
  State<PracticeGoalDialog> createState() => _PracticeGoalDialogState();
}

class _PracticeGoalDialogState extends State<PracticeGoalDialog> {
  late PracticeSelection _selection = widget.selections.first;
  PracticeGoalUnit _unit = PracticeGoalUnit.minutes;
  final _target = TextEditingController(text: '30');
  int _days = 7;
  bool _invalid = false;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  void _save() {
    final target = int.tryParse(_target.text);
    if (target == null || target < 1 || target > 10000) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(context, (
      selection: _selection,
      unit: _unit,
      target: target,
      days: _days,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add practice goal'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<PracticeSelection>(
          value: _selection,
          isExpanded: true,
          items: [
            for (final item in widget.selections)
              DropdownMenuItem(
                value: item,
                child: Text(
                  '${item.title} · ${item.kind.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) => setState(() => _selection = value!),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _target,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Target',
                  errorText: _invalid ? 'Enter 1 to 10,000' : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<PracticeGoalUnit>(
              value: _unit,
              items: const [
                DropdownMenuItem(
                  value: PracticeGoalUnit.minutes,
                  child: Text('Minutes'),
                ),
                DropdownMenuItem(
                  value: PracticeGoalUnit.views,
                  child: Text('Views'),
                ),
              ],
              onChanged: (value) => setState(() => _unit = value!),
            ),
          ],
        ),
        DropdownButton<int>(
          value: _days,
          items: const [
            DropdownMenuItem(value: 7, child: Text('Over 7 days')),
            DropdownMenuItem(value: 30, child: Text('Over 30 days')),
          ],
          onChanged: (value) => setState(() => _days = value!),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Add goal')),
    ],
  );
}
