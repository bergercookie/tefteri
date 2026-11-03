import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:tefteri/app.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/core/auth_controller.dart';
import 'package:tefteri/core/shortcuts/keymap.dart';
import 'package:tefteri/features/daily/daily_screen.dart';
import 'package:tefteri/features/planner/planner_screen.dart';

import 'support/fake_api.dart';

class _SignedIn extends AuthController {
  _SignedIn(super.ref) {
    state = const AuthState(signedIn: true);
  }
}

Future<GoRouter> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = FakeApi({
    'GET /calendar': <Object?>[],
    'GET /tasks': <Object?>[],
    'GET /tasks/counts': <String, int>{},
    'GET /views/day/2026-11-04': {
      'date': '2026-11-04',
      'entries': <Object?>[],
      'tasks': <Object?>[],
      'note': null,
    },
  });
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = api;
  final container = ProviderContainer(overrides: [
    dioProvider.overrideWithValue(dio),
    authControllerProvider.overrideWith(_SignedIn.new),
  ]);
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  test('the planner is the first view (p) and the day view moves to t', () {
    expect(appViews.first.path, '/');
    expect(appViews.first.label, 'Planner');
    expect(appViews.first.key, 'p');
    final day = appViews.firstWhere((v) => v.label == 'Today');
    expect((day.path, day.key), ('/daily', 't'));
    expect(appViews.where((v) => v.path == '/calendar'), isEmpty);
  });

  testWidgets('the default route is the planner', (tester) async {
    await _pump(tester);
    expect(find.byType(PlannerScreen), findsOneWidget);
    expect(find.byType(DailyScreen), findsNothing);
  });

  testWidgets('the day view is still reachable at /daily', (tester) async {
    final router = await _pump(tester);
    router.go('/daily');
    await tester.pumpAndSettle();
    expect(find.byType(DailyScreen), findsOneWidget);
  });

  testWidgets('the old /calendar address opens the planner', (tester) async {
    final router = await _pump(tester);
    router.go('/daily');
    await tester.pumpAndSettle();
    router.go('/calendar');
    await tester.pumpAndSettle();
    expect(find.byType(PlannerScreen), findsOneWidget);
  });
}
