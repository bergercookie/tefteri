import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/planner/planner_screen.dart';
import 'package:tefteri/features/planner/time_grid.dart';

import '../../support/fake_api.dart';
import 'planner_helpers.dart';

// Wednesday 4 November 2026, 10:30.
DateTime _now = DateTime(2026, 11, 4, 10, 30);

Future<void> _pump(WidgetTester tester, {DateTime? day}) => pumpWithApi(
    tester,
    plannerApi(),
    PlannerScreen(initialDate: day ?? wednesday, clock: () => _now));

void main() {
  setUp(() => _now = DateTime(2026, 11, 4, 10, 30));

  testWidgets('a red dot and line mark the current time in today\'s column',
      (tester) async {
    await _pump(tester);
    final line = find.byKey(const Key('now-indicator'));
    expect(line, findsOneWidget);
    final column = columnTopLeft(tester, wednesday);
    final rect = tester.getRect(line);
    // the middle of the dot sits at 10:30
    expect(
        rect.center.dy - column.dy, closeTo(minutesToOffset(10 * 60 + 30), 6));
    // the whole dot is inside the column and the line spans it
    final dayColumn =
        tester.getRect(find.byKey(const Key('day-column-2026-11-04')));
    expect(rect.right, closeTo(dayColumn.right, 1));
    // red: a dot and a line
    final boxes = tester
        .widgetList<Widget>(
            find.descendant(of: line, matching: find.byType(Container)))
        .cast<Container>();
    final dot = boxes.single.decoration! as BoxDecoration;
    expect(dot.shape, BoxShape.circle);
    expect(dot.color, const Color(0xFFD93025));
    final bar = tester.widget<ColoredBox>(
        find.descendant(of: line, matching: find.byType(ColoredBox)).first);
    expect(bar.color, const Color(0xFFD93025));
  });

  testWidgets('only today\'s column has the line', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('now-indicator')), findsOneWidget);
    final inside = find.descendant(
        of: find.byKey(const Key('day-column-2026-11-04')),
        matching: find.byKey(const Key('now-indicator')));
    expect(inside, findsOneWidget);
  });

  testWidgets('another week has no line', (tester) async {
    await _pump(tester, day: DateTime(2026, 11, 11));
    expect(find.byKey(const Key('now-indicator')), findsNothing);
  });

  testWidgets('the line moves when the minute changes', (tester) async {
    await _pump(tester);
    final before = tester.getCenter(find.byKey(const Key('now-indicator'))).dy;
    _now = DateTime(2026, 11, 4, 11, 30);
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    final after = tester.getCenter(find.byKey(const Key('now-indicator'))).dy;
    expect(after - before, closeTo(hourHeight, 1));
  });

  testWidgets('the calendar opens scrolled to the current time',
      (tester) async {
    _now = DateTime(2026, 11, 4, 15, 0);
    await _pump(tester);
    // without a scroll to now the 15:00 line would be far below the visible grid
    final grid = tester.getRect(find.byKey(const Key('time-grid')));
    final line = tester.getCenter(find.byKey(const Key('now-indicator')));
    expect(grid.contains(line), isTrue);
  });

  testWidgets('the line does not block a drop on its column', (tester) async {
    final api =
        plannerApi(extra: {'PUT /tasks/t1/schedule': dueTask('t1', 'x')});
    await pumpWithApi(
        tester, api, PlannerScreen(initialDate: wednesday, clock: () => _now));
    // drop right on the line
    await dragTo(
        tester,
        find.byKey(const Key('task-t1')),
        tester.getCenter(find.byKey(const Key('now-indicator'))) +
            const Offset(30, 0));
    expect(api.where('PUT /tasks/t1/schedule'), hasLength(1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
