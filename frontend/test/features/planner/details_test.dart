import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/planner/details_dialogs.dart';

import '../../support/fake_api.dart';
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

/// The text typed in the field with [key].
String _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

/// What a date or time field of the form shows.
String _picker(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key('$key-value'))).data!;

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
    expect(_field(tester, 'task-edit-title'), 'Write report');
    expect(_text(tester, 'task-details-status'), 'Open');
    expect(_picker(tester, 'task-edit-date'), '2026-11-04');
    expect(_picker(tester, 'task-edit-time'), '14:00');
    expect(_text(tester, 'task-details-calendar'), '2026-11-04, 14:00 - 15:00');
    expect(_text(tester, 'task-details-context'), 'Work');
    // refreshed from the server: the longer description shows
    expect(_field(tester, 'task-edit-description'),
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
    expect(_picker(tester, 'task-edit-date'), 'No date');
    expect(_picker(tester, 'task-edit-time'), '-');
    expect(_text(tester, 'task-details-calendar'), 'Not on the calendar');
    expect(_field(tester, 'task-edit-description'), '');
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
    expect(_picker(tester, 'task-edit-date'), '2026-11-05');
    expect(_picker(tester, 'task-edit-time'), 'All day');
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
    expect(_field(tester, 'task-edit-title'), 'Prepare the demo');
    expect(_field(tester, 'task-edit-description'), 'Slides and a dry run.');
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
    expect(_text(tester, 'task-details-heading'), 'Prepare the demo');
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
    expect(_field(tester, 'task-edit-title'), 'Pay the invoice');
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

  group('editing', () {
    Future<FakeApi> open(WidgetTester tester,
        {Map<String, Object?> extra = const {},
        DateTime? due,
        bool allDay = false}) async {
      final task = {
        ..._full('t1', 'Write report',
            due: due, description: 'Cover the Q3 numbers.'),
        if (allDay) 'scheduled_start': null,
        if (allDay) 'scheduled_end': null,
      };
      final api = plannerApi(
        tasksFor: (_) => [task],
        extra: {'GET /tasks/t1': task, ...extra},
      );
      await pumpPlanner(tester, api);
      await tester.tap(find.byKey(const Key('task-t1')));
      await settle(tester);
      return api;
    }

    bool saveEnabled(WidgetTester tester) =>
        tester
            .widget<FilledButton>(find.byKey(const Key('task-save')))
            .onPressed !=
        null;

    testWidgets('Save is off until something changes', (tester) async {
      await open(tester);
      expect(saveEnabled(tester), isFalse);
      await tester.enterText(
          find.byKey(const Key('task-edit-title')), 'Write the report');
      await tester.pump();
      expect(saveEnabled(tester), isTrue);
      await tester.enterText(
          find.byKey(const Key('task-edit-title')), 'Write report');
      await tester.pump();
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('the title and the description are written to the task app',
        (tester) async {
      final api = await open(tester, extra: {
        'PATCH /tasks/t1': _full('t1', 'x'),
      });
      await tester.enterText(
          find.byKey(const Key('task-edit-title')), '  Write the report  ');
      await tester.enterText(find.byKey(const Key('task-edit-description')),
          'Cover the Q3 numbers.\nAdd the chart.');
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-save')));
      await settle(tester);
      expect(api.where('PATCH /tasks/t1').single.data, {
        'title': 'Write the report',
        'description': 'Cover the Q3 numbers.\nAdd the chart.',
      });
      expect(api.where('PUT /tasks/t1/schedule'), isEmpty);
      expect(find.byKey(const Key('task-details')), findsNothing);
      // The planner reloads its lists.
      expect(api.where('GET /tasks').length, greaterThan(1));
    });

    testWidgets('an empty title cannot be saved', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('task-edit-title')), '   ');
      await tester.pump();
      expect(saveEnabled(tester), isFalse);
      expect(find.text('The title is needed.'), findsOneWidget);
    });

    testWidgets('a new day makes the task all day', (tester) async {
      final api = await open(tester,
          due: DateTime(2026, 11, 4, 15),
          extra: {'PUT /tasks/t1/schedule': dueTask('t1', 'x')});
      // Take the time away first: the task becomes all day on its day.
      await tester.tap(find.byKey(const Key('task-edit-time-clear')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-edit-date')));
      await settle(tester);
      await tester.tap(find.text('12'));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await settle(tester);
      expect(_picker(tester, 'task-edit-date'), '2026-11-12');
      expect(_picker(tester, 'task-edit-time'), 'All day');
      await tester.tap(find.byKey(const Key('task-save')));
      await settle(tester);
      expect(api.where('PUT /tasks/t1/schedule').single.data,
          {'date': '2026-11-12'});
      expect(api.where('PATCH /tasks/t1'), isEmpty);
    });

    testWidgets('a time plans a block that starts then', (tester) async {
      final api = await open(tester,
          due: DateTime(2026, 11, 5),
          allDay: true,
          extra: {'PUT /tasks/t1/schedule': dueTask('t1', 'x')});
      expect(_picker(tester, 'task-edit-time'), 'All day');
      await tester.tap(find.byKey(const Key('task-edit-time')));
      await settle(tester);
      await tester.tap(find.text('OK')); // the picker starts at 09:00
      await settle(tester);
      expect(_picker(tester, 'task-edit-time'), '09:00');
      await tester.tap(find.byKey(const Key('task-save')));
      await settle(tester);
      expect(api.where('PUT /tasks/t1/schedule').single.data,
          {'start': DateTime(2026, 11, 5, 9).toUtc().toIso8601String()});
    });

    testWidgets('clearing the day removes the due date', (tester) async {
      final api = await open(tester,
          due: DateTime(2026, 11, 4, 15),
          extra: {'DELETE /tasks/t1/schedule': dueTask('t1', 'x')});
      await tester.tap(find.byKey(const Key('task-edit-date-clear')));
      await tester.pump();
      expect(_picker(tester, 'task-edit-date'), 'No date');
      expect(_picker(tester, 'task-edit-time'), '-');
      await tester.tap(find.byKey(const Key('task-save')));
      await settle(tester);
      expect(api.where('DELETE /tasks/t1/schedule'), hasLength(1));
    });

    testWidgets('a task without a date can be given one', (tester) async {
      final api = await open(tester,
          extra: {'PUT /tasks/t1/schedule': dueTask('t1', 'x')});
      expect(
          tester.widget<InkWell>(find.byKey(const Key('task-edit-time'))).onTap,
          isNull); // no time without a day
      await tester.tap(find.byKey(const Key('task-edit-date')));
      await settle(tester);
      await tester.tap(find.text('OK')); // today
      await settle(tester);
      expect(_picker(tester, 'task-edit-date'), isNot('No date'));
      await tester.tap(find.byKey(const Key('task-save')));
      await settle(tester);
      expect((api.where('PUT /tasks/t1/schedule').single.data! as Map).keys,
          ['date']);
    });

    testWidgets('a refusal stays on screen with the message', (tester) async {
      await open(tester, extra: {
        'PATCH /tasks/t1': const ApiFailure(
            409,
            'The item changed in Vikunja. Sync to see the new version.',
            'remote_conflict'),
      });
      await tester.enterText(
          find.byKey(const Key('task-edit-title')), 'Write the report');
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-save')));
      await settle(tester);
      expect(find.byKey(const Key('task-details')), findsOneWidget);
      expect(
          find.text(
              'The item changed in Vikunja. Sync to see the new version.'),
          findsOneWidget);
      expect(_field(tester, 'task-edit-title'), 'Write the report');
      expect(saveEnabled(tester), isTrue); // the user can try again
    });

    testWidgets('closing with changes asks first', (tester) async {
      await open(tester);
      await tester.enterText(
          find.byKey(const Key('task-edit-title')), 'Write the report');
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-details-close')));
      await settle(tester);
      expect(find.byKey(const Key('task-discard-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const Key('task-discard-keep')));
      await settle(tester);
      expect(find.byKey(const Key('task-details')), findsOneWidget);
      await tester.tap(find.byKey(const Key('task-details-close')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('task-discard-yes')));
      await settle(tester);
      expect(find.byKey(const Key('task-details')), findsNothing);
    });

    testWidgets('the server copy does not overwrite what the user typed',
        (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('task-edit-title')), 'Mine');
      await tester.pump();
      // A reload from the server (for example after Mark done).
      final scope = ProviderScope.containerOf(
          tester.element(find.byKey(const Key('task-details'))));
      scope.invalidate(taskDetailProvider('t1'));
      await settle(tester);
      expect(_field(tester, 'task-edit-title'), 'Mine');
    });
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
