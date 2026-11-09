import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/control_key.dart';

import '../../support/fake_api.dart';
import 'planner_helpers.dart';

Map<String, Object?> _done(String id) =>
    {...dueTask(id, 'x'), 'status': 'done'};

/// A right click on [target]; with [ctrl], while the Ctrl key is down.
Future<void> _rightClick(WidgetTester tester, Finder target,
    {bool ctrl = false}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.tap(target, buttons: kSecondaryButton);
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await settle(tester);
}

void main() {
  FakeApi api0({Map<String, Object?> extra = const {}}) => plannerApi(
        calendar: [
          calItem('task', 't1', 'Prepare the demo',
              start: DateTime(2026, 11, 4, 14), status: 'open'),
          calItem('task', 'c5', 'Pay the invoice',
              start: DateTime(2026, 11, 5),
              end: DateTime(2026, 11, 6),
              allDay: true,
              status: 'open'),
          calItem('task', 'd1', 'Already done',
              start: DateTime(2026, 11, 3, 10), status: 'done'),
          calItem('entry', 'e1', 'Team standup',
              start: DateTime(2026, 11, 3, 9),
              end: DateTime(2026, 11, 3, 9, 30)),
        ],
        extra: {
          'POST /tasks/t1/complete': _done('t1'),
          'POST /tasks/c5/complete': _done('c5'),
          'POST /tasks/d1/complete': _done('d1'),
          'GET /tasks/t1': dueTask('t1', 'Prepare the demo'),
          ...extra,
        },
      );

  testWidgets('Ctrl and a right click complete a task block', (tester) async {
    final api = api0();
    await pumpPlanner(tester, api);
    await _rightClick(tester, find.byKey(const Key('block-task-t1')),
        ctrl: true);
    expect(api.where('POST /tasks/t1/complete'), hasLength(1));
    // The calendar reloads, and no pop-up opened.
    expect(api.where('GET /calendar').length, greaterThan(1));
    expect(find.byKey(const Key('task-details')), findsNothing);
  });

  testWidgets('Ctrl and a right click complete an all-day task',
      (tester) async {
    final api = api0();
    await pumpPlanner(tester, api);
    await _rightClick(tester, find.byKey(const Key('allday-task-c5')),
        ctrl: true);
    expect(api.where('POST /tasks/c5/complete'), hasLength(1));
  });

  testWidgets('a right click without Ctrl does nothing', (tester) async {
    final api = api0();
    await pumpPlanner(tester, api);
    await _rightClick(tester, find.byKey(const Key('block-task-t1')));
    expect(api.where('POST /tasks/t1/complete'), isEmpty);
    expect(find.byKey(const Key('task-details')), findsNothing);
  });

  Future<void> ctrlClick(WidgetTester tester, Finder target) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(target);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 80));
  }

  testWidgets('Ctrl and a double click complete a task block', (tester) async {
    final api = api0();
    await pumpPlanner(tester, api);
    final block = find.byKey(const Key('block-task-t1'));
    await ctrlClick(tester, block);
    // One Ctrl click does not complete, and it opens no pop-up that would
    // cover the second click.
    expect(api.where('POST /tasks/t1/complete'), isEmpty);
    expect(find.byKey(const Key('task-details')), findsNothing);
    await ctrlClick(tester, block);
    await settle(tester);
    expect(api.where('POST /tasks/t1/complete'), hasLength(1));
    expect(find.byKey(const Key('task-details')), findsNothing);
  });

  testWidgets('two Ctrl clicks on different tasks complete none',
      (tester) async {
    final api = api0();
    await pumpPlanner(tester, api);
    await ctrlClick(tester, find.byKey(const Key('block-task-t1')));
    await ctrlClick(tester, find.byKey(const Key('allday-task-c5')));
    await settle(tester);
    expect(api.requests.where((r) => r.path.endsWith('/complete')), isEmpty);
  });

  testWidgets('Ctrl clicks that are far apart in time complete nothing',
      (tester) async {
    final api = api0();
    await pumpPlanner(tester, api);
    var clock = DateTime(2026, 11, 9, 10);
    ControlKey.now = () => clock;
    addTearDown(() => ControlKey.now = DateTime.now);
    final block = find.byKey(const Key('block-task-t1'));
    await ctrlClick(tester, block);
    clock = clock.add(const Duration(seconds: 2));
    await ctrlClick(tester, block);
    await settle(tester);
    expect(api.where('POST /tasks/t1/complete'), isEmpty);
  });

  testWidgets('a double click without Ctrl completes nothing', (tester) async {
    final api = api0();
    await pumpPlanner(tester, api);
    await tester.tap(find.byKey(const Key('block-task-t1')));
    await tester.pump(const Duration(milliseconds: 80));
    await settle(tester);
    expect(api.where('POST /tasks/t1/complete'), isEmpty);
    // A plain click opens the details, as before.
    expect(find.byKey(const Key('task-details')), findsOneWidget);
  });

  testWidgets('Ctrl and a double click complete a task of the list',
      (tester) async {
    final api = plannerApi(extra: {
      'POST /tasks/t1/complete': _done('t1'),
    });
    await pumpPlanner(tester, api);
    final row = find.byKey(const Key('task-t1'));
    await ctrlClick(tester, row);
    expect(api.where('POST /tasks/t1/complete'), isEmpty);
    await ctrlClick(tester, row);
    await settle(tester);
    expect(api.where('POST /tasks/t1/complete'), hasLength(1));
    expect(find.byKey(const Key('task-details')), findsNothing);
  });

  testWidgets('a task that is done is not touched again', (tester) async {
    final api = api0();
    await pumpPlanner(tester, api);
    await _rightClick(tester, find.byKey(const Key('block-task-d1')),
        ctrl: true);
    expect(api.where('POST /tasks/d1/complete'), isEmpty);
  });

  testWidgets('an event has nothing to complete', (tester) async {
    final api = api0();
    await pumpPlanner(tester, api);
    await _rightClick(tester, find.byKey(const Key('block-entry-e1')),
        ctrl: true);
    expect(api.requests.where((r) => r.path.endsWith('/complete')), isEmpty);
    expect(find.byKey(const Key('event-details')), findsNothing);
  });

  testWidgets('a refusal from the task app is shown', (tester) async {
    final api = api0(extra: {
      'POST /tasks/t1/complete': const ApiFailure(
          502,
          'Home tasks cannot be reached. Nothing was changed.',
          'backend_unavailable'),
    });
    await pumpPlanner(tester, api);
    await _rightClick(tester, find.byKey(const Key('block-task-t1')),
        ctrl: true);
    expect(find.text('Home tasks cannot be reached. Nothing was changed.'),
        findsOneWidget);
  });
}
