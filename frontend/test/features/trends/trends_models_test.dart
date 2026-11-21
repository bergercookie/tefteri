import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/trends/trends_models.dart';

import '../../support/fake_api.dart';

WeekMetrics _w(String week,
        {bool finished = true,
        int committed = 0,
        int done = 0,
        int goal = 0,
        int maint = 0,
        int off = 0,
        int ms = 0,
        int msDone = 0}) =>
    WeekMetrics.fromJson(weekMetricsJson(week,
        finished: finished,
        committed: committed,
        committedDone: done,
        goalAligned: goal,
        maintenance: maint,
        offPlan: off,
        milestonesCommitted: ms,
        milestonesDone: msDone));

void main() {
  test('a week that is much better is up, in every measure', () {
    final weeks = [
      _w('2030-01-07',
          committed: 10, done: 6, goal: 6, off: 4, ms: 2, msDone: 1),
      _w('2030-01-14',
          committed: 10, done: 6, goal: 6, off: 4, ms: 2, msDone: 1),
      _w('2030-01-21',
          committed: 10, done: 6, goal: 6, off: 4, ms: 2, msDone: 1),
      _w('2030-01-28',
          committed: 10, done: 6, goal: 6, off: 4, ms: 2, msDone: 1),
      _w('2030-02-04',
          committed: 10, done: 9, goal: 12, off: 2, ms: 2, msDone: 2),
    ];
    final c = compareWeek(weeks, DateTime(2030, 2, 4))!;
    expect(c.before, 4);
    final by = {for (final l in c.lines) l.key: l};
    expect(by['completion']!.direction, Direction.up);
    expect(by['completion']!.value, '90%');
    expect(by['completion']!.baseline, '60%');
    expect(by['completion']!.sentence, contains('30 points higher than'));
    expect(by['done']!.direction, Direction.up); // 14 against 10
    expect(by['goal']!.direction, Direction.up); // 86% against 60%
    expect(by['milestones']!.direction, Direction.up); // 2 against 1
    // The sentence always names the direction in words.
    expect(by['done']!.sentence, contains('higher than'));
  });

  test('a week that is lower is down, and one close to the average is steady',
      () {
    final base = [
      for (final d in ['2030-01-07', '2030-01-14', '2030-01-21', '2030-01-28'])
        _w(d, committed: 10, done: 8, goal: 5, maint: 1, off: 4),
    ];
    final down = compareWeek(
        [...base, _w('2030-02-04', committed: 10, done: 3, goal: 1, off: 4)],
        DateTime(2030, 2, 4))!;
    expect(down.lines.firstWhere((l) => l.key == 'completion').direction,
        Direction.down);
    expect(down.lines.firstWhere((l) => l.key == 'done').direction,
        Direction.down);
    final steady = compareWeek([
      ...base,
      _w('2030-02-04', committed: 10, done: 8, goal: 5, maint: 1, off: 4)
    ], DateTime(2030, 2, 4))!;
    for (final l in steady.lines) {
      expect(l.direction, Direction.steady, reason: l.key);
      expect(l.sentence, contains('about the same as'));
    }
    // A move of less than 5 points is steady; 5 or more is not.
    final near = compareWeek([
      ...base,
      _w('2030-02-04', committed: 100, done: 82, goal: 5, maint: 1, off: 4)
    ], DateTime(2030, 2, 4))!;
    expect(near.lines.firstWhere((l) => l.key == 'completion').direction,
        Direction.steady); // 82% against 80%
  });

  test('with fewer than two earlier weeks there is no comparison', () {
    final one = compareWeek([
      _w('2030-01-28', committed: 10, done: 6, goal: 6, off: 4),
      _w('2030-02-04', committed: 10, done: 9, goal: 9, off: 1),
    ], DateTime(2030, 2, 4))!;
    expect(one.notEnough, isTrue);
    expect(one.lines, isEmpty);
    expect(one.before, 1);
  });

  test('weeks with no numbers and the running week are not earlier weeks', () {
    final weeks = [
      _w('2030-01-14', committed: 10, done: 6, goal: 6, off: 4),
      _w('2030-01-21'), // nothing happened
      _w('2030-01-28', committed: 10, done: 6, goal: 6, off: 4),
      _w('2030-02-04', committed: 10, done: 9, goal: 9, off: 1),
      _w('2030-02-11', finished: false, committed: 10, done: 1, goal: 1),
    ];
    final c = compareWeek(weeks, DateTime(2030, 2, 4))!;
    expect(c.before, 2); // the empty week is left out
    // The running week is not compared, and a week without numbers is not either.
    expect(compareWeek(weeks, DateTime(2030, 1, 21)), isNull);
    expect(compareWeek(weeks, DateTime(2031, 1, 1)), isNull);
    expect(latestFinishedWeek(weeks), DateTime(2030, 2, 4));
  });

  test('a measure with too few earlier values is left out', () {
    // Only the last earlier week had committed tasks: no completion line.
    final weeks = [
      _w('2030-01-14', goal: 4, off: 4),
      _w('2030-01-21', goal: 4, off: 4),
      _w('2030-01-28', committed: 10, done: 6, goal: 6, off: 4),
      _w('2030-02-04', committed: 10, done: 9, goal: 9, off: 1),
    ];
    final c = compareWeek(weeks, DateTime(2030, 2, 4))!;
    expect(c.lines.map((l) => l.key), isNot(contains('completion')));
    expect(c.lines.map((l) => l.key), contains('done'));
  });

  test('only the four weeks before count', () {
    final weeks = [
      for (var i = 0; i < 6; i++)
        _w('2030-01-${(7 + 7 * i).toString().padLeft(2, '0')}',
            committed: 10, done: 6, goal: 6, off: 4),
      _w('2030-02-18', committed: 10, done: 6, goal: 6, off: 4),
    ];
    expect(compareWeek(weeks, DateTime(2030, 2, 18))!.before, 4);
  });
}
