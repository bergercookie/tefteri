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
      goals: [
        goalJson('g1', 'Ship beta',
            periodType: 'week', periodStart: '2026-11-02', progress: 0.5),
      ],
      tasks: [
        {...taskJson('t1', 'Write plan'), 'goal_id': 'g1'},
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

FakeApi _api([Map<String, Object?> extra = const {}]) => FakeApi({
      _path: _week(),
      'GET /statistics': statisticsJson(
        goalAligned: 1,
        maintenance: 1,
        offPlan: 7,
        progress: weekProgressJson(),
      ),
      'GET /statistics/tasks': fakeStatisticsTasks(_done),
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

void main() {
  testWidgets('shows goals with progress and tasks, but no events',
      (tester) async {
    final api = _api();
    await _pump(tester, api);
    expect(find.text('Week of 2026-11-02'), findsOneWidget);
    expect(find.text('Ship beta'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('goal-progress-g1')));
    expect(bar.value, 0.5);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Standup'), findsNothing);
    expect(find.byKey(const Key('no-events')), findsNothing);
    expect(find.text('Write plan'), findsOneWidget);
    expect(find.textContaining('Goal: Ship beta'), findsOneWidget);
    expect(find.textContaining('Not scheduled'), findsOneWidget);
  });

  testWidgets('says what goal-aligned means in one line', (tester) async {
    await _pump(tester, _api());
    expect(
        find.text(
            'Goal-aligned means work in a milestone you committed to this week.'),
        findsOneWidget);
  });

  testWidgets('shows the categories card and the completed list',
      (tester) async {
    final api = _api();
    await _pump(tester, api);
    expect(find.byKey(const Key('categories-card')), findsOneWidget);
    expect(find.byKey(const Key('proportion-bar')), findsOneWidget);
    for (final c in ['goal_aligned', 'maintenance', 'off_plan']) {
      expect(find.byKey(Key('completed-group-$c')), findsOneWidget);
    }
    expect(find.text('Write the spec'), findsOneWidget);
    expect(find.text('Take out the bins'), findsOneWidget);
    expect(api.where('GET /statistics').first.query,
        {'period': 'week', 'day': '2026-11-02'});
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

  testWidgets('there is no "outside the plan" list with a limit of five',
      (tester) async {
    await _pump(tester, _api());
    expect(find.byKey(const Key('done-outside-plan')), findsNothing);
    expect(find.text('Done outside the plan'), findsNothing);
    expect(find.byKey(const Key('extra-toggle')), findsNothing);
    // All 7 off-plan tasks show, not the first five.
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
    expect(find.byKey(const Key('no-goals')), findsOneWidget);
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

  testWidgets('a task can be linked to a goal', (tester) async {
    final api = _api({'PATCH /tasks/t2': taskJson('t2', 'x')});
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('task-menu-t2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link to goal'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('link-goal-g1')));
    await tester.pumpAndSettle();
    expect((api.where('PATCH /tasks/t2').single.data! as Map)['goal_id'], 'g1');
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
