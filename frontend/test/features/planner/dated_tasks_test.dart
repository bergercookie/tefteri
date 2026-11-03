import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/planner/time_grid.dart';

import 'planner_helpers.dart';

void main() {
  testWidgets('a timed task is a block that ends at its due time',
      (tester) async {
    // due 15:00 -> the block covers 14:00-15:00
    final api = plannerApi(calendar: [
      calItem('task', 't1', 'Write report',
          start: DateTime(2026, 11, 4, 14), end: DateTime(2026, 11, 4, 15)),
    ]);
    await pumpPlanner(tester, api);
    final block = find.byKey(const Key('block-task-t1'));
    final column = columnTopLeft(tester, wednesday);
    final rect = tester.getRect(block);
    expect(rect.top - column.dy, closeTo(minutesToOffset(14 * 60), 2));
    expect(rect.height, closeTo(hourHeight, 3));
  });

  testWidgets('a date-only task shows in the all-day row', (tester) async {
    final api = plannerApi(calendar: [
      calItem('task', 't9', 'Pay rent',
          start: DateTime(2026, 11, 5),
          end: DateTime(2026, 11, 6),
          allDay: true),
    ]);
    await pumpPlanner(tester, api);
    expect(find.byKey(const Key('allday-task-t9')), findsOneWidget);
    expect(find.byKey(const Key('block-task-t9')), findsNothing);
    // it sits in Thursday's all-day cell
    final cell = tester.getRect(find.byKey(const Key('allday-2026-11-05')));
    expect(
        cell.contains(
            tester.getCenter(find.byKey(const Key('allday-task-t9')))),
        isTrue);
  });

  testWidgets('a done task is struck through', (tester) async {
    final api = plannerApi(calendar: [
      calItem('task', 't1', 'Done thing',
          start: DateTime(2026, 11, 4, 9), status: 'done'),
    ]);
    await pumpPlanner(tester, api);
    final text = tester.widget<Text>(find.descendant(
        of: find.byKey(const Key('block-task-t1')),
        matching: find.text('Done thing')));
    expect(text.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('a block cut at midnight is marked as continued', (tester) async {
    final api = plannerApi(calendar: [
      calItem('task', 't1', 'Early',
          start: DateTime(2026, 11, 4),
          end: DateTime(2026, 11, 4, 0, 30),
          clipped: true),
    ]);
    await pumpPlanner(tester, api);
    expect(find.byKey(const Key('clipped-t1')), findsOneWidget);
  });

  testWidgets('task blocks and events look different', (tester) async {
    final api = plannerApi(calendar: [
      calItem('entry', 'e1', 'Standup', start: DateTime(2026, 11, 4, 9)),
      calItem('task', 't1', 'Focus', start: DateTime(2026, 11, 4, 12)),
    ]);
    await pumpPlanner(tester, api);
    Color tint(String key) =>
        (tester.widget<Container>(find.byKey(Key(key))).decoration!
                as BoxDecoration)
            .color!;
    Color accent(String key) =>
        tester.widget<Container>(find.byKey(Key(key))).color!;
    expect(tint('block-entry-e1'), isNot(tint('block-task-t1')));
    // a strong colored edge on the left of every block
    expect(
        accent('block-accent-entry-e1'), isNot(accent('block-accent-task-t1')));
  });

  testWidgets('overlapping items sit side by side', (tester) async {
    final api = plannerApi(calendar: [
      calItem('entry', 'e1', 'Standup',
          start: DateTime(2026, 11, 4, 9), end: DateTime(2026, 11, 4, 9, 30)),
      calItem('task', 't1', 'Focus',
          start: DateTime(2026, 11, 4, 9, 15),
          end: DateTime(2026, 11, 4, 10, 15)),
    ]);
    await pumpPlanner(tester, api);
    final a = tester.getRect(find.byKey(const Key('block-entry-e1')));
    final b = tester.getRect(find.byKey(const Key('block-task-t1')));
    expect(a.overlaps(b), isFalse);
    expect(a.width, closeTo(b.width, 1));
    final column =
        tester.getRect(find.byKey(const Key('day-column-2026-11-04')));
    expect(a.width, lessThan(column.width * 0.6));
  });
}
