import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/features/statistics/drilldown_screen.dart';
import 'package:tefteri/theme/theme.dart';

import '../../support/fake_api.dart';

/// The routes of the fake server for one week summary and its task lists.
Map<String, Object?> weekRoutes({
  Map<String, Object?>? summary,
  List<Map<String, Object?>> tasks = const [],
}) =>
    {
      'GET /statistics': summary ?? statisticsJson(),
      'GET /statistics/tasks': fakeStatisticsTasks(tasks),
    };

/// Pumps [home] inside a router that also knows the drill-down screen, the
/// Projects page and the planning page, so that taps can go somewhere.
Future<FakeApi> pumpStats(
  WidgetTester tester,
  Map<String, Object?> routes,
  Widget home, {
  Size size = const Size(1000, 2400),
  Brightness brightness = Brightness.light,
  Map<String, Object> prefs = const {},
  bool scroll = true,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final api = FakeApi(routes);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = api
    ..transformer = SyncTransformer();
  Widget page() =>
      Scaffold(body: scroll ? SingleChildScrollView(child: home) : home);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => page()),
    GoRoute(path: '/week', builder: (_, __) => page()),
    GoRoute(path: '/month', builder: (_, __) => page()),
    GoRoute(path: '/year', builder: (_, __) => page()),
    statisticsRoute(),
    GoRoute(path: '/projects', builder: (_, __) => const Text('projects page')),
    GoRoute(path: '/week/plan', builder: (_, __) => const Text('plan page')),
    GoRoute(
        path: '/settings/connections',
        builder: (_, __) => const Text('connections page')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio)],
    child: MaterialApp.router(
      routerConfig: router,
      theme: tefteriLight,
      darkTheme: tefteriDark,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

/// A term hint that the user already closed, so it stays out of the way.
const hintsClosed = <String, Object>{
  'term_hint_closed_category-terms': true,
  'term_hint_closed_category-unsorted': true,
  'term_hint_closed_category-hidden': true,
};
