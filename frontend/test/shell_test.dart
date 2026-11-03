import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/auth_controller.dart';
import 'package:tefteri/core/context_filter.dart';
import 'package:tefteri/core/shell.dart';

void main() {
  testWidgets('context switch updates the global filter', (tester) async {
    final container = ProviderContainer();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AppShell(title: 'T', body: SizedBox())),
    ));
    await tester.tap(find.text('work'));
    await tester.pump();
    expect(container.read(contextFilterProvider), ContextFilter.work);
    expect(find.byKey(const Key('sync-button')), findsOneWidget);
  });
  adminMenuTests();
}

class _FakeAuth extends AuthController {
  _FakeAuth(super.ref, bool admin) {
    state = AuthState(signedIn: true, isAdmin: admin);
  }

  @override
  Future<void> logout() async => state = const AuthState();
}

Future<ProviderContainer> _openDrawer(WidgetTester tester, bool admin) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    authControllerProvider.overrideWith((ref) => _FakeAuth(ref, admin)),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: AppShell(title: 'T', body: SizedBox())),
  ));
  await tester.tap(find.byTooltip('Open navigation menu'));
  await tester.pumpAndSettle();
  return container;
}

void adminMenuTests() {
  testWidgets('drawer lists the planner first and every other view',
      (tester) async {
    await _openDrawer(tester, false);
    expect(find.byKey(const Key('nav-/')), findsOneWidget);
    for (final path in [
      '/daily',
      '/week',
      '/month',
      '/year',
      '/goals',
      '/review',
      '/notes',
    ]) {
      expect(find.byKey(Key('nav-$path')), findsOneWidget, reason: path);
    }
    expect(find.byKey(const Key('nav-/calendar')), findsNothing);
  });

  testWidgets('drawer shows Admin settings only for administrators',
      (tester) async {
    await _openDrawer(tester, true);
    expect(find.byKey(const Key('nav-/admin')), findsOneWidget);
    expect(find.text('Admin settings'), findsOneWidget);
    expect(find.byKey(const Key('nav-/settings')), findsOneWidget);
  });

  testWidgets('drawer hides Admin settings from other users', (tester) async {
    await _openDrawer(tester, false);
    expect(find.byKey(const Key('nav-/admin')), findsNothing);
    expect(find.byKey(const Key('nav-/settings')), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('Connections, Change password and Users are not in the drawer',
      (tester) async {
    await _openDrawer(tester, true);
    for (final path in [
      '/users',
      '/password',
      '/admin/users',
      '/settings/password',
      '/settings/connections',
    ]) {
      expect(find.byKey(Key('nav-$path')), findsNothing, reason: path);
    }
    expect(find.text('Connections'), findsNothing);
    expect(find.text('Change password'), findsNothing);
    expect(find.text('Users'), findsNothing);
  });

  testWidgets('a page below Settings has a back button', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
          home: AppShell(title: 'T', body: SizedBox(), backTo: '/settings')),
    ));
    expect(find.byKey(const Key('back-button')), findsOneWidget);
    expect(find.byTooltip('Open navigation menu'), findsOneWidget);
  });
}
