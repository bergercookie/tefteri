import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/planner/planner_visibility.dart';

import '../../support/fake_api.dart';
import 'planner_helpers.dart';

Map<String, Object?> _connection(String id, String kind, String name) => {
      'id': id,
      'kind': kind,
      'provider': kind == 'tasks' ? 'vikunja' : 'google_calendar',
      'display_name': name,
      'settings': <String, Object?>{},
      'status': 'ok',
      'last_sync_at': null,
      'last_sync_outcome': null,
    };

Map<String, Object?> _calendar(String id, String name,
        {bool enabled = true, String? color}) =>
    {
      'id': id,
      'remote_id': 'remote-$id',
      'name': name,
      'parent_remote_id': null,
      'color': color,
      'enabled': enabled,
      'read_only': false,
    };

FakeApi _api() => plannerApi(
      calendar: [
        calItem('entry', 'e1', 'Standup',
            start: DateTime(2026, 11, 4, 9), containerId: 'k1'),
        calItem('entry', 'e2', 'Dinner',
            start: DateTime(2026, 11, 4, 18), containerId: 'k2'),
        calItem('task', 't1', 'Write report',
            start: DateTime(2026, 11, 4, 12), connectionId: 'c1'),
        calItem('task', 't2', 'Plan trip',
            start: DateTime(2026, 11, 4, 14), connectionId: 'c2'),
      ],
      tasksFor: (_) => [
        dueTask('t1', 'Write report'),
        {...dueTask('t2', 'Plan trip'), 'connection_id': 'c2'},
      ],
      extra: {
        'GET /connections': [
          _connection('c1', 'tasks', 'Home tasks'),
          _connection('c2', 'tasks', 'Work tasks'),
          _connection('cal1', 'calendar', 'Google'),
        ],
        'GET /connections/cal1/containers': [
          _calendar('k1', 'Personal', color: '#ff0000'),
          _calendar('k2', 'Family'),
        ],
      },
    );

Future<void> _openViews(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('planner-views-button')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('hides one task provider and one calendar, then shows all',
      (tester) async {
    final api = _api();
    await pumpPlanner(tester, api);
    expect(find.byKey(const Key('task-t2')), findsOneWidget);
    expect(find.byKey(const Key('block-entry-e2')), findsOneWidget);

    await _openViews(tester);
    expect(find.byKey(const Key('planner-views-dialog')), findsOneWidget);
    expect(find.byKey(const Key('planner-task-source-c1')), findsOneWidget);
    expect(find.byKey(const Key('planner-task-source-c2')), findsOneWidget);
    expect(find.byKey(const Key('planner-calendar-source-k1')), findsOneWidget);
    expect(find.byKey(const Key('planner-calendar-source-k2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('planner-task-source-c2')));
    await tester.tap(find.byKey(const Key('planner-calendar-source-k2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('planner-views-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-t1')), findsOneWidget);
    expect(find.byKey(const Key('task-t2')), findsNothing);
    expect(find.byKey(const Key('block-entry-e1')), findsOneWidget);
    expect(find.byKey(const Key('block-entry-e2')), findsNothing);
    expect(find.byKey(const Key('block-task-t2')), findsNothing);
    expect(api.where('GET /tasks').last.query['exclude_connections'], ['c2']);
    expect(api.where('GET /tasks/counts').last.query['exclude_connections'],
        ['c2']);

    await _openViews(tester);
    await tester.tap(find.byKey(const Key('planner-views-show-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('planner-views-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-t2')), findsOneWidget);
    expect(find.byKey(const Key('block-entry-e2')), findsOneWidget);
  });

  testWidgets('one pane can be hidden but the last pane stays', (tester) async {
    await pumpPlanner(tester, _api());
    await _openViews(tester);

    await tester.tap(find.byKey(const Key('planner-show-calendar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('planner-views-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-pane')), findsOneWidget);
    expect(find.byKey(const Key('calendar-pane')), findsNothing);

    await _openViews(tester);
    final calendar = tester
        .widget<SwitchListTile>(find.byKey(const Key('planner-show-calendar')));
    // The calendar can be shown again on its own.
    expect(calendar.onChanged, isNotNull);
    final tasks = tester
        .widget<SwitchListTile>(find.byKey(const Key('planner-show-tasks')));
    expect(tasks.onChanged, isNull); // the tasks are the only pane left
  });

  testWidgets('keeps the choice on this device', (tester) async {
    SharedPreferences.setMockInitialValues({
      'planner_show_tasks': false,
      'planner_show_calendar': true,
      'planner_hidden_task_connections': ['c2'],
      'planner_hidden_calendars': ['k2'],
    });
    await pumpPlanner(tester, _api());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-pane')), findsNothing);
    expect(find.byKey(const Key('calendar-pane')), findsOneWidget);
    expect(find.byKey(const Key('block-entry-e1')), findsOneWidget);
    expect(find.byKey(const Key('block-entry-e2')), findsNothing);
  });

  testWidgets('the dialog fits a phone screen', (tester) async {
    await pumpPlanner(tester, _api(), size: const Size(360, 640));
    await _openViews(tester);
    expect(find.byKey(const Key('planner-views-dialog')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('a stored state with both panes off keeps the tasks visible', () async {
    SharedPreferences.setMockInitialValues({
      'planner_show_tasks': false,
      'planner_show_calendar': false,
    });
    final controller = PlannerVisibilityController();
    addTearDown(controller.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.state.showTasks, isTrue);
    expect(controller.state.showCalendar, isFalse);
  });
}
