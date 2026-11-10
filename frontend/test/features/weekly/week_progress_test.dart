import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/weekly/week_progress.dart';
import 'package:tefteri/features/weekly/week_progress_card.dart';
import 'package:tefteri/features/weekly/weekly_models.dart';

import '../../support/fake_api.dart';

final _monday = DateTime(2026, 11, 2);

Map<String, Object?> _task(String id, {String? doneOn, bool done = false}) => {
      'id': id,
      'title': 'Task $id',
      'done': done || doneOn != null,
      'completed_day': doneOn,
    };

WeeklyPlan _plan(List<Map<String, Object?>> tasks,
        {String status = 'committed'}) =>
    WeeklyPlan.fromJson({
      'id': 'p',
      'status': status,
      'max_projects': 3,
      'projects': [
        {
          'id': 'a',
          'name': 'Website',
          'created_here': false,
          'open_tasks': 0,
          'done_tasks': 0,
          'scheduled_tasks': 0,
          'tasks': const <Object?>[],
          'committed_tasks': tasks,
        },
      ],
    });

void main() {
  // 10 tasks: 2 done on Monday, 1 on Tuesday, 1 on Wednesday, 6 open.
  final tasks = [
    _task('1', doneOn: '2026-11-02'),
    _task('2', doneOn: '2026-11-02'),
    _task('3', doneOn: '2026-11-03'),
    _task('4', doneOn: '2026-11-04'),
    for (var i = 5; i <= 10; i++) _task('$i'),
  ];

  group('WeekProgress', () {
    test('counts done per day, what is left and the cadence', () {
      final p =
          WeekProgress.of(_plan(tasks), _monday, DateTime(2026, 11, 4, 15));
      expect(p.committed, 10);
      expect(p.doneByDay, [2, 1, 1, 0, 0, 0, 0]);
      expect(p.doneInWeek, 4);
      expect(p.done, 4);
      expect(p.left, 6);
      expect(p.daysElapsed, 3);
      expect(p.cadence, closeTo(4 / 3, 1e-9));
      expect(p.daysLeft, 5); // Wednesday to Sunday, today included
      expect(p.neededPerDay, closeTo(6 / 5, 1e-9));
      expect(p.onTrack, isTrue);
    });

    test('burns down from the scope and stops at today', () {
      final p = WeekProgress.of(_plan(tasks), _monday, DateTime(2026, 11, 4));
      expect(p.remainingByDay, [8, 7, 6, null, null, null, null]);
      expect(p.idealByDay.first, closeTo(10 * 6 / 7, 1e-9));
      expect(p.idealByDay.last, 0);
    });

    test('is behind when the cadence is below what is needed', () {
      final p = WeekProgress.of(_plan(tasks), _monday, DateTime(2026, 11, 8));
      expect(p.daysLeft, 1); // only Sunday
      expect(p.neededPerDay, 6);
      expect(p.cadence, closeTo(4 / 7, 1e-9));
      expect(p.onTrack, isFalse);
    });

    test('tasks done before the week or without a day are not burned', () {
      final p = WeekProgress.of(
        _plan([
          _task('1', doneOn: '2026-10-30'),
          _task('2', done: true),
          _task('3', doneOn: '2026-11-03'),
          _task('4'),
        ]),
        _monday,
        DateTime(2026, 11, 3),
      );
      expect(p.done, 3);
      expect(p.doneInWeek, 1);
      expect(p.scope, 2);
      expect(p.remainingByDay.take(2), [2, 1]);
    });

    test(
        'a week that has not begun has no cadence; a past week has no days left',
        () {
      final future =
          WeekProgress.of(_plan(tasks), _monday, DateTime(2026, 10, 28));
      expect(future.cadence, isNull);
      expect(future.daysLeft, 7);
      expect(future.remainingByDay, everyElement(isNull));
      final past =
          WeekProgress.of(_plan(tasks), _monday, DateTime(2026, 11, 20));
      expect(past.daysLeft, 0);
      expect(past.neededPerDay, isNull);
      expect(past.remainingByDay.whereType<int>(), hasLength(7));
    });
  });

  group('WeekProgressCard', () {
    Map<String, Object?> state(String status) => {
          'week_start': '2026-11-02',
          'week_end': '2026-11-09',
          'plan': {
            'id': 'p',
            'status': status,
            'max_projects': 3,
            'projects': [
              {
                'id': 'a',
                'name': 'Website',
                'created_here': false,
                'open_tasks': 6,
                'done_tasks': 4,
                'scheduled_tasks': 0,
                'tasks': <Object?>[],
                'committed_tasks': tasks,
              },
            ],
          },
          'look_back': null,
        };

    testWidgets('shows done, left, cadence, days and the burndown',
        (tester) async {
      await pumpWithApi(
        tester,
        FakeApi({'GET /weekly/2026-11-02': state('committed')}),
        Scaffold(
          body: SingleChildScrollView(
            child:
                WeekProgressCard(week: _monday, today: DateTime(2026, 11, 4)),
          ),
        ),
      );
      expect(find.text('4 of 10 tasks done'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('stat-left')), matching: find.text('6')),
          findsOneWidget);
      expect(find.text('1.3 a day'), findsOneWidget);
      expect(find.text('1.2 a day'), findsOneWidget);
      expect(find.text('On track.'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('done-day-0')),
              matching: find.text('2')),
          findsOneWidget);
      expect(find.text('Total 4'), findsOneWidget);
      expect(find.byKey(const Key('burndown')), findsOneWidget);
    });

    testWidgets('shows nothing for a draft plan', (tester) async {
      await pumpWithApi(
        tester,
        FakeApi({'GET /weekly/2026-11-02': state('draft')}),
        Scaffold(body: WeekProgressCard(week: _monday)),
      );
      expect(find.byKey(const Key('week-progress')), findsNothing);
    });
  });
}
