import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'planner_helpers.dart';

void main() {
  testWidgets('shows the task pane on the left and the calendar on the right',
      (tester) async {
    final api = plannerApi(calendar: [
      calItem('entry', 'e1', 'Standup',
          start: DateTime(2026, 11, 3, 10), end: DateTime(2026, 11, 3, 10, 30)),
    ]);
    await pumpPlanner(tester, api);

    final tasks = tester.getRect(find.byKey(const Key('task-pane')));
    final calendar = tester.getRect(find.byKey(const Key('calendar-pane')));
    expect(tasks.right, lessThanOrEqualTo(calendar.left));
    expect(find.byKey(const Key('task-t1')), findsOneWidget);
    expect(find.byKey(const Key('block-entry-e1')), findsOneWidget);
    // the default filter is Today (FR-018)
    expect(api.where('GET /tasks').first.query['due'], 'today');
  });

  testWidgets('sync reloads both columns', (tester) async {
    final api = plannerApi(extra: {'POST /sync': <Object?>[]});
    await pumpPlanner(tester, api);
    final tasksBefore = api.where('GET /tasks').length;
    final calendarBefore = api.where('GET /calendar').length;
    await tester.tap(find.byKey(const Key('sync-button')));
    await tester.pumpAndSettle();
    expect(api.where('POST /sync'), hasLength(1));
    expect(api.where('GET /tasks').length, greaterThan(tasksBefore));
    expect(api.where('GET /calendar').length, greaterThan(calendarBefore));
  });

  testWidgets('next week loads the next week of the calendar', (tester) async {
    final api = plannerApi();
    await pumpPlanner(tester, api);
    await tester.tap(find.byKey(const Key('next-week')));
    await tester.pumpAndSettle();
    expect(api.where('GET /calendar').last.query['from'],
        DateTime(2026, 11, 9).toUtc().toIso8601String());
  });

  testWidgets('a calendar load error shows a retry button', (tester) async {
    final api = FakeApi({
      'GET /calendar': const ApiFailure(502, 'Google cannot be reached.', 'x'),
      'GET /tasks': [dueTask('t1', 'Write report')],
      'GET /tasks/counts': {'today': 1},
    });
    await pumpPlanner(tester, api);
    expect(find.text('Google cannot be reached.'), findsOneWidget);
    expect(find.byKey(const Key('reload-button')), findsOneWidget);
    expect(
        find.byKey(const Key('task-t1')), findsOneWidget); // tasks still work
  });

  group('arrow keys', () {
    String from(FakeApi api) =>
        api.where('GET /calendar').last.query['from'] as String;

    testWidgets(
        'the right arrow shows the next week, the left arrow the previous',
        (tester) async {
      final api = plannerApi();
      await pumpPlanner(tester, api);
      expect(find.text('Week of 2026-11-02'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester);
      expect(find.text('Week of 2026-11-09'), findsOneWidget);
      expect(from(api), DateTime(2026, 11, 9).toUtc().toIso8601String());

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await settle(tester);
      expect(find.text('Week of 2026-10-26'), findsOneWidget);
      expect(from(api), DateTime(2026, 10, 26).toUtc().toIso8601String());
    });

    testWidgets('the arrows still work after a click on a filter',
        (tester) async {
      final api = plannerApi();
      await pumpPlanner(tester, api);
      await tester.tap(find.byKey(const Key('filter-week')));
      await settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester);
      expect(find.text('Week of 2026-11-09'), findsOneWidget);
    });

    testWidgets('in the search box the arrows move the cursor, not the week',
        (tester) async {
      await pumpPlanner(tester, plannerApi());
      await tester.tap(find.byKey(const Key('task-search')));
      await tester.enterText(find.byKey(const Key('task-search')), 'trip');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      expect(find.text('Week of 2026-11-02'), findsOneWidget);
    });

    testWidgets('the arrow buttons say which key does the same',
        (tester) async {
      await pumpPlanner(tester, plannerApi());
      expect(find.byTooltip('Previous week (Left arrow)'), findsOneWidget);
      expect(find.byTooltip('Next week (Right arrow)'), findsOneWidget);
    });
  });
}
