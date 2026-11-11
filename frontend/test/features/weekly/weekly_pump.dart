import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/features/weekly/weekly_api.dart';
import 'package:tefteri/features/weekly/weekly_screen.dart';
import 'package:tefteri/theme/theme.dart';

import '../../support/fake_api.dart';
import 'weekly_fake.dart';

/// Pumps the weekly planning page for the week of [weekKey] with [server] and
/// the routes in [extra]. A router stands in for the rest of the app, so that
/// "Label a project as theme" can open the Projects page.
Future<FakeApi> pumpWeekly(
  WidgetTester tester,
  WeeklyServer server, {
  Map<String, Object?> extra = const {},
  Size size = const Size(1000, 2400),
  Brightness brightness = Brightness.light,
  Duration? poll,
}) async {
  SharedPreferences.setMockInitialValues({});
  final api = FakeApi({
    ...server.allRoutes(),
    'GET /views/week/$weekKey': periodJson('week', weekKey, '2030-03-11'),
    ...extra,
  });
  tester.view.physicalSize = size;
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
      weeklyPollIntervalProvider.overrideWithValue(poll),
    ],
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

/// Opens the step with the checklist key `check-[step]`.
Future<void> openStep(WidgetTester tester, String step) async {
  await tester.tap(find.byKey(Key('check-$step')));
  await tester.pumpAndSettle();
}

/// The vertical position of the widget with [key].
double topOf(WidgetTester tester, String key) =>
    tester.getTopLeft(find.byKey(Key(key))).dy;

/// Taps the widget with [key], scrolling it into view first, and lets the
/// calls it starts (and the reads that follow them) finish.
Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pumpAndSettle();
  // A change refreshes the picker after the first settle.
  await tester.pump(const Duration(milliseconds: 10));
  await tester.pumpAndSettle();
}

/// The text with [key] that reads [data] (the checklist repeats some counts).
Finder textKey(String key, String data) => find
    .byWidgetPredicate((w) => w is Text && w.key == Key(key) && w.data == data);
