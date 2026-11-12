@Tags(['screenshots'])
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/month/month_screen.dart';
import 'package:tefteri/features/week/week_screen.dart';
import 'package:tefteri/features/year/year_screen.dart';

import 'fixtures.dart';
import 'screenshot_helper.dart';

/// The annual plan of 2026, read only on the year view.
final _annualPlan = annualPlanJson(year: 2026, goals: [
  annualGoalJson('g1', 'Run a half marathon', keyResults: [
    keyResultJson('kr1', 'Longest run in km',
        goalId: 'g1',
        start: 5,
        target: 21,
        current: 14,
        deadline: '2026-10-31'),
  ]),
  annualGoalJson('g4', 'Read more', keyResults: [
    keyResultJson('kr2', 'Books read',
        goalId: 'g4', start: 0, target: 12, current: 9),
  ]),
]);

final _tasks = [
  {
    ...taskJson('t6', 'Buy running shoes', status: 'done'),
    'goal_id': 'g1',
  },
  {
    ...taskJson('t7', 'Run 10 km on Saturday'),
    'goal_id': 'g1',
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

/// The week of the fixture, as the server counts it: every completed task is
/// in one of the three categories.
final _weekDone = [
  statTaskJson('d1', 'Update the pricing page',
      category: 'goal_aligned',
      completedDay: '2026-11-02',
      project: 'Website',
      reason: 'committed_milestone'),
  statTaskJson('d2', 'Fix the contact form',
      category: 'goal_aligned',
      completedDay: '2026-11-03',
      project: 'Website',
      reason: 'committed_milestone'),
  statTaskJson('d3', 'Take out the bins',
      category: 'maintenance',
      completedDay: '2026-11-03',
      project: 'Chores',
      reason: 'maintenance_label'),
  statTaskJson('d4', 'Call the plumber',
      category: 'off_plan',
      completedDay: '2026-11-03',
      project: 'Home',
      reason: 'theme'),
  statTaskJson('d5', 'Reply to the landlord',
      category: 'off_plan',
      completedDay: '2026-11-04',
      project: null,
      unsorted: true,
      reason: 'no_project'),
];

/// `GET /statistics` for the week, the month and the year of the fixture.
Object? _statistics(RequestOptions o) {
  final progress = weekProgressJson(
    committed: 8,
    done: 5,
    doneByDay: const [2, 1, 2, 0, 0, 0, 0],
    daysElapsed: 3,
    daysLeft: 5,
    cadence: 5 / 3,
    neededPerDay: 0.6,
    remainingByDay: const [6, 5, 3, null, null, null, null],
    scope: 8,
    idealByDay: const [6.86, 5.71, 4.57, 3.43, 2.29, 1.14, 0.0],
  );
  List<Object?> days(List<List<int>> c) => [
        for (var i = 0; i < 7; i++)
          {
            'start': '2026-11-0${2 + i}',
            'end': '2026-11-0${3 + i}',
            'counts': categoryCountsJson(c[i][0], c[i][1], c[i][2]),
            'hidden': 0,
          },
      ];
  return switch (o.queryParameters['period']) {
    'month' => statisticsJson(
        period: 'month',
        start: '2026-11-01',
        end: '2026-12-01',
        goalAligned: 14,
        maintenance: 9,
        offPlan: 5,
        hidden: 2,
        unsorted: 1),
    'year' => statisticsJson(
        period: 'year',
        start: '2026-01-01',
        end: '2027-01-01',
        goalAligned: 120,
        maintenance: 70,
        offPlan: 40,
        hidden: 6),
    _ => statisticsJson(
        goalAligned: 2,
        maintenance: 1,
        offPlan: 2,
        unsorted: 1,
        progress: progress,
        parts: days([
          [1, 0, 0],
          [1, 1, 1],
          [0, 0, 1],
          [0, 0, 0],
          [0, 0, 0],
          [0, 0, 0],
          [0, 0, 0],
        ])),
  };
}

FakeApi _api() => FakeApi({
      'GET /statistics': _statistics,
      'GET /statistics/tasks': fakeStatisticsTasks(_weekDone),
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
          {'text': 'Update the key results', 'checked': false},
          {'text': 'Check the budget', 'checked': false},
          {'text': 'Choose the themes for next month', 'checked': false},
        ],
        'done': 1,
        'total': 4,
      },
      'GET /weekly/2026-11-02': _weeklyState,
      'GET /views/week/2026-11-02':
          periodJson('week', '2026-11-02', '2026-11-09',
              goalTitles: {
                'g1': {'title': 'Run a half marathon', 'annual': true},
              },
              tasks: _tasks,
              entries: [
                entryJson('e1', 'Team standup', DateTime(2026, 11, 2, 9)),
              ]),
      'GET /views/year/2026': periodJson('year', '2026-01-01', '2027-01-01'),
      'GET /annual/2026': _annualPlan,
      'GET /monthly/2026-11': monthlyJson(
        month: '2026-11',
        entries: [
          monthlyEntryJson('e1', 'p1', 'Health',
              target: 3, done: 1, countsFrom: '2026-11-01', lastMonthDone: 2),
          monthlyEntryJson('e2', 'p2', 'Website',
              target: 2, done: 1, countsFrom: '2026-11-01', lastMonthDone: 1),
        ],
        keyResults: [
          monthlyKeyResultJson(
              id: 'kr1',
              goalId: 'g1',
              goalTitle: 'Run a half marathon',
              metric: 'Longest run in km',
              startValue: 5,
              currentValue: 14,
              currentAt: '2026-11-01T09:00:00Z',
              target: 21,
              deadline: '2026-10-31',
              themeIds: const ['p1']),
        ],
      ),
      'GET /connections': connections,
    });

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
}
