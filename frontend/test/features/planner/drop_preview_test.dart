import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tefteri/features/planner/time_grid.dart';

import 'planner_helpers.dart';

/// Mouse-like platform: a drag starts at once (touch needs a long press).
final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

final _thursday = DateTime(2026, 11, 5);

String _time(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('drop-preview-time'))).data!;

double _veil(WidgetTester tester, DateTime day) => tester
    .widget<AnimatedOpacity>(find.byKey(Key(
        'drag-scrim-${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}')))
    .opacity;

/// Starts to drag the widget [from] and moves it to [to], without dropping.
Future<TestGesture> _hold(WidgetTester tester, Finder from, Offset to) async {
  final gesture = await tester.startGesture(tester.getCenter(from));
  await gesture.moveBy(const Offset(24, 0));
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump(const Duration(milliseconds: 300));
  return gesture;
}

void main() {
  testWidgets('nothing is highlighted when no task is dragged', (tester) async {
    await pumpPlanner(tester, plannerApi());
    expect(find.byKey(const Key('drop-preview')), findsNothing);
    expect(_veil(tester, wednesday), 0);
  }, variant: _linux);

  testWidgets('the slot under the pointer is shown with its start and end',
      (tester) async {
    await pumpPlanner(tester, plannerApi());
    final gesture = await _hold(tester, find.byKey(const Key('task-t1')),
        slotPoint(tester, wednesday, 9, 20));
    // The pointer is in the 09:15 slot; the block lasts one hour.
    expect(find.byKey(const Key('drop-preview')), findsOneWidget);
    expect(_time(tester), '09:15 - 10:15');
    expect(find.text('Write report'), findsWidgets);
    // The calendar fades back while the task is held.
    expect(_veil(tester, wednesday), 1);
    expect(_veil(tester, _thursday), 1);
    await gesture.up();
    await settle(tester);
  }, variant: _linux);

  testWidgets('the preview follows the pointer to another slot and day',
      (tester) async {
    await pumpPlanner(tester, plannerApi());
    final gesture = await _hold(tester, find.byKey(const Key('task-t1')),
        slotPoint(tester, wednesday, 9, 20));
    await gesture.moveTo(slotPoint(tester, wednesday, 9, 50));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_time(tester), '09:45 - 10:45');
    await gesture.moveTo(slotPoint(tester, _thursday, 16, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('drop-preview')), findsOneWidget); // one only
    expect(_time(tester), '16:00 - 17:00');
    final column =
        tester.getRect(find.byKey(const Key('day-column-2026-11-05')));
    final box = tester.getRect(find.byKey(const Key('drop-preview')));
    expect(box.left, greaterThanOrEqualTo(column.left));
    expect(box.right, lessThanOrEqualTo(column.right));
    expect(box.height, closeTo(56, 0.5)); // one hour
    await gesture.up();
    await settle(tester);
  }, variant: _linux);

  testWidgets('the all-day row says it will plan the day only', (tester) async {
    await pumpPlanner(tester, plannerApi());
    final cell = tester.getCenter(find.byKey(const Key('allday-2026-11-04')));
    final gesture = await _hold(tester, find.byKey(const Key('task-t1')), cell);
    expect(find.byKey(const Key('drop-preview-allday')), findsOneWidget);
    expect(find.byKey(const Key('drop-preview')), findsNothing);
    await gesture.up();
    await settle(tester);
  }, variant: _linux);

  testWidgets('a drop clears the preview and the veil', (tester) async {
    final api = plannerApi(
        extra: {'PUT /tasks/t1/schedule': dueTask('t1', 'Write report')});
    await pumpPlanner(tester, api);
    final gesture = await _hold(tester, find.byKey(const Key('task-t1')),
        slotPoint(tester, wednesday, 9, 20));
    await gesture.up();
    await settle(tester);
    expect(find.byKey(const Key('drop-preview')), findsNothing);
    expect(_veil(tester, wednesday), 0);
    expect(api.where('PUT /tasks/t1/schedule'), hasLength(1));
  }, variant: _linux);

  testWidgets('letting go outside the calendar clears the preview',
      (tester) async {
    final api = plannerApi();
    await pumpPlanner(tester, api);
    final gesture = await _hold(tester, find.byKey(const Key('task-t1')),
        slotPoint(tester, wednesday, 9, 20));
    expect(find.byKey(const Key('drop-preview')), findsOneWidget);
    await gesture.moveTo(const Offset(5, 5)); // the navigation
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('drop-preview')), findsNothing);
    await gesture.up();
    await settle(tester);
    expect(_veil(tester, wednesday), 0);
    expect(api.where('PUT /tasks/t1/schedule'), isEmpty);
  }, variant: _linux);

  testWidgets('a block that is moved shows its new place too', (tester) async {
    final api = plannerApi(calendar: [
      calItem('task', 't1', 'Write report',
          start: DateTime(2026, 11, 4, 14), end: DateTime(2026, 11, 4, 15)),
    ]);
    await pumpPlanner(tester, api);
    final gesture = await _hold(tester, find.byKey(const Key('block-task-t1')),
        slotPoint(tester, _thursday, 10, 5));
    expect(_time(tester), '10:00 - 11:00');
    await gesture.up();
    await settle(tester);
  }, variant: _linux);

  testWidgets('the preview follows the grid when it scrolls under the pointer',
      (tester) async {
    await pumpPlanner(tester, plannerApi());
    tester.view.physicalSize = const Size(1000, 600);
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
        of: find.byKey(const Key('time-grid')),
        matching: find.byType(Scrollable));
    final position = tester.state<ScrollableState>(scrollable).position;
    final grid = tester.getRect(find.byKey(const Key('time-grid')));
    final x =
        tester.getTopLeft(find.byKey(const Key('day-column-2026-11-04'))).dx +
            24;
    // The middle of the grid, away from the edges that scroll it.
    final point = Offset(x, grid.center.dy);
    final gesture =
        await _hold(tester, find.byKey(const Key('task-t1')), point);
    final before = _time(tester);
    position.jumpTo(position.pixels + hourHeight * 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The same screen point now shows a time two hours later, and so would a drop.
    final h = int.parse(before.substring(0, 2));
    expect(_time(tester).substring(0, 2), (h + 2).toString().padLeft(2, '0'));
    await gesture.up();
    await settle(tester);
  }, variant: _linux);

  testWidgets('holding a task near the bottom edge scrolls the grid',
      (tester) async {
    await pumpPlanner(tester, plannerApi());
    // A short window, so that the grid is taller than what shows.
    tester.view.physicalSize = const Size(1000, 600);
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
        of: find.byKey(const Key('time-grid')),
        matching: find.byType(Scrollable));
    double offset() =>
        tester.state<ScrollableState>(scrollable).position.pixels;
    final before = offset();
    final grid = tester.getRect(find.byKey(const Key('time-grid')));
    final x =
        tester.getTopLeft(find.byKey(const Key('day-column-2026-11-04'))).dx +
            24;
    final gesture = await tester
        .startGesture(tester.getCenter(find.byKey(const Key('task-t1'))));
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await gesture.moveTo(Offset(x + i, grid.bottom - 10));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(offset(), greaterThan(before));
    await gesture.up();
    await settle(tester);
  }, variant: _linux);
}
