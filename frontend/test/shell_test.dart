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
}

Future<void> _openDrawer(WidgetTester tester, bool admin) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith((ref) => _FakeAuth(ref, admin)),
    ],
    child: const MaterialApp(home: AppShell(title: 'T', body: SizedBox())),
  ));
  await tester.tap(find.byTooltip('Open navigation menu'));
  await tester.pumpAndSettle();
}

void adminMenuTests() {
  testWidgets('drawer shows Users only for admins', (tester) async {
    await _openDrawer(tester, true);
    expect(find.byKey(const Key('nav-/users')), findsOneWidget);
    expect(find.byKey(const Key('nav-/password')), findsOneWidget);
  });

  testWidgets('drawer hides Users for other users', (tester) async {
    await _openDrawer(tester, false);
    expect(find.byKey(const Key('nav-/users')), findsNothing);
    expect(find.byKey(const Key('nav-/password')), findsOneWidget);
  });
}
