import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tefteri/features/planner/planner_screen.dart';

import '../../support/fake_api.dart';
import 'planner_helpers.dart';

/// The route of the app: a link of a notification or of the widget names what to open.
GoRouter _router() => GoRouter(initialLocation: '/?date=2026-11-04', routes: [
      GoRoute(
        path: '/',
        builder: (_, s) => PlannerScreen(
          initialDate: DateTime.tryParse(s.uri.queryParameters['date'] ?? ''),
          openTaskId: s.uri.queryParameters['task'],
          openEventId: s.uri.queryParameters['event'],
          openAdd: s.uri.queryParameters['add'],
        ),
      ),
    ]);

FakeApi _api() => plannerApi(calendar: [
      calItem('entry', 'e1', 'Team standup',
          start: DateTime(2026, 11, 4, 9), end: DateTime(2026, 11, 4, 9, 30)),
    ], extra: {
      'GET /tasks/t9': {
        ...dueTask('t9', 'Call Sam', due: DateTime(2026, 11, 4, 15)),
        'sync_state': 'synced',
      },
      'GET /connections': [
        connectionJson('c1', 'tasks', 'Home tasks'),
        connectionJson('c2', 'calendar', 'Work calendar'),
      ],
      'GET /connections/c1/containers': [
        {
          'id': 'k1',
          'remote_id': '1',
          'name': 'Inbox',
          'parent_remote_id': null
        },
      ],
      'GET /connections/c1/labels': <Object?>[],
      'GET /connections/c2/containers': [
        {'id': 'k2', 'name': 'Work', 'enabled': true, 'read_only': false},
      ],
      'GET /me/settings': {
        'random_time_on_date_drop': false,
        'default_event_container_id': null,
      },
    });

Future<GoRouter> _pump(WidgetTester tester) async {
  final router = _router();
  await pumpWithApi(tester, _api(), const SizedBox(), router: router);
  return router;
}

Future<void> _go(WidgetTester tester, GoRouter router, String location) async {
  router.go(location);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a link with add=menu opens the Add menu', (tester) async {
    final router = await _pump(tester);
    await _go(tester, router, '/?date=2026-11-04&add=menu');
    expect(find.byKey(const Key('add-menu')), findsOneWidget);
  });

  testWidgets('add=note, add=task and add=event open that form',
      (tester) async {
    final router = await _pump(tester);
    await _go(tester, router, '/?date=2026-11-04&add=note');
    expect(find.byKey(const Key('daily-note-sheet')), findsOneWidget);
    router.routerDelegate.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await _go(tester, router, '/?date=2026-11-04&add=task');
    expect(find.byKey(const Key('new-task-dialog')), findsOneWidget);
    router.routerDelegate.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await _go(tester, router, '/?date=2026-11-04&add=event');
    expect(find.byKey(const Key('new-event-dialog')), findsOneWidget);
  });

  testWidgets('the same link works again after the first one was used',
      (tester) async {
    final router = await _pump(tester);
    const link = '/?date=2026-11-04&task=t9';
    await _go(tester, router, link);
    expect(find.byKey(const Key('task-details')), findsOneWidget);
    // The address no longer holds the task, so that the same link is a change again.
    expect(router.state.uri.queryParameters.containsKey('task'), isFalse);
    router.routerDelegate.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-details')), findsNothing);
    await _go(tester, router, link);
    expect(find.byKey(const Key('task-details')), findsOneWidget);
  });

  testWidgets('an event link opens the event, again and again', (tester) async {
    final router = await _pump(tester);
    const link = '/?date=2026-11-04&event=e1';
    for (var i = 0; i < 2; i++) {
      await _go(tester, router, link);
      expect(find.byKey(const Key('event-details')), findsOneWidget,
          reason: 'on tap ${i + 1}');
      router.routerDelegate.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
    }
  });
}
