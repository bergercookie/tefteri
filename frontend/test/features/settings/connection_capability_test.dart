import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/features/settings/connections_screen.dart';

import '../../support/fake_api.dart';

Future<FakeApi> _pump(WidgetTester tester, Map<String, Object?> routes) async {
  final api = FakeApi({
    'GET /connections': <Object?>[],
    'GET /sync/status': {'last_sync_at': null, 'results': []},
    ...routes,
  });
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = api;
  await tester.pumpWidget(ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio)],
    child: const MaterialApp(home: ConnectionsScreen()),
  ));
  await tester.pumpAndSettle();
  return api;
}

Future<void> _addVikunja(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('add-connection')));
  await tester.pumpAndSettle();
  await tester.enterText(
      find.byKey(const Key('new-connection-url')), 'https://tasks.test');
  await tester.enterText(
      find.byKey(const Key('new-connection-token')), 'secret');
  await tester.pump();
  await tester.tap(find.byKey(const Key('new-connection-save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a task app without nested projects is refused in plain words',
      (tester) async {
    await _pump(tester, {
      'POST /connections': const ApiFailure.contract(422, 'missing_capability',
          'This task app is missing a required capability: subprojects.'),
    });
    await _addVikunja(tester);
    expect(find.byKey(const Key('missing-capability')), findsOneWidget);
    expect(find.textContaining('Nested projects (projects inside projects'),
        findsOneWidget);
    // The machine name stays out of the user's way.
    expect(find.textContaining('subprojects'), findsNothing);
    expect(find.textContaining('Nothing was changed in your task app'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('missing-capability-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('missing-capability')), findsNothing);
  });

  testWidgets('several missing capabilities are all named', (tester) async {
    await _pump(tester, {
      'POST /connections': const ApiFailure.contract(422, 'missing_capability',
          'Missing required capabilities: stable_project_ids, completion_times.'),
    });
    await _addVikunja(tester);
    expect(find.byKey(const Key('missing-stable_project_ids')), findsOneWidget);
    expect(find.byKey(const Key('missing-completion_times')), findsOneWidget);
  });

  testWidgets('the check of a saved connection names the missing capability',
      (tester) async {
    await _pump(tester, {
      'POST /connections': <String, Object?>{
        'id': 'new1',
        'kind': 'tasks',
        'provider': 'vikunja',
        'display_name': 'Vikunja',
        'status': 'ok',
        'last_sync_at': null,
        'last_sync_outcome': null,
      },
      'POST /connections/new1/check': <String, Object?>{
        'status': 'ok',
        'capabilities': {
          'missing_required': ['project_tree'],
          'optional': {'rename': false, 'restore': true},
        },
      },
    });
    await _addVikunja(tester);
    expect(
        find.textContaining('Reading the whole project tree'), findsOneWidget);
  });

  testWidgets(
      'a task app that cannot move tasks is connected, and the user '
      'is told what is lost', (tester) async {
    await _pump(tester, {
      'POST /connections': {'id': 'c1'},
      'POST /connections/c1/check': {
        'status': 'ok',
        'capabilities': {
          'missing_required': <Object?>[],
          'optional': {'create_tasks': true, 'move_tasks': false},
        },
      },
    });
    await _addVikunja(tester);
    expect(find.byKey(const Key('missing-capability')), findsNothing);
    expect(find.byKey(const Key('connection-optional-note')), findsOneWidget);
    expect(find.textContaining('cannot move tasks between projects'),
        findsOneWidget);
    expect(find.textContaining('Close and return tasks'), findsOneWidget);
  });

  testWidgets('a task app that can move tasks gets no extra note',
      (tester) async {
    await _pump(tester, {
      'POST /connections': {'id': 'c1'},
      'POST /connections/c1/check': {
        'status': 'ok',
        'capabilities': {
          'missing_required': <Object?>[],
          'optional': {'move_tasks': true},
        },
      },
    });
    await _addVikunja(tester);
    expect(find.byKey(const Key('connection-optional-note')), findsNothing);
    expect(find.textContaining('cannot move tasks'), findsNothing);
  });
}
