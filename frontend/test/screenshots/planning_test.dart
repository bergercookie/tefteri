@Tags(['screenshots'])
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/goals/goals_screen.dart';
import 'package:tefteri/features/month/month_screen.dart';
import 'package:tefteri/features/week/week_screen.dart';
import 'package:tefteri/features/year/year_screen.dart';

import 'fixtures.dart';
import 'screenshot_helper.dart';

final _yearGoal = goalJson('g1', 'Run a half marathon', progress: 0.4);
final _monthGoal = goalJson('g2', 'Run 100 km in November',
    periodType: 'month',
    periodStart: '2026-11-01',
    parentId: 'g1',
    progress: 0.5);
final _weekGoal = goalJson('g3', 'Run 25 km',
    periodType: 'week',
    periodStart: '2026-11-02',
    parentId: 'g2',
    progress: 0.5);

final _tasks = [
  {
    ...taskJson('t6', 'Buy running shoes', status: 'done'),
    'goal_id': 'g3',
  },
  {
    ...taskJson('t7', 'Run 10 km on Saturday'),
    'goal_id': 'g3',
    'scheduled_start': '2026-11-07T08:00:00Z',
  },
  taskJson('t1', 'Write the release notes'),
];

Map<String, Object?> _committedTask(int n, {String? doneOn}) => {
      'id': 'c$n',
      'title': 'Task $n',
      'done': doneOn != null,
      'completed_day': doneOn,
    };

/// Eight tasks committed for the week: two done Monday, one Tuesday, two Wednesday.
final _weeklyState = {
  'week_start': '2026-11-02',
  'week_end': '2026-11-09',
  'look_back': null,
  // Done during the week, and not in the committed plan.
  'done_outside_plan': [
    {
      'id': 'x1',
      'title': 'Call the plumber',
      'completed_day': '2026-11-03',
      'project': 'Home',
      'project_color': null,
      'url': null,
    },
    {
      'id': 'x2',
      'title': 'Pay the electricity bill',
      'completed_day': '2026-11-04',
      'project': 'Taxes',
      'project_color': null,
      'url': null,
    },
    {
      'id': 'x3',
      'title': 'Reply to the landlord',
      'completed_day': '2026-11-04',
      'project': null,
      'project_color': null,
      'url': null,
    },
  ],
  'plan': {
    'id': 'plan1',
    'status': 'committed',
    'committed_at': '2026-11-01T18:00:00Z',
    'retro_skipped': false,
    'max_projects': 3,
    'projects': [
      {
        'id': 'pp1',
        'name': 'Website',
        'created_here': false,
        'open_tasks': 3,
        'done_tasks': 5,
        'scheduled_tasks': 3,
        'tasks': <Object?>[],
        'committed_tasks': [
          _committedTask(1, doneOn: '2026-11-02'),
          _committedTask(2, doneOn: '2026-11-02'),
          _committedTask(3, doneOn: '2026-11-03'),
          _committedTask(4, doneOn: '2026-11-04'),
          _committedTask(5, doneOn: '2026-11-04'),
          _committedTask(6),
          _committedTask(7),
          _committedTask(8),
        ],
      },
    ],
  },
};

FakeApi _api() => FakeApi({
      'GET /checklists/year/2026-01-01': {
        'period_type': 'year',
        'period_start': '2026-01-01',
        'items': <Object?>[],
        'done': 0,
        'total': 0,
      },
      'GET /checklists/month/2026-11-01': {
        'period_type': 'month',
        'period_start': '2026-11-01',
        'items': [
          {'text': 'Look back at the month', 'checked': true},
          {'text': 'Review the goals of the month', 'checked': false},
          {'text': 'Check the budget', 'checked': false},
          {'text': 'Set the goals for next month', 'checked': false},
        ],
        'done': 1,
        'total': 4,
      },
      'GET /weekly/2026-11-02': _weeklyState,
      'GET /views/week/2026-11-02':
          periodJson('week', '2026-11-02', '2026-11-09',
              goals: [_weekGoal],
              tasks: _tasks,
              entries: [
                entryJson('e1', 'Team standup', DateTime(2026, 11, 2, 9)),
              ]),
      'GET /views/month/2026-11-01': periodJson(
          'month', '2026-11-01', '2026-12-01',
          goals: [_monthGoal], tasks: _tasks),
      'GET /views/year/2026':
          periodJson('year', '2026-01-01', '2027-01-01', goals: [
        _yearGoal,
        goalJson('g4', 'Read 12 books', progress: 0.75),
      ]),
      'GET /goals': (RequestOptions o) =>
          switch (o.queryParameters['parent_id']) {
            'g1' => [_monthGoal],
            'g2' => [_weekGoal],
            null => [
                _yearGoal,
                goalJson('g4', 'Read 12 books', progress: 0.75)
              ],
            _ => <Object?>[],
          },
      'GET /connections': connections,
    });

void main() {
  testWidgets('weekly view', (tester) async {
    await pumpScreen(tester, _api(),
        WeekScreen(initialDate: day, today: DateTime(2026, 11, 4)));
    await saveScreenshot('planning-week');
  });

  testWidgets('monthly view', (tester) async {
    await pumpScreen(tester, _api(), MonthScreen(initialDate: day));
    await saveScreenshot('planning-month');
  });

  testWidgets('annual view', (tester) async {
    await pumpScreen(tester, _api(), const YearScreen(initialYear: 2026));
    await saveScreenshot('planning-year');
  });

  testWidgets('goal breakdown', (tester) async {
    await pumpScreen(tester, _api(), GoalsScreen(initialDate: day));
    await saveScreenshot('planning-goals');
    await tester.tap(find.byKey(const Key('goal-menu-g1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Break down'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add goal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add task'));
    await tester.pumpAndSettle();
    await saveScreenshot('planning-breakdown');
  });
}
