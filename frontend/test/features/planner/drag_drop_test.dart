import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'planner_helpers.dart';

Map<String, Object?> _put(String id) => dueTask(id, 'x');

/// Mouse-like platform: a drag starts at once (touch needs a long press).
final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

void main() {
  testWidgets('dropping a task on a slot schedules a block that starts there',
      (tester) async {
    final api = plannerApi(extra: {'PUT /tasks/t1/schedule': _put('t1')});
    await pumpPlanner(tester, api);
    // inside the 14:30 slot
    final target = slotPoint(tester, wednesday, 14, 37);
    await dragTo(tester, find.byKey(const Key('task-t1')), target);

    final put = api.where('PUT /tasks/t1/schedule').single;
    expect(put.data, {
      'start': DateTime(2026, 11, 4, 14, 30).toUtc().toIso8601String(),
    });
    // lists reload after the save
    expect(api.where('GET /calendar').length, greaterThan(1));
    expect(api.where('POST /calendar/entries'), isEmpty); // never an event
  }, variant: _linux);

  testWidgets('dragging a block to another slot moves it', (tester) async {
    final api = plannerApi(
      calendar: [
        calItem('task', 't1', 'Write report',
            start: DateTime(2026, 11, 4, 14), end: DateTime(2026, 11, 4, 15)),
      ],
      extra: {'PUT /tasks/t1/schedule': _put('t1')},
    );
    await pumpPlanner(tester, api);
    final target = slotPoint(tester, DateTime(2026, 11, 5), 10, 5);
    await dragTo(tester, find.byKey(const Key('block-task-t1')), target);
    expect((api.where('PUT /tasks/t1/schedule').single.data! as Map)['start'],
        DateTime(2026, 11, 5, 10).toUtc().toIso8601String());
  }, variant: _linux);

  testWidgets('dragging a block back to the task column unschedules it',
      (tester) async {
    final api = plannerApi(
      calendar: [
        calItem('task', 't1', 'Write report',
            start: DateTime(2026, 11, 4, 14), end: DateTime(2026, 11, 4, 15)),
      ],
      extra: {'DELETE /tasks/t1/schedule': _put('t1')},
    );
    await pumpPlanner(tester, api);
    final pane = tester.getCenter(find.byKey(const Key('task-pane'))) +
        const Offset(0, 120);
    await dragTo(tester, find.byKey(const Key('block-task-t1')), pane);
    expect(api.where('DELETE /tasks/t1/schedule'), hasLength(1));
  }, variant: _linux);

  testWidgets('dropping on the all-day row plans the date only',
      (tester) async {
    final api = plannerApi(extra: {'PUT /tasks/t2/schedule': _put('t2')});
    await pumpPlanner(tester, api);
    await dragTo(tester, find.byKey(const Key('task-t2')),
        tester.getCenter(find.byKey(const Key('allday-2026-11-06'))));
    expect(api.where('PUT /tasks/t2/schedule').single.data,
        {'date': '2026-11-06'});
  }, variant: _linux);

  testWidgets('a failed save shows the server message and changes nothing',
      (tester) async {
    final api = plannerApi(extra: {
      'PUT /tasks/t1/schedule': const ApiFailure(
          502,
          'Vikunja cannot be reached. Nothing was changed.',
          'backend_unavailable'),
    });
    await pumpPlanner(tester, api);
    await dragTo(tester, find.byKey(const Key('task-t1')),
        slotPoint(tester, wednesday, 9, 0));
    expect(find.text('Vikunja cannot be reached. Nothing was changed.'),
        findsOneWidget);
    // no block appears: the calendar still answers an empty list
    expect(find.byKey(const Key('block-task-t1')), findsNothing);
    // the lists were reloaded from the server
    expect(api.where('GET /calendar').length, greaterThan(1));
    // the user can close the banner
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    expect(find.text('Vikunja cannot be reached. Nothing was changed.'),
        findsNothing);
  }, variant: _linux);

  testWidgets('touch screens need a long press to start a drag',
      (tester) async {
    final api = plannerApi(extra: {'PUT /tasks/t1/schedule': _put('t1')});
    await pumpPlanner(tester, api);
    final from = tester.getCenter(find.byKey(const Key('task-t1')));
    final target = slotPoint(tester, wednesday, 9, 0);

    // a quick swipe does not drag
    final swipe = await tester.startGesture(from);
    await swipe.moveTo(target);
    await swipe.up();
    await settle(tester);
    expect(api.where('PUT /tasks/t1/schedule'), isEmpty);

    // press and hold, then drag
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await settle(tester);
    expect(api.where('PUT /tasks/t1/schedule'), hasLength(1));
  });
}
