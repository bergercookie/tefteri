import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_helpers.dart';

bool _selected(WidgetTester tester, String key) =>
    tester.widget<ChoiceChip>(find.byKey(Key(key))).selected;

void main() {
  testWidgets('six filter chips show counts and Today is active',
      (tester) async {
    await pumpPlanner(tester, plannerApi());
    for (final (key, label) in [
      ('today', 'Today (2)'),
      ('tomorrow', 'Tomorrow (0)'),
      ('week', 'This week (3)'),
      ('all', 'All (5)'),
      ('none', 'No due date (1)'),
      ('overdue', 'Overdue (1)'),
    ]) {
      expect(
          find.descendant(
              of: find.byKey(Key('filter-$key')), matching: find.text(label)),
          findsOneWidget,
          reason: key);
    }
    expect(_selected(tester, 'filter-today'), isTrue);
    expect(_selected(tester, 'filter-overdue'), isFalse);
  });

  testWidgets('clicking a filter lists exactly what the server returns for it',
      (tester) async {
    final api = plannerApi(tasksFor: (r) {
      return switch (r.query['due']) {
        'overdue' => [dueTask('o1', 'Late job', due: DateTime(2026, 11, 1, 9))],
        _ => [dueTask('t1', 'Write report')],
      };
    });
    await pumpPlanner(tester, api);
    expect(find.byKey(const Key('task-t1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('filter-overdue')));
    await settle(tester);
    expect(api.where('GET /tasks').last.query['due'], 'overdue');
    expect(find.byKey(const Key('task-o1')), findsOneWidget);
    expect(find.byKey(const Key('task-t1')), findsNothing);
    expect(_selected(tester, 'filter-overdue'), isTrue);
    expect(_selected(tester, 'filter-today'), isFalse);
    expect(find.text('Due 2026-11-01 09:00'), findsOneWidget);
  });

  testWidgets('tasks show whether they are scheduled', (tester) async {
    final api = plannerApi(
        tasksFor: (_) => [
              dueTask('a', 'Undated'),
              dueTask('b', 'Dated', due: DateTime(2026, 11, 4, 15)),
            ]);
    await pumpPlanner(tester, api);
    expect(find.byKey(const Key('unscheduled-a')), findsOneWidget);
    expect(find.byKey(const Key('scheduled-b')), findsOneWidget);
    expect(find.text('No due date'), findsOneWidget);
  });

  testWidgets('typing in the search bar searches all open tasks',
      (tester) async {
    final api = plannerApi(tasksFor: (r) {
      if (r.query['q'] == 'trip') return [dueTask('t2', 'Plan trip')];
      return [dueTask('t1', 'Write report')];
    });
    await pumpPlanner(tester, api);
    await tester.enterText(find.byKey(const Key('task-search')), 'trip');
    // the list updates after a short pause, not on every key
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        api.where('GET /tasks').where((r) => r.query['q'] == 'trip'), isEmpty);
    await tester.pump(const Duration(milliseconds: 150));
    await settle(tester);

    expect(api.where('GET /tasks').last.query['q'], 'trip');
    expect(find.byKey(const Key('task-t2')), findsOneWidget);
    expect(find.byKey(const Key('task-t1')), findsNothing);
    expect(find.byKey(const Key('search-note')), findsOneWidget);
    // while searching no filter chip is marked active
    expect(_selected(tester, 'filter-today'), isFalse);
  });

  testWidgets('a search without matches shows a message and a clear button',
      (tester) async {
    final api = plannerApi(
        tasksFor: (r) =>
            r.query['q'] == null ? [dueTask('t1', 'Write report')] : []);
    await pumpPlanner(tester, api);
    await tester.enterText(find.byKey(const Key('task-search')), 'zzz');
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(find.text('No tasks match "zzz".'), findsOneWidget);

    await tester.tap(find.byKey(const Key('task-search-clear-empty')));
    await settle(tester);
    expect(find.byKey(const Key('task-t1')), findsOneWidget);
    expect(find.byKey(const Key('search-note')), findsNothing);
  });

  testWidgets('clearing the search returns to the active filter',
      (tester) async {
    final api = plannerApi(
        tasksFor: (r) => r.query['q'] == null
            ? [dueTask('t1', 'Write report')]
            : [dueTask('t2', 'Plan trip')]);
    await pumpPlanner(tester, api);
    await tester.tap(find.byKey(const Key('filter-week')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('task-search')), 'trip');
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(find.byKey(const Key('task-t2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('task-search-clear')));
    await settle(tester);
    expect(find.byKey(const Key('task-t1')), findsOneWidget);
    expect(api.where('GET /tasks').last.query.containsKey('q'), isFalse);
    expect(api.where('GET /tasks').last.query['due'], 'week');
    expect(_selected(tester, 'filter-week'), isTrue);
  });

  testWidgets('clicking a filter clears the search text', (tester) async {
    await pumpPlanner(tester, plannerApi());
    await tester.enterText(find.byKey(const Key('task-search')), 'trip');
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    await tester.tap(find.byKey(const Key('filter-none')));
    await settle(tester);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('task-search')))
            .controller!
            .text,
        '');
    expect(_selected(tester, 'filter-none'), isTrue);
  });

  testWidgets('a task found by search can be dragged onto the calendar',
      (tester) async {
    final api = plannerApi(
      tasksFor: (r) => r.query['q'] == null ? [] : [dueTask('t2', 'Plan trip')],
      extra: {'PUT /tasks/t2/schedule': dueTask('t2', 'Plan trip')},
    );
    await pumpPlanner(tester, api);
    await tester.enterText(find.byKey(const Key('task-search')), 'trip');
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    await dragTo(tester, find.byKey(const Key('task-t2')),
        slotPoint(tester, wednesday, 11, 0));
    expect((api.where('PUT /tasks/t2/schedule').single.data! as Map)['start'],
        DateTime(2026, 11, 4, 11).toUtc().toIso8601String());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
