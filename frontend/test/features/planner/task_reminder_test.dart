import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'planner_helpers.dart';

/// A task at 14:00 to 15:00 on Wednesday (due 15:00), or without a day.
Map<String, Object?> _task({bool timed = true}) => {
      ...dueTask('t1', 'Call Sam',
          due: timed ? DateTime(2026, 11, 4, 15) : null),
      'description': null,
    };

/// An API with a task whose reminder lives in [state] (null: none).
FakeApi _api({
  required List<int?> state,
  bool timed = true,
  bool supported = true,
  int defaultMinutes = 15,
}) =>
    plannerApi(
      tasksFor: (_) => [_task(timed: timed)],
      extra: {
        'GET /tasks/t1': _task(timed: timed),
        'GET /me/settings': {
          'random_time_on_date_drop': false,
          'default_reminder_minutes': defaultMinutes,
        },
        'GET /tasks/t1/reminder': (_) =>
            {'supported': supported, 'minutes_before': state.first},
        'PUT /tasks/t1/reminder': (o) {
          final asked = (o.data as Map)['minutes_before'] as int?;
          state[0] = asked ?? defaultMinutes;
          return {'supported': true, 'minutes_before': state.first};
        },
        'DELETE /tasks/t1/reminder': (_) {
          state[0] = null;
          return {'supported': true, 'minutes_before': null};
        },
      },
    );

Future<void> _open(WidgetTester tester, FakeApi api) async {
  await pumpPlanner(tester, api);
  await tester.tap(find.byKey(const Key('task-t1')));
  await settle(tester);
}

bool _enabled(WidgetTester tester) => tester
    .widget<ButtonStyleButton>(find.byKey(const Key('task-reminder-add')))
    .enabled;

void main() {
  testWidgets('the add button names the default offset and adds the reminder',
      (tester) async {
    final state = <int?>[null];
    final api = _api(state: state);
    await _open(tester, api);

    expect(find.text('Remind me 15 minutes before'), findsOneWidget);
    expect(_enabled(tester), isTrue);
    await tester.tap(find.byKey(const Key('task-reminder-add')));
    await settle(tester);

    // No offset is sent: the server uses the default of the user's settings.
    expect(
        api.where('PUT /tasks/t1/reminder').single.data, <String, Object?>{});
    expect(state, [15]);
    expect(find.byKey(const Key('task-reminder-add')), findsNothing);
    expect(
        find.text('Reminder 15 minutes before the due time'), findsOneWidget);
  });

  testWidgets('the button follows the default of the settings', (tester) async {
    await _open(tester, _api(state: [null], defaultMinutes: 90));
    expect(find.text('Remind me 90 minutes before'), findsOneWidget);
  });

  testWidgets('a reminder at the due time is described as such',
      (tester) async {
    await _open(tester, _api(state: [0]));
    expect(find.text('Reminder at the due time'), findsOneWidget);
  });

  testWidgets('an existing reminder can be removed', (tester) async {
    final state = <int?>[30];
    final api = _api(state: state);
    await _open(tester, api);
    expect(
        find.text('Reminder 30 minutes before the due time'), findsOneWidget);

    await tester.tap(find.byKey(const Key('task-reminder-remove')));
    await settle(tester);
    expect(api.where('DELETE /tasks/t1/reminder'), hasLength(1));
    expect(state, [null]);
    expect(find.byKey(const Key('task-reminder-add')), findsOneWidget);
  });

  testWidgets('a task without a time cannot get a reminder', (tester) async {
    final api = _api(state: [null], timed: false);
    await _open(tester, api);
    expect(_enabled(tester), isFalse);
    expect(find.byKey(const Key('task-reminder-hint')), findsOneWidget);
    expect(api.where('PUT /tasks/t1/reminder'), isEmpty);
  });

  testWidgets('a time that is not saved yet blocks the button', (tester) async {
    await _open(tester, _api(state: [null]));
    expect(_enabled(tester), isTrue);
    await tester.tap(find.byKey(const Key('task-edit-time-clear')));
    await tester.pump();
    expect(_enabled(tester), isFalse);
    expect(find.byKey(const Key('task-reminder-hint')), findsOneWidget);
  });

  testWidgets('nothing shows when the task app has no reminders',
      (tester) async {
    await _open(tester, _api(state: [null], supported: false));
    expect(find.byKey(const Key('task-reminder-add')), findsNothing);
    expect(find.byKey(const Key('task-reminder-remove')), findsNothing);
    expect(find.byKey(const Key('task-details')), findsOneWidget);
  });

  testWidgets('a failed add shows the message and no reminder', (tester) async {
    final state = <int?>[null];
    final api = plannerApi(
      tasksFor: (_) => [_task()],
      extra: {
        'GET /tasks/t1': _task(),
        'GET /tasks/t1/reminder': {'supported': true, 'minutes_before': null},
        'PUT /tasks/t1/reminder':
            const ApiFailure(502, 'Vikunja cannot be reached.', 'down'),
      },
    );
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('task-reminder-add')));
    await settle(tester);
    expect(find.text('Vikunja cannot be reached.'), findsOneWidget);
    expect(find.byKey(const Key('task-reminder-add')), findsOneWidget);
    expect(state, [null]);
  });
}
