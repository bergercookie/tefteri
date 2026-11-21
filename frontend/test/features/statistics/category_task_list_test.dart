import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/statistics/category_task_list.dart';
import 'package:tefteri/features/statistics/statistics_models.dart';
import 'package:tefteri/features/statistics/statistics_providers.dart';

import '../../support/fake_api.dart';
import 'stats_pump.dart';

List<Map<String, Object?>> _many(int n, {String category = 'off_plan'}) => [
      for (var i = 0; i < n; i++)
        statTaskJson('t$i', 'Task $i',
            category: category, project: 'Project ${i % 3}'),
    ];

TaskListQuery _query({String order = 'newest', Category? category}) =>
    TaskListQuery(
        period: 'week',
        day: '2026-11-02',
        category: category ?? Category.offPlan,
        order: order);

void main() {
  testWidgets('"Show more" loads the next page and repeats nothing',
      (tester) async {
    final api = await pumpStats(
      tester,
      weekRoutes(tasks: _many(120)),
      CategoryTaskList(query: _query()),
      prefs: hintsClosed,
    );
    expect(find.byKey(const Key('task-row-t0')), findsOneWidget);
    expect(find.byKey(const Key('task-row-t49')), findsOneWidget);
    expect(find.byKey(const Key('task-row-t50')), findsNothing);
    expect(find.text('Showing 50 of 120'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('show-more')));
    await tester.tap(find.byKey(const Key('show-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-row-t99')), findsOneWidget);
    expect(find.text('Showing 100 of 120'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('show-more')));
    await tester.tap(find.byKey(const Key('show-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-row-t119')), findsOneWidget);
    expect(find.byKey(const Key('show-more')), findsNothing);
    expect(find.text('All 120 shown'), findsOneWidget);
    final cursors = [
      for (final r in api.where('GET /statistics/tasks')) r.query['cursor'],
    ];
    expect(cursors, [null, '50', '100']);
  });

  testWidgets('a scroll loads the next page; all 250 are reached once',
      (tester) async {
    final api = await pumpStats(
      tester,
      weekRoutes(tasks: _many(250)),
      SizedBox(
          height: 700,
          child: CategoryTaskList(query: _query(), scrollable: true)),
      prefs: hintsClosed,
      scroll: false,
    );
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 80; i++) {
      await tester.drag(list, const Offset(0, -1500));
      await tester.pumpAndSettle();
      if (api.where('GET /statistics/tasks').length >= 5) break;
    }
    final container = ProviderScope.containerOf(
        tester.element(find.byType(CategoryTaskList)));
    final state = container.read(taskListProvider(_query()));
    expect(state.items, hasLength(250));
    expect({for (final t in state.items) t.id}, hasLength(250));
    expect(state.nextCursor, isNull);
    final cursors = [
      for (final r in api.where('GET /statistics/tasks')) r.query['cursor'],
    ];
    expect(cursors, [null, '50', '100', '150', '200']);
    expect(cursors.toSet(), hasLength(cursors.length));
  });

  testWidgets('tasks are grouped by project, with the unsorted note',
      (tester) async {
    final tasks = [
      statTaskJson('a1', 'Fix the gutter', project: 'Alpha'),
      statTaskJson('a2', 'Paint the door', project: 'Alpha'),
      statTaskJson('b1', 'Sort the shelf', project: 'Beta', unsorted: true),
      statTaskJson('n1', 'Call back', project: null, unsorted: true),
    ];
    await pumpStats(
      tester,
      weekRoutes(tasks: tasks),
      CategoryTaskList(query: _query(order: 'project')),
      prefs: hintsClosed,
    );
    expect(find.byKey(const Key('group-Alpha')), findsOneWidget);
    expect(find.byKey(const Key('group-Beta')), findsOneWidget);
    expect(find.byKey(const Key('group-No project')), findsOneWidget);
    expect(find.text('Fix the gutter'), findsOneWidget);
    expect(find.byKey(const Key('unsorted-note-b1')), findsOneWidget);
    expect(find.byKey(const Key('unsorted-note-n1')), findsOneWidget);
    expect(find.byKey(const Key('unsorted-note-a1')), findsNothing);
    expect(find.text('Unsorted'), findsNWidgets(2));
  });

  testWidgets('the newest order shows the project on each row', (tester) async {
    await pumpStats(
      tester,
      weekRoutes(tasks: [
        statTaskJson('a1', 'Fix the gutter', project: 'Alpha'),
        statTaskJson('b1', 'Sort the shelf', project: 'Beta'),
      ]),
      CategoryTaskList(query: _query()),
      prefs: hintsClosed,
    );
    expect(find.byKey(const Key('group-Alpha')), findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const Key('task-row-a1')),
            matching: find.text('Alpha')),
        findsOneWidget);
  });

  testWidgets('a project that left the task app says so', (tester) async {
    await pumpStats(
      tester,
      weekRoutes(tasks: [
        statTaskJson('a1', 'Fix the gutter', project: 'Old', orphaned: true),
      ]),
      CategoryTaskList(query: _query()),
      prefs: hintsClosed,
    );
    expect(find.textContaining('no longer in your task app'), findsOneWidget);
  });

  testWidgets('an empty list says so', (tester) async {
    await pumpStats(
        tester, weekRoutes(tasks: const []), CategoryTaskList(query: _query()),
        prefs: hintsClosed);
    expect(find.text('No tasks here.'), findsOneWidget);
  });

  testWidgets('a failed page keeps the tasks and offers to try again',
      (tester) async {
    var calls = 0;
    final good = fakeStatisticsTasks(_many(120));
    await pumpStats(
      tester,
      {
        'GET /statistics': statisticsJson(offPlan: 120),
        'GET /statistics/tasks': (options) {
          calls++;
          if (calls == 2) {
            return const ApiFailure(502, 'The server is busy.', 'unavailable');
          }
          return good(options);
        },
      },
      CategoryTaskList(query: _query()),
      prefs: hintsClosed,
    );
    await tester.ensureVisible(find.byKey(const Key('show-more')));
    await tester.tap(find.byKey(const Key('show-more')));
    await tester.pumpAndSettle();
    // The 50 tasks that were loaded stay, and the message says what to do.
    expect(find.byKey(const Key('task-row-t49')), findsOneWidget);
    expect(find.textContaining('The server is busy.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('list-retry')));
    await tester.tap(find.byKey(const Key('list-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-row-t99')), findsOneWidget);
    expect(find.textContaining('The server is busy.'), findsNothing);
  });
}
