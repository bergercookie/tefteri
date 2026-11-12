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
    WeeklyServer.project('tA', 'Work', kind: 'theme'),
    WeeklyServer.project('tB', 'Home', kind: 'theme'),
    WeeklyServer.project('p1', 'Website',
        tasks: 4,
        theme: 'tA',
        themeName: 'Work',
        doneState: 'The new site is live'),
    WeeklyServer.project('p2', 'Garden',
        tasks: 3,
        theme: 'tB',
        themeName: 'Home',
        doneState: 'The beds are planted'),
    WeeklyServer.project('p3', 'Taxes',
        tasks: 2,
        theme: 'tB',
        themeName: 'Home',
        doneState: 'The return is sent',
        rollover: 1),
    WeeklyServer.project('p4', 'Inbox', tasks: 2),
  ]);
  s.projects[3]['carried'] = 2;
  s.themes = [
    WeeklyServer.theme('tA', 'Work', milestones: 1),
    WeeklyServer.theme('tB', 'Home', milestones: 2),
  ];
  return s;
}

/// The weekly checklist of the user, with two items ticked.
final _checklist = {
  'period_type': 'week',
  'period_start': weekKey,
  'items': [
    {'text': 'Look back at last week', 'checked': true},
    {'text': 'Check the calendar for the week', 'checked': true},
    {'text': 'Clear the inbox', 'checked': false},
    {'text': 'Pick the most important tasks', 'checked': false},
    {'text': 'Block time for focused work', 'checked': false},
  ],
  'done': 2,
  'total': 5,
};

Future<void> _pump(WidgetTester tester, WeeklyServer s,
        {Map<String, Object?> extra = const {}}) =>
    pumpScreen(
        tester,
        FakeApi({
          ...s.allRoutes(),
          ...extra,
          'GET /checklists/week/$weekKey': _checklist,
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
                {'name': 'Website', 'done': true, 'milestone_id': 'm1'},
                {
                  'name': 'Garden',
                  'done': i == 0,
                  'decision': i == 0 ? null : 'recommit',
                  'milestone_id': 'm2'
                },
                {
                  'name': 'Taxes',
                  'done': false,
                  'decision': 'park',
                  'milestone_id': 'm3'
                },
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
    await tester.tap(find.byKey(const Key('new-milestone')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('milestone-name')), 'Launch campaign');
    await tester.enterText(
        find.byKey(const Key('milestone-done-state')), 'The campaign is live');
    await tester.tap(find.byKey(const Key('milestone-create')));
    await tester.pumpAndSettle();
    await saveScreenshot('weekly-projects');
  });

  testWidgets('the picker, grouped by theme', (tester) async {
    final s = _server()
      ..focusKnown = true
      ..chosen.add('p1');
    s.themes = [
      WeeklyServer.theme('tA', 'Work', inFocus: true, milestones: 1),
      WeeklyServer.theme('tB', 'Home', inFocus: false, milestones: 2),
    ];
    for (final p in s.projects) {
      if (p['theme'] == 'tA') p['in_focus'] = true;
      if (p['theme'] == 'tB') p['in_focus'] = false;
    }
    await _pump(tester, s);
    await _open(tester, 'projects');
    await saveScreenshot('weekly-picker');
  });

  testWidgets('new milestone', (tester) async {
    final s = _server();
    await _pump(tester, s);
    await _open(tester, 'projects');
    await tester.tap(find.byKey(const Key('new-milestone')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('milestone-name')), 'Launch campaign');
    await tester.enterText(
        find.byKey(const Key('milestone-done-state')), 'The campaign is live');
    await tester.pumpAndSettle();
    await saveScreenshot('weekly-new-milestone');
  });

  testWidgets('more than three milestones', (tester) async {
    final s = _server()..chosen.addAll(['p1', 'p2', 'p3', 'p4']);
    await _pump(tester, s);
    await _open(tester, 'projects');
    await saveScreenshot('weekly-cap');
  });

  testWidgets('close a milestone', (tester) async {
    final s = _server(lookBack: sampleLookBack());
    await _pump(tester, s, extra: {
      'POST /milestones/m-op2/close': {
        'open_tasks': 2,
        'theme': {'id': 'th-work', 'name': 'Work'},
        'message': '2 open tasks will move to Work.',
      },
    });
    await tester.tap(find.byKey(const Key('decision-close-op2')));
    await tester.pumpAndSettle();
    await saveScreenshot('weekly-close');
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
