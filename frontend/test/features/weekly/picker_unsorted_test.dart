import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/features/weekly/weekly_api.dart';
import 'package:tefteri/features/weekly/weekly_screen.dart';

import '../../support/fake_api.dart';
import '../projects/projects_fake.dart';
import 'weekly_fake.dart';

/// The picker inside a router, so that "Label a project as theme" can open
/// the Projects screen.
Future<FakeApi> _pump(
  WidgetTester tester,
  WeeklyServer weekly,
  Map<String, Object?> extra,
) async {
  final api = FakeApi({
    ...weekly.allRoutes(),
    'GET /views/week/$weekKey': periodJson('week', weekKey, '2030-03-11'),
    ...extra,
  });
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = api
    ..transformer = SyncTransformer();
  final router = GoRouter(routes: [
    GoRoute(
        path: '/',
        builder: (_, __) =>
            WeeklyPlanningScreen(initialDate: DateTime(2030, 3, 6))),
    GoRoute(path: '/projects', builder: (_, __) => const Text('projects page')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(dio),
      weeklyPollIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return api;
}

Map<String, Object?> _classification(int unsorted) => {
      'connections': [
        {
          'connection_id': 'c1',
          'name': 'Vikunja',
          'capabilities': {'rename': true, 'restore': true},
          'projects': [classifiedJson('p1', 'Website')],
        },
      ],
      'unsorted_count': unsorted,
    };

void main() {
  testWidgets('unsorted projects give a quiet reminder that does not block',
      (tester) async {
    await _pump(tester, WeeklyServer(),
        {'GET /projects/classification': _classification(3)});
    expect(find.byKey(const Key('unsorted-reminder')), findsOneWidget);
    expect(find.text('3 projects have no label yet.'), findsOneWidget);
    // Not a card, not a dialog: the picker works as before.
    expect(find.byKey(const Key('unsorted-card')), findsNothing);
    await tapKey(tester, 'add-p1');
    expect(find.byKey(const Key('chosen-mark-p1')), findsOneWidget);
  });

  testWidgets('no reminder when every project is labelled', (tester) async {
    await _pump(tester, WeeklyServer(),
        {'GET /projects/classification': _classification(0)});
    expect(find.byKey(const Key('unsorted-reminder')), findsNothing);
  });

  testWidgets('the reminder opens the Projects screen', (tester) async {
    await _pump(tester, WeeklyServer(),
        {'GET /projects/classification': _classification(1)});
    await tapKey(tester, 'unsorted-open');
    expect(find.text('projects page'), findsOneWidget);
  });

  testWidgets('an empty picker offers to label or create a theme',
      (tester) async {
    await _pump(tester, WeeklyServer(projects: []),
        {'GET /projects/classification': _classification(0)});
    expect(find.byKey(const Key('no-projects')), findsOneWidget);
    expect(find.text('Label a project as theme'), findsOneWidget);
    expect(find.text('Create a theme'), findsOneWidget);
    await tapKey(tester, 'label-a-theme');
    expect(find.text('projects page'), findsOneWidget);
  });

  testWidgets('Create a theme works inside the picker', (tester) async {
    final api = await _pump(tester, WeeklyServer(projects: []), {
      'GET /projects/classification': _classification(0),
      'POST /projects': <String, Object?>{'id': 'new1'},
    });
    await tapKey(tester, 'create-a-theme');
    await tester.enterText(
        find.byKey(const Key('create-theme-name')), 'Health');
    await tester.pump();
    await tapKey(tester, 'create-theme-save');
    final body = api.where('POST /projects').single.data as Map;
    expect(body['name'], 'Health');
    expect(body['label'], 'theme');
    expect(find.byKey(const Key('create-theme-dialog')), findsNothing);
  });

  testWidgets('a refused theme shows the reason and creates nothing',
      (tester) async {
    await _pump(tester, WeeklyServer(projects: []), {
      'GET /projects/classification': _classification(0),
      'POST /projects': const ApiFailure.contract(502, 'task_app_refused',
          'Your task app refused to create the project. Nothing was created.'),
    });
    await tapKey(tester, 'create-a-theme');
    await tester.enterText(
        find.byKey(const Key('create-theme-name')), 'Health');
    await tester.pump();
    await tapKey(tester, 'create-theme-save');
    expect(find.byKey(const Key('create-theme-error')), findsOneWidget);
    expect(find.textContaining('Nothing was created'), findsOneWidget);
  });
}
