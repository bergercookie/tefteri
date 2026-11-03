import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_helpers.dart';

Map<String, Object?> _full(String id, String title,
        {DateTime? due,
        String? description,
        String status = 'open',
        String? context = 'work',
        String syncState = 'synced'}) =>
    {
      ...dueTask(id, title, due: due),
      'description': description,
      'status': status,
      'context': context,
      'effective_context': context ?? 'life',
      'sync_state': syncState,
    };

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('a click on a task in the list opens its details',
      (tester) async {
    final api = plannerApi(
      tasksFor: (_) => [
        _full('t1', 'Write report',
            due: DateTime(2026, 11, 4, 15),
            description: 'Cover the Q3 numbers.'),
      ],
      extra: {
        'GET /tasks/t1': _full('t1', 'Write report',
            due: DateTime(2026, 11, 4, 15),
            description: 'Cover the Q3 numbers.\nAdd the chart.'),
      },
    );
    await pumpPlanner(tester, api);
    await tester.tap(find.byKey(const Key('task-t1')));
    await settle(tester);

    expect(find.byKey(const Key('task-details')), findsOneWidget);
    expect(_text(tester, 'task-details-title'), 'Write report');
    expect(_text(tester, 'task-details-status'), 'Open');
    expect(_text(tester, 'task-details-due'), '2026-11-04 15:00');
    expect(_text(tester, 'task-details-calendar'), '2026-11-04, 14:00 - 15:00');
    expect(_text(tester, 'task-details-context'), 'Work');
    // refreshed from the server: the longer description shows
    expect(_text(tester, 'task-details-description'),
        'Cover the Q3 numbers.\nAdd the chart.');
    expect(api.where('GET /tasks/t1'), hasLength(1));

    await tester.tap(find.byKey(const Key('task-details-close')));
    await settle(tester);
    expect(find.byKey(const Key('task-details')), findsNothing);
  });

  testWidgets('a task without a date or description says so', (tester) async {
    final api = plannerApi(
      tasksFor: (_) => [_full('t1', 'Plan trip', context: null)],
      extra: {'GET /tasks/t1': _full('t1', 'Plan trip', context: null)},
    );
    await pumpPlanner(tester, api);
    await tester.tap(find.byKey(const Key('task-t1')));
    await settle(tester);
    expect(_text(tester, 'task-details-due'), 'No due date');
    expect(_text(tester, 'task-details-calendar'), 'Not on the calendar');
    expect(_text(tester, 'task-details-description'), 'No description.');
    expect(_text(tester, 'task-details-context'),
        'Life (no label, follows the app)');
  });

  testWidgets('a done task and a date-only task show the right text',
      (tester) async {
    final api = plannerApi(
      tasksFor: (_) => [_full('t1', 'Pay rent')],
      extra: {
        'GET /tasks/t1': {
          ..._full('t1', 'Pay rent', status: 'done'),
          'due_at': DateTime(2026, 11, 5).toUtc().toIso8601String(),
          'scheduled_start': null,
          'scheduled_end': null,
        },
      },
    );
    await pumpPlanner(tester, api);
    await tester.tap(find.byKey(const Key('task-t1')));
    await settle(tester);
    expect(_text(tester, 'task-details-status'), 'Done');
    expect(_text(tester, 'task-details-due'), '2026-11-05');
    expect(_text(tester, 'task-details-calendar'), '2026-11-05, all day');
  });

  testWidgets('a task in conflict tells the user where to go', (tester) async {
    final api = plannerApi(
      tasksFor: (_) => [_full('t1', 'Write report', syncState: 'conflict')],
      extra: {
        'GET /tasks/t1': _full('t1', 'Write report', syncState: 'conflict')
      },
    );
    await pumpPlanner(tester, api);
    await tester.tap(find.byKey(const Key('task-t1')));
    await settle(tester);
    expect(_text(tester, 'task-details-sync'),
        'Changed in both places. Open the Conflicts screen.');
  });

  testWidgets('a click on a task block in the calendar opens its details',
      (tester) async {
    final api = plannerApi(
      calendar: [
        calItem('task', 'c9', 'Prepare the demo',
            start: DateTime(2026, 11, 4, 14), end: DateTime(2026, 11, 4, 15)),
      ],
      extra: {
        'GET /tasks/c9': _full('c9', 'Prepare the demo',
            due: DateTime(2026, 11, 4, 15),
            description: 'Slides and a dry run.'),
      },
    );
    await pumpPlanner(tester, api);
    await tester.tap(find.byKey(const Key('block-task-c9')));
    await settle(tester);
    expect(_text(tester, 'task-details-title'), 'Prepare the demo');
    expect(_text(tester, 'task-details-description'), 'Slides and a dry run.');
    expect(_text(tester, 'task-details-calendar'), '2026-11-04, 14:00 - 15:00');
  });

  testWidgets('the block pop-up shows the title while the task loads',
      (tester) async {
    final api = plannerApi(calendar: [
      calItem('task', 'c9', 'Prepare the demo',
          start: DateTime(2026, 11, 4, 14)),
    ]);
    await pumpPlanner(tester, api); // GET /tasks/c9 answers 404
    await tester.tap(find.byKey(const Key('block-task-c9')));
    await settle(tester);
    expect(_text(tester, 'task-details-title'), 'Prepare the demo');
    expect(find.byKey(const Key('task-details-error')), findsOneWidget);
    expect(find.byKey(const Key('task-details-retry')), findsOneWidget);
  });

  testWidgets('a click on an all-day task opens its details', (tester) async {
    final api = plannerApi(
      calendar: [
        calItem('task', 'c5', 'Pay the invoice',
            start: DateTime(2026, 11, 5),
            end: DateTime(2026, 11, 6),
            allDay: true),
      ],
      extra: {'GET /tasks/c5': _full('c5', 'Pay the invoice')},
    );
    await pumpPlanner(tester, api);
    await tester.tap(find.byKey(const Key('allday-task-c5')));
    await settle(tester);
    expect(_text(tester, 'task-details-title'), 'Pay the invoice');
  });

  testWidgets('a click on a calendar event opens the event details',
      (tester) async {
    final api = plannerApi(calendar: [
      calItem('entry', 'e1', 'Team standup',
          start: DateTime(2026, 11, 3, 9), end: DateTime(2026, 11, 3, 9, 30)),
    ]);
    await pumpPlanner(tester, api);
    await tester.tap(find.byKey(const Key('block-entry-e1')));
    await settle(tester);
    expect(_text(tester, 'event-details-title'), 'Team standup');
    expect(_text(tester, 'task-details-when'), '2026-11-03, 09:00 - 09:30');
    expect(_text(tester, 'task-details-type'), 'Calendar event');
    expect(api.where('GET /tasks/e1'), isEmpty); // no task to load
    await tester.tap(find.byKey(const Key('event-details-close')));
    await settle(tester);
    expect(find.byKey(const Key('event-details')), findsNothing);
  });

  testWidgets('a drag still moves a task and does not open the details',
      (tester) async {
    final api = plannerApi(
      extra: {'PUT /tasks/t1/schedule': dueTask('t1', 'x')},
    );
    await pumpPlanner(tester, api);
    await dragTo(tester, find.byKey(const Key('task-t1')),
        slotPoint(tester, wednesday, 9, 0));
    expect(api.where('PUT /tasks/t1/schedule'), hasLength(1));
    expect(find.byKey(const Key('task-details')), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
