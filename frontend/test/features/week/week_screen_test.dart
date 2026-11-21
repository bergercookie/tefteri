import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/week/week_screen.dart';

import '../../support/fake_api.dart';

// 2026-11-04 is a Wednesday; its week starts on Monday 2026-11-02.
final _day = DateTime(2026, 11, 4);
const _path = 'GET /views/week/2026-11-02';

Map<String, Object?> _week() => periodJson(
      'week',
      '2026-11-02',
      '2026-11-09',
      goalTitles: {
        'g1': {'title': 'Ship beta', 'annual': false},
        'a1': {'title': 'Get better at open source', 'annual': true},
      },
      tasks: [
        {
          ...taskJson('t1', 'Write plan'),
          'goal_id': 'g1',
          'category': 'goal_aligned'
        },
        {
          ...taskJson('t5', 'Send the invoice', status: 'done'),
          'completed_at':
              DateTime(2026, 11, 3, 16, 45).toUtc().toIso8601String(),
        },
        taskJson('t6', 'Fix the old bug', status: 'done'),
        {
          ...taskJson('t4', 'Review a pull request'),
          'goal_id': 'a1',
          'category': 'off_plan'
        },
        {
          ...taskJson('t2', 'Call Sam'),
          'scheduled_start': '2026-11-03T09:00:00Z',
        },
        {
          ...taskJson('t3', 'File the taxes'),
          'due_at': DateTime(2026, 11, 5).toUtc().toIso8601String(),
        },
      ],
      entries: [
        {
          'id': 'e1',
          'connection_id': 'c2',
          'title': 'Standup',
          'start': DateTime(2026, 11, 3, 10).toUtc().toIso8601String(),
          'end': null,
          'all_day': false,
          'sync_state': 'synced',
        },
      ],
    );

final _done = [
  statTaskJson('d1', 'Write the spec',
      category: 'goal_aligned', project: 'Website'),
  statTaskJson('d2', 'Take out the bins',
      category: 'maintenance', project: 'Chores'),
  for (var i = 0; i < 7; i++)
    statTaskJson('o$i', 'Errand $i', category: 'off_plan', project: 'Home'),
];

final _open = [
  openTaskJson('o1', 'Book the venue',
      category: 'goal_aligned', project: 'Website'),
  openTaskJson('o2', 'Pay the rent',
      category: 'maintenance', project: 'Chores'),
];

FakeApi _api([Map<String, Object?> extra = const {}]) => FakeApi({
      _path: _week(),
      'GET /statistics': statisticsJson(
        goalAligned: 1,
        maintenance: 1,
        offPlan: 7,
        progress: weekProgressJson(),
      ),
      'GET /statistics/tasks': fakeStatisticsTasks(_done),
      'GET /statistics/open': openTasksJson(tasks: _open),
      'GET /weekly/2026-11-02': _weekly(),
      ...extra,
    });

Map<String, Object?> _weekly() => {
      'week_start': '2026-11-02',
      'week_end': '2026-11-09',
      'look_back': null,
      'plan': {
        'id': 'p',
        'status': 'committed',
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
            'committed_tasks': <Object?>[],
          },
        ],
      },
    };

Future<void> _pump(WidgetTester tester, FakeApi api) {
  SharedPreferences.setMockInitialValues({});
  return pumpWithApi(tester, api, WeekScreen(initialDate: _day));
}

double topOf(WidgetTester tester, String key) =>
    tester.getTopLeft(find.byKey(Key(key))).dy;

