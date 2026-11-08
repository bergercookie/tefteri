@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/weekly/weekly_api.dart';
import 'package:tefteri/features/weekly/weekly_screen.dart';

import '../features/weekly/weekly_fake.dart';
import 'fixtures.dart';
import 'screenshot_helper.dart';

final _noPolling = [weeklyPollIntervalProvider.overrideWithValue(null)];

WeeklyServer _server({Map<String, Object?>? lookBack}) {
  final s = WeeklyServer(lookBack: lookBack, projects: [
    WeeklyServer.project('p1', 'Website', tasks: 4),
    WeeklyServer.project('p2', 'Garden', tasks: 3),
    WeeklyServer.project('p3', 'Taxes', tasks: 2),
    WeeklyServer.project('p4', 'Inbox', tasks: 2),
  ]);
  s.projects[2]['carried'] = 2;
  return s;
}

Future<void> _pump(WidgetTester tester, WeeklyServer s) => pumpScreen(
    tester,
    FakeApi({
      ...s.allRoutes(),
      // No refresh: the page would show the time of the check, which changes.
      'POST /weekly/$weekKey/refresh':
          const ApiFailure(502, 'offline', 'backend_unavailable'),
      'GET /views/week/$weekKey':
          periodJson('week', weekKey, '2030-03-11', entries: [
        entryJson('e1', 'Team standup', DateTime(2030, 3, 5, 9)),
        entryJson('e2', 'Dentist', DateTime(2030, 3, 7, 14)),
      ]),
    }),
    WeeklyPlanningScreen(initialDate: DateTime(2030, 3, 6)),
    overrides: _noPolling);

Future<void> _open(WidgetTester tester, String step) async {
  await tester.tap(find.byKey(Key('check-$step')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('look back', (tester) async {
    await _pump(tester, _server(lookBack: sampleLookBack()));
    await saveScreenshot('weekly-look-back');
  });

  testWidgets('earlier weeks', (tester) async {
    final s = _server(lookBack: sampleLookBack(reviewed: true))
      ..history = {
        'entries': [
          for (final (i, w)
              in ['2030-02-25', '2030-02-18', '2030-02-11'].indexed)
            {
              'plan_id': 'h$i',
              'week_start': w,
              'committed_projects': 3,
              'done_projects': [2, 1, 1][i],
              'committed_tasks': 9,
              'done_tasks': [7, 4, 3][i],
              'reflection': i == 1 ? 'Too many garden jobs for one week.' : '',
              'projects': [
                {'name': 'Website', 'done': true},
                {'name': 'Garden', 'done': i == 0},
                {'name': 'Taxes', 'done': false},
              ],
            },
        ],
        'totals': {
          'weeks': 3,
          'committed_projects': 9,
          'done_projects': 4,
          'committed_tasks': 27,
          'done_tasks': 14,
        },
      };
    await _pump(tester, s);
    await _open(tester, 'lookBack');
    await saveScreenshot('weekly-history');
  });

  testWidgets('choose projects', (tester) async {
    final s = _server()..chosen.add('p3');
    await _pump(tester, s);
    await _open(tester, 'projects');
    await tester.tap(find.byKey(const Key('new-subproject')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('subproject-name')), 'Launch campaign');
    await tester.tap(find.byKey(const Key('subproject-create')));
    await tester.pumpAndSettle();
    await saveScreenshot('weekly-projects');
  });

  testWidgets('give tasks a day', (tester) async {
    final s = _server()
      ..chosen.addAll(['p1', 'p2'])
      ..days.addAll({
        'p1-t1': '2030-03-05',
        'p1-t2': '2030-03-05',
        'p1-t3': '2030-03-07',
        'p2-t1': '2030-03-06',
      });
    await _pump(tester, s);
    await _open(tester, 'tasks');
    await saveScreenshot('weekly-tasks');
  });

  testWidgets('check and commit', (tester) async {
    final s = _server()
      ..chosen.addAll(['p1', 'p2'])
      ..days.addAll({
        'p1-t1': '2030-03-05',
        'p1-t2': '2030-03-06',
        'p1-t3': '2030-03-07',
        'p1-t4': '2030-03-08',
        'p2-t1': '2030-03-06',
        'p2-t2': '2030-03-07',
        'p2-t3': '2030-03-08',
      });
    await _pump(tester, s);
    await _open(tester, 'finish');
    await saveScreenshot('weekly-finish');
  });
}
