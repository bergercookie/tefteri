import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/planning_models.dart';
import 'package:tefteri/features/planner/shared_events.dart';

import 'planner_helpers.dart';

CalendarItem _item(Map<String, Object?> json) => CalendarItem.fromJson(json);

void main() {
  final nine = DateTime(2026, 11, 4, 9);

  group('mergeSharedEvents', () {
    test('shows the copies of one event in two calendars once', () {
      final items = [
        _item(calItem('entry', 'a', 'Review',
            start: nine,
            containerId: 'k1',
            calendar: 'A1',
            color: '#d50000',
            uid: 'x@google.com',
            readOnly: true)),
        _item(calItem('entry', 'b', 'Review',
            start: nine,
            containerId: 'k2',
            calendar: 'B1',
            color: '#33b679',
            uid: 'x@google.com')),
        _item(calItem('entry', 'c', 'Other', start: nine, containerId: 'k1')),
      ];
      final merged = mergeSharedEvents(items);
      expect(merged.map((i) => i.id), ['b', 'c']);
      // The copy that the user can change is kept, so it can still be moved.
      final shared = merged.first;
      expect(shared.isShared, isTrue);
      expect(shared.calendarNames, ['B1', 'A1']);
      expect(shared.calendarColors, ['#33b679', '#d50000']);
      expect(calendarsLine(shared), 'Available in both calendars B1 and A1');
    });

    test('keeps events that differ in time, have no uid, or share a calendar',
        () {
      final items = [
        _item(calItem('entry', 'a', 'R',
            start: nine, containerId: 'k1', uid: 'x')),
        _item(calItem('entry', 'b', 'R',
            start: nine.add(const Duration(days: 7)),
            containerId: 'k2',
            uid: 'x')),
        _item(calItem('entry', 'c', 'R', start: nine, containerId: 'k2')),
        _item(calItem('entry', 'd', 'R', start: nine, containerId: 'k1')),
        _item(calItem('task', 'e', 'R', start: nine, uid: 'x')),
      ];
      expect(
          mergeSharedEvents(items).map((i) => i.id), ['a', 'b', 'c', 'd', 'e']);
    });
  });

  test('the tooltip names the title, the time and the calendar', () {
    final event = _item(calItem('entry', 'a', 'A very long meeting title',
        start: nine, calendar: 'Work'));
    expect(itemTooltip(event),
        'A very long meeting title\n2026-11-04, 09:00 - 10:00\nCalendar: Work');
    final task = _item(calItem('task', 't', 'Write report',
        start: nine, project: 'Home', status: 'done'));
    expect(itemTooltip(task),
        'Write report\nDue 2026-11-04 10:00\nProject: Home\nDone');
  });

  testWidgets('a shared event shows once, in the colors of both calendars',
      (tester) async {
    final api = plannerApi(calendar: [
      calItem('entry', 'a', 'Review',
          start: nine,
          containerId: 'k1',
          calendar: 'A1',
          color: '#d50000',
          uid: 'x'),
      calItem('entry', 'b', 'Review',
          start: nine,
          containerId: 'k2',
          calendar: 'B1',
          color: '#33b679',
          uid: 'x'),
    ]);
    await pumpPlanner(tester, api);
    expect(find.byKey(const Key('block-entry-a')), findsOneWidget);
    expect(find.byKey(const Key('block-entry-b')), findsNothing);
    expect(find.byKey(const Key('shared-a')), findsOneWidget);
    final box =
        tester.widget<Container>(find.byKey(const Key('block-entry-a')));
    expect((box.decoration! as BoxDecoration).gradient, isNotNull);
    final tooltip =
        tester.widget<Tooltip>(find.byKey(const Key('item-tooltip-entry-a')));
    expect(tooltip.message, contains('Available in both calendars A1 and B1'));

    // The details say it too.
    await tester.tap(find.byKey(const Key('block-entry-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-details-calendar')), findsOneWidget);
    expect(find.text('Available in both calendars A1 and B1'), findsOneWidget);
  });

  testWidgets('resting the mouse on a block shows its whole title',
      (tester) async {
    final api = plannerApi(calendar: [
      calItem('task', 't1', 'A task with a title far too long for its block',
          start: nine, status: 'open'),
    ]);
    await pumpPlanner(tester, api);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture
        .moveTo(tester.getCenter(find.byKey(const Key('block-task-t1'))));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(
        find.textContaining(
            'A task with a title far too long for its block\nDue'),
        findsOneWidget);
  });
}
