@Tags(['screenshots'])
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/month/month_screen.dart';
import 'package:tefteri/features/statistics/drilldown_screen.dart';
import 'package:tefteri/features/statistics/statistics_models.dart';
import 'package:tefteri/features/week/week_screen.dart';
import 'package:tefteri/features/year/year_screen.dart';

import 'fixtures.dart';
import 'screenshot_helper.dart';

/// Screenshots of the work categories and the statistics, from fake data.
/// They write `docs/images/statistics-*.png`.

/// The tasks of the week of 2 November 2026 as the server lists them. Every
/// task is in one of the three categories. The ignored project has one task
/// that the lists of the three categories leave out.
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
  statTaskJson('d6', 'Clean the old archive',
      category: 'hidden',
      completedDay: '2026-11-04',
      project: 'Old stuff',
      reason: 'ignored'),
];

/// The month of November 2026 for the drill-down of the month.
final _monthDone = [
  for (var i = 0; i < 6; i++)
    statTaskJson('m$i', 'Write chapter ${i + 1} of the guide',
        category: 'goal_aligned',
        completedDay: '2026-11-0${i + 1}',
        project: 'Write the docs',
        reason: 'committed_milestone'),
  statTaskJson('m6', 'Pay the water bill',
      category: 'maintenance',
      completedDay: '2026-11-03',
      project: 'Chores',
      reason: 'maintenance_label'),
  statTaskJson('m7', 'Sort the garage',
      category: 'off_plan',
      completedDay: '2026-11-02',
      project: 'Home',
      reason: 'theme'),
];

Map<String, Object?> _progress() => weekProgressJson(
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

List<Object?> _days(List<List<int>> c) => [
      for (var i = 0; i < 7; i++)
        {
          'start': '2026-11-0${2 + i}',
          'end': '2026-11-0${3 + i}',
          'counts': categoryCountsJson(c[i][0], c[i][1], c[i][2]),
          'hidden': 0,
        },
    ];

Map<String, Object?> _week() => statisticsJson(
      goalAligned: 2,
      maintenance: 1,
      offPlan: 2,
      unsorted: 1,
      hidden: 1,
      progress: _progress(),
      parts: _days([
        [1, 0, 0],
        [1, 1, 1],
        [0, 0, 1],
        [0, 0, 0],
        [0, 0, 0],
        [0, 0, 0],
        [0, 0, 0],
      ]),
    );

Map<String, Object?> _month() => statisticsJson(
      period: 'month',
      start: '2026-11-01',
      end: '2026-12-01',
      goalAligned: 14,
      maintenance: 9,
      offPlan: 5,
      hidden: 2,
      unsorted: 1,
    );

Map<String, Object?> _year() => statisticsJson(
      period: 'year',
      start: '2026-01-01',
      end: '2027-01-01',
      goalAligned: 120,
      maintenance: 70,
      offPlan: 40,
      hidden: 6,
    );

/// A period with no completed task, in a user who has not labelled projects.
Map<String, Object?> _empty(String period) => statisticsJson(
      period: period,
      start: '2026-11-01',
      end: '2026-12-01',
      empty: {'reason': 'no_labels', 'action': 'label_projects'},
    );

Object? _statistics(RequestOptions o, {bool empty = false}) {
  final period = o.queryParameters['period'];
  if (empty) return _empty('$period');
  return switch (period) {
    'month' => _month(),
    'year' => _year(),
    _ => _week(),
  };
}

FakeApi _api(
        {bool empty = false,
        List<Map<String, Object?>>? tasks,
        String period = 'week'}) =>
    FakeApi({
      'GET /statistics': (RequestOptions o) => _statistics(o, empty: empty),
      'GET /statistics/tasks': fakeStatisticsTasks(tasks ?? _weekDone,
          period: period,
          start: period == 'month' ? '2026-11-01' : '2026-11-02',
          end: period == 'month' ? '2026-12-01' : '2026-11-09'),
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
        'items': <Object?>[],
        'done': 0,
        'total': 0,
      },
      'GET /weekly/2026-11-02': {
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
                for (var n = 1; n <= 8; n++)
                  {
                    'id': 'c$n',
                    'title': 'Task $n',
                    'done': n <= 5,
                    'completed_day':
                        n <= 5 ? '2026-11-0${(n + 1) ~/ 2 + 1}' : null,
                  },
              ],
            },
          ],
        },
      },
      'GET /views/week/2026-11-02':
          periodJson('week', '2026-11-02', '2026-11-09'),
      'GET /views/month/2026-11-01':
          periodJson('month', '2026-11-01', '2026-12-01'),
      'GET /views/year/2026': periodJson('year', '2026-01-01', '2027-01-01'),
      'GET /goals': <Object?>[],
      'GET /connections': connections,
    });

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('week with the list of completed tasks', (tester) async {
    await pumpScreen(tester, _api(),
        WeekScreen(initialDate: day, today: DateTime(2026, 11, 4)),
        size: const Size(1100, 2350));
    await saveScreenshot('statistics-week');
  });

  testWidgets('month with counts and the bar', (tester) async {
    await pumpScreen(tester, _api(), MonthScreen(initialDate: day),
        size: const Size(1100, 900));
    await saveScreenshot('statistics-month');
  });

  testWidgets('year with counts and the bar', (tester) async {
    await pumpScreen(tester, _api(), const YearScreen(initialYear: 2026),
        size: const Size(1100, 900));
    await saveScreenshot('statistics-year');
  });

  testWidgets('drill-down into goal-aligned tasks of the month',
      (tester) async {
    await pumpScreen(
        tester,
        _api(tasks: _monthDone, period: 'month'),
        const DrilldownScreen(
            period: 'month', day: '2026-11-01', category: Category.goalAligned),
        size: const Size(1100, 900));
    await saveScreenshot('statistics-drilldown');
  });

  testWidgets('a month with no completed task', (tester) async {
    await pumpScreen(tester, _api(empty: true), MonthScreen(initialDate: day),
        size: const Size(1100, 700));
    await saveScreenshot('statistics-empty');
  });

  testWidgets('phone width', (tester) async {
    await pumpScreen(tester, _api(), MonthScreen(initialDate: day),
        size: const Size(390, 844));
    await saveScreenshot('statistics-phone');
  });
}