void main() {
  testWidgets('due tasks group by theme and project, and hide done on demand',
      (tester) async {
    final week = periodJson('week', '2026-11-02', '2026-11-09', tasks: [
      {...taskJson('a', 'Alpha'), 'theme': 'Health', 'project': 'Running'},
      {
        ...taskJson('b', 'Beta', status: 'done'),
        'theme': 'Health',
        'project': 'Running'
      },
      {...taskJson('c', 'Gamma'), 'theme': 'Health', 'project': 'Health'},
      {...taskJson('d', 'Delta'), 'project': 'Errands'},
    ], entries: []);
    await _pump(tester, _api({_path: week}));
    expect(find.byKey(const Key('theme-Health')), findsOneWidget);
    expect(find.byKey(const Key('theme-none')), findsOneWidget);
    expect(find.byKey(const Key('subproject-Health-Running')), findsOneWidget);
    expect(find.byKey(const Key('subproject-Health-Health')), findsNothing);
    expect(find.text('Beta'), findsOneWidget);
    await tester.tap(find.byKey(const Key('show-done-filter')));
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('a work theme has the Work pill, and its tasks a briefcase',
      (tester) async {
    final week = periodJson('week', '2026-11-02', '2026-11-09', tasks: [
      {
        ...taskJson('a', 'Alpha'),
        'theme': 'Job',
        'project': 'Launch',
        'work': true
      },
      {...taskJson('b', 'Beta'), 'theme': 'Home', 'project': 'Garden'},
    ], entries: []);
    await _pump(
        tester,
        _api({
          _path: week,
          'GET /statistics/open': openTasksJson(tasks: [
            openTaskJson('o1', 'Book the venue',
                category: 'goal_aligned', project: 'Website', work: true),
            openTaskJson('o2', 'Pay the rent',
                category: 'maintenance', project: 'Chores'),
          ]),
        }));
    // The theme header says Work for the work theme only.
    expect(
        find.descendant(
            of: find.byKey(const Key('theme-Job')),
            matching: find.text('Work')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('theme-Home')),
            matching: find.text('Work')),
        findsNothing);
    // The tasks: the project chip of a work task has the briefcase.
    Finder icon(String key) => find.descendant(
        of: find.byKey(Key(key)), matching: find.byIcon(Icons.work_outline));
    expect(icon('task-a'), findsOneWidget);
    expect(icon('task-b'), findsNothing);
    // The same on the card Still to do.
    expect(icon('open-task-o1'), findsOneWidget);
    expect(icon('open-task-o2'), findsNothing);
  });

  testWidgets('a project and a theme of the due list fold away',
      (tester) async {
    final week = periodJson('week', '2026-11-02', '2026-11-09', tasks: [
      {...taskJson('a', 'Alpha'), 'theme': 'Health', 'project': 'Running'},
      {...taskJson('b', 'Beta'), 'theme': 'Health', 'project': 'Cycling'},
      {...taskJson('d', 'Delta'), 'project': 'Errands'},
    ], entries: []);
    await _pump(tester, _api({_path: week}));
    // Fold one project: only its tasks go.
    await tester.tap(find.byKey(const Key('subproject-Health-Running')));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Delta'), findsOneWidget);
    // Fold the theme: its projects and tasks go, the other theme stays.
    await tester.tap(find.byKey(const Key('theme-Health')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('subproject-Health-Cycling')), findsNothing);
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Delta'), findsOneWidget);
    // Unfold it again: the project that was folded stays folded.
    await tester.tap(find.byKey(const Key('theme-Health')));
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets('shows tasks, but no goal section and no events', (tester) async {
    final api = _api();
    await _pump(tester, api);
    expect(find.text('Week of 2026-11-02'), findsOneWidget);
    expect(find.text('Goals'), findsNothing);
    expect(find.byKey(const Key('no-goals')), findsNothing);
    expect(find.byKey(const Key('goal-progress-g1')), findsNothing);
    expect(find.text('Standup'), findsNothing);
    expect(find.byKey(const Key('no-events')), findsNothing);
    expect(find.text('Write plan'), findsOneWidget);
    expect(find.textContaining('Not scheduled'), findsWidgets);
  });

  testWidgets('each due task says whether it is done and when, or pending',
      (tester) async {
    await _pump(tester, _api());
    String status(String id) =>
        tester.widget<Text>(find.byKey(Key('task-status-$id'))).data!;
    expect(status('t1'), 'Pending - not done yet');
    expect(status('t2'), 'Pending - not done yet');
    expect(status('t5'), 'Done 2026-11-03 16:45');
    expect(status('t6'), 'Done - completion time not known');
  });

  testWidgets('each task section explains itself in a tip', (tester) async {
    await _pump(tester, _api());
    expect(find.text('All due this week'), findsOneWidget);
    final due = tester.widget<Tooltip>(find.ancestor(
        of: find.byKey(const Key('info-All due this week')),
        matching: find.byType(Tooltip)));
    expect(due.message, contains('done or not'));
    expect(find.text('Completed this week'), findsNothing);
  });

  testWidgets('a task shows its annual goal, and an old goal as history',
      (tester) async {
    final api = _api({'PATCH /tasks/t1': taskJson('t1', 'x')});
    await _pump(tester, api);
    expect(
        find.textContaining('Goal: Get better at open source'), findsOneWidget);
    expect(find.textContaining('Goal (history): Ship beta'), findsOneWidget);
    expect(find.textContaining('Goal: Ship beta'), findsNothing);
    // The old link can be cleared.
    await tester.tap(find.byKey(const Key('task-menu-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove goal'));
    await tester.pumpAndSettle();
    expect(
        (api.where('PATCH /tasks/t1').single.data! as Map)['goal_id'], isNull);
  });

  testWidgets('says what goal-aligned means in one line', (tester) async {
    await _pump(tester, _api());
    expect(
        find.text(
            'Goal-aligned means work in a milestone you committed to this week.'),
        findsOneWidget);
  });

  testWidgets('shows the completed card and, below it, the open card',
      (tester) async {
    final api = _api();
    await _pump(tester, api);
    expect(find.byKey(const Key('categories-card')), findsOneWidget);
    expect(find.text('Completed work'), findsOneWidget);
    expect(find.byKey(const Key('open-work-card')), findsOneWidget);
    expect(find.text('Still to do'), findsOneWidget);
    // The open card sits right below the completed one.
    expect(topOf(tester, 'open-work-card'),
        greaterThan(topOf(tester, 'categories-card')));
    // There is no list of completed tasks any more.
    expect(find.text('Completed this week'), findsNothing);
    expect(find.byKey(const Key('completed-by-category')), findsNothing);
    expect(find.text('Write the spec'), findsNothing);
    // The open card has the same three groups, with their tasks.
    for (final c in ['goal_aligned', 'maintenance', 'off_plan']) {
      expect(find.byKey(Key('open-group-$c')), findsOneWidget);
    }
    expect(find.text('Book the venue'), findsOneWidget);
    expect(find.text('Pay the rent'), findsOneWidget);
    expect(find.text('2 tasks still to do'), findsOneWidget);
    expect(
        api.where('GET /statistics/open').single.query, {'day': '2026-11-02'});
  });

  testWidgets('a group of the open card folds away', (tester) async {
    await _pump(tester, _api());
    await tester.tap(find.byKey(const Key('open-group-toggle-maintenance')));
    await tester.pumpAndSettle();
    expect(find.text('Pay the rent'), findsNothing);
    expect(find.text('Book the venue'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-group-toggle-maintenance')));
    await tester.pumpAndSettle();
    expect(find.text('Pay the rent'), findsOneWidget);
  });

  testWidgets('the progress card draws the numbers of the server',
      (tester) async {
    await _pump(
        tester,
        _api({
          'GET /statistics': statisticsJson(
            goalAligned: 1,
            progress: weekProgressJson(
                committed: 9, done: 7, doneByDay: const [3, 2, 2, 0, 0, 0, 0]),
          ),
        }));
    expect(find.text('7 of 9 tasks done'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('stat-left')), matching: find.text('2')),
        findsOneWidget);
    expect(find.text('Total 7'), findsOneWidget);
  });

  testWidgets('the open card lists every task, with no limit of five',
      (tester) async {
    await _pump(
        tester,
        _api({
          'GET /statistics/open': openTasksJson(tasks: [
            for (var i = 0; i < 7; i++)
              openTaskJson('x$i', 'Errand $i', project: 'Home'),
          ]),
        }));
    expect(find.byKey(const Key('done-outside-plan')), findsNothing);
    expect(find.byKey(const Key('extra-toggle')), findsNothing);
    for (var i = 0; i < 7; i++) {
      expect(find.text('Errand $i'), findsOneWidget);
    }
  });

  testWidgets('a task with only a day shows that day as planned',
      (tester) async {
    await _pump(tester, _api());
    expect(find.textContaining('Planned 2026-11-05 - All day'), findsOneWidget);
    await tester.tap(find.byKey(const Key('task-menu-t3')));
    await tester.pumpAndSettle();
    expect(find.text('Unschedule'), findsOneWidget);
    expect(find.text('Change time'), findsOneWidget);
  });

  testWidgets('next week loads the following Monday', (tester) async {
    final api = _api({
      'GET /views/week/2026-11-09':
          periodJson('week', '2026-11-09', '2026-11-16'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('next-period')));
    await tester.pumpAndSettle();
    expect(api.where('GET /views/week/2026-11-09'), hasLength(1));
    expect(find.text('Week of 2026-11-09'), findsOneWidget);
    expect(find.byKey(const Key('no-tasks')), findsOneWidget);
  });

  testWidgets('schedule puts the task on the chosen day and hour',
      (tester) async {
    final api = _api({'PUT /tasks/t1/schedule': taskJson('t1', 'x')});
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('task-menu-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-day')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-11-04').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-confirm')));
    await tester.pumpAndSettle();
    final put = api.where('PUT /tasks/t1/schedule').single;
    expect((put.data! as Map)['start'],
        DateTime(2026, 11, 4, 9).toUtc().toIso8601String());
    expect(api.where('POST /calendar/entries'), isEmpty);
    expect(api.where(_path), hasLength(2));
  });

  testWidgets('unschedule calls DELETE on the schedule', (tester) async {
    final api = _api({'DELETE /tasks/t2/schedule': taskJson('t2', 'x')});
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('task-menu-t2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unschedule'));
    await tester.pumpAndSettle();
    expect(api.where('DELETE /tasks/t2/schedule'), hasLength(1));
  });

  testWidgets('every task says DONE or TODO, in the color of its category',
      (tester) async {
    await _pump(tester, _api());
    Finder label(String id, String text) =>
        find.descendant(of: find.byKey(Key(id)), matching: find.text(text));
    // t5 and t6 are done; t1 and t4 are still to do.
    expect(label('task-done-t5', 'DONE'), findsOneWidget);
    expect(label('task-done-t6', 'DONE'), findsOneWidget);
    expect(label('task-complete-t1', 'TODO'), findsOneWidget);
    expect(label('task-complete-t4', 'TODO'), findsOneWidget);
    expect(find.text('DONE'), findsNWidgets(2));
    // A pending task of the open card says TODO too.
    expect(label('open-complete-o1', 'TODO'), findsOneWidget);
    Color border(String id) {
      final material = tester.widget<Material>(find
          .descendant(of: find.byKey(Key(id)), matching: find.byType(Material))
          .first);
      return ((material.shape! as RoundedRectangleBorder).side).color;
    }

    final scheme = Theme.of(tester.element(find.byType(Scaffold).first));
    // Goal-aligned is blue, off-plan is orange: the borders differ.
    expect(border('task-complete-t1'), scheme.colorScheme.primary);
    expect(border('task-complete-t4'), isNot(border('task-complete-t1')));
    expect(border('open-complete-o1'), border('task-complete-t1'));
    expect(border('open-complete-o2'), isNot(border('open-complete-o1')));
    // DONE is filled; TODO is an empty frame.
    Color? fill(String id) => tester
        .widget<Material>(find
            .descendant(
                of: find.byKey(Key(id)), matching: find.byType(Material))
            .first)
        .color;
    expect(fill('task-done-t5'), isNot(Colors.transparent));
    expect(fill('task-complete-t1'), Colors.transparent);
  });

  testWidgets('a due task is marked done from its button and from its menu',
      (tester) async {
    final api = _api({
      'POST /tasks/t1/complete': taskJson('t1', 'x', status: 'done'),
      'POST /tasks/t2/complete': taskJson('t2', 'x', status: 'done'),
    });
    await _pump(tester, api);
    // A done task has no button.
    expect(find.byKey(const Key('task-complete-t5')), findsNothing);
    await tester.tap(find.byKey(const Key('task-complete-t1')));
    await tester.pumpAndSettle();
    expect(api.where('POST /tasks/t1/complete'), hasLength(1));
    // The week and the numbers are read again.
    expect(api.where('GET /views/week/2026-11-02').length, greaterThan(1));
    expect(api.where('GET /statistics/open').length, greaterThan(1));
    await tester.tap(find.byKey(const Key('task-menu-t2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark done'));
    await tester.pumpAndSettle();
    expect(api.where('POST /tasks/t2/complete'), hasLength(1));
  });

  testWidgets('a task of the open card is marked done', (tester) async {
    final api = _api({
      'POST /tasks/o1/complete': taskJson('o1', 'x', status: 'done'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('open-complete-o1')));
    await tester.pumpAndSettle();
    expect(api.where('POST /tasks/o1/complete'), hasLength(1));
    expect(api.where('GET /statistics/open').length, greaterThan(1));
  });

  testWidgets('a failed completion shows the server message', (tester) async {
    final api = _api({
      'POST /tasks/o1/complete':
          const ApiFailure(502, 'The task app did not answer.', 'unavailable'),
      'POST /tasks/t1/complete':
          const ApiFailure(502, 'The task app did not answer.', 'unavailable'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('open-complete-o1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-work-action-error')), findsOneWidget);
    expect(find.text('The task app did not answer.'), findsWidgets);
    expect(find.text('Book the venue'), findsOneWidget);
    await tester.tap(find.byKey(const Key('task-complete-t1')));
    await tester.pumpAndSettle();
    expect(find.text('Write plan'), findsOneWidget);
  });

  testWidgets('a task can be linked to a goal of the annual plan',
      (tester) async {
    final year = DateTime.now().year;
    final api = _api({
      'PATCH /tasks/t2': taskJson('t2', 'x'),
      'GET /annual/$year': annualPlanJson(year: year, goals: [
        annualGoalJson('a1', 'Get better at open source'),
      ]),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('task-menu-t2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link to goal'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('link-goal-g1')), findsNothing);
    await tester.tap(find.byKey(const Key('link-goal-a1')));
    await tester.pumpAndSettle();
    expect((api.where('PATCH /tasks/t2').single.data! as Map)['goal_id'], 'a1');
  });

  testWidgets('a scheduling failure shows the server message', (tester) async {
    final api = _api({
      'PUT /tasks/t1/schedule': const ApiFailure(
          409, 'Scheduling is not available for this app.', 'not_supported'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('task-menu-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-confirm')));
    await tester.pumpAndSettle();
    expect(
        find.text('Scheduling is not available for this app.'), findsOneWidget);
  });

  testWidgets('a load failure offers a retry', (tester) async {
    final api = FakeApi({
      _path:
          const ApiFailure(502, 'The server is down.', 'backend_unavailable'),
    });
    await _pump(tester, api);
    expect(find.text('The server is down.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reload-button')));
    await tester.pumpAndSettle();
    expect(api.where(_path), hasLength(2));
  });
}
