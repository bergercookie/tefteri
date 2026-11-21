import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/core/auth_controller.dart';
import 'package:tefteri/core/find.dart';
import 'package:tefteri/core/app_selection.dart';
import 'package:tefteri/core/shortcuts/app_shortcuts.dart';
import 'package:tefteri/features/weekly/weekly_api.dart';
import 'package:tefteri/features/weekly/weekly_screen.dart';
import 'package:tefteri/theme/theme.dart';

import '../../support/fake_api.dart';
import 'weekly_fake.dart';

class _SignedIn extends AuthController {
  _SignedIn(super.ref) {
    state = const AuthState(signedIn: true);
  }
}

final _open = <ProviderContainer>{};

/// Takes the page down and ends the container, so that nothing is pending when
/// the test ends (a hint on the page sends what it saw after a short delay).
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  for (final c in _open.toList()) {
    c.dispose();
  }
  _open.clear();
}

Future<ProviderContainer> _pump(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({});
  final server = WeeklyServer(projects: [
    for (var i = 0; i < 30; i++)
      WeeklyServer.project('p$i', 'Project $i', tasks: 2),
  ]);
  final api = FakeApi({
    ...server.allRoutes(),
    'GET /views/week/$weekKey': periodJson('week', weekKey, '2030-03-11'),
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
  ]);
  final container = ProviderContainer(overrides: [
    dioProvider.overrideWithValue(dio),
    weeklyPollIntervalProvider.overrideWithValue(null),
    authControllerProvider.overrideWith(_SignedIn.new),
  ]);
  // The container belongs to this test. A tear-down would dispose it only
  // after the check for pending timers, so the test ends it itself.
  addTearDown(() => _open.remove(container));
  _open.add(container);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: router,
      theme: tefteriLight,
      builder: (_, child) => AppShortcuts(
        router: router,
        child: FindHost(child: AppSelection(child: child!)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

double _offset(WidgetTester tester) {
  final scrollables = tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .where((s) => s.position.axis == Axis.vertical)
      .toList();
  return [for (final s in scrollables) s.position.pixels]
      .fold(0.0, (a, b) => a + b);
}

void main() {
  for (final size in [const Size(1200, 700), const Size(500, 700)]) {
    testWidgets('weekly plan $size: Page Down scrolls', (tester) async {
      await _pump(tester, size);
      await tester.tap(find.byKey(const Key('check-projects')));
      await tester.pumpAndSettle();
      final before = _offset(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(_offset(tester), greaterThan(before));
      await _finish(tester);
    });

    testWidgets('weekly plan $size: Ctrl+F finds text', (tester) async {
      final c = await _pump(tester, size);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('find-bar')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('find-field')), 'Project 1');
      await tester.pumpAndSettle();
      expect(c.read(findProvider).matches, isNotEmpty);
      await _finish(tester);
    });

    testWidgets(
        'weekly plan $size: Page Down scrolls while the find bar has '
        'the focus', (tester) async {
      await _pump(tester, size);
      await tester.tap(find.byKey(const Key('check-projects')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('find-field')), 'Project');
      await tester.pumpAndSettle();
      final before = _offset(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(_offset(tester), greaterThan(before));
      await _finish(tester);
    });
  }
}
