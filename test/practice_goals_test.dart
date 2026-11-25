import 'package:encoresheets/practice_activity.dart';
import 'package:encoresheets/practice_goals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a goal includes only matching items within its rolling period', () {
    const score = (kind: PracticeKind.score, id: '1', title: 'Sonata');
    const goal = (
      selection: score,
      unit: PracticeGoalUnit.minutes,
      target: 30,
      days: 7,
    );
    const history = <PracticeEntry>[
      (selection: score, day: '2026-11-18', seconds: 900, views: 1),
      (selection: score, day: '2026-11-19', seconds: 300, views: 2),
      (selection: score, day: '2026-11-25', seconds: 30, views: 1),
      (
        selection: (kind: PracticeKind.setlist, id: '1', title: 'Friday'),
        day: '2026-11-25',
        seconds: 600,
        views: 1,
      ),
    ];
    expect(goalProgress(goal, history, DateTime(2026, 11, 25)), 5.5);
  });
}
