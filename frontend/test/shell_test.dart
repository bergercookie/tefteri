import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/auth_controller.dart';
import 'package:tefteri/core/shell.dart';
import 'package:tefteri/core/versions.dart';

void main() {
  testWidgets('the header shows the sync button', (tester) async {
    final container = ProviderContainer();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AppShell(title: 'T', body: SizedBox())),
    ));
    expect(find.byKey(const Key('sync-button')), findsOneWidget);
    expect(find.text('work'), findsNothing);
  });
  adminMenuTests();
  railTests();
  versionTests();
}

class _FakeAuth extends AuthController {
  _FakeAuth(super.ref, bool admin) {
    state = AuthState(signedIn: true, isAdmin: admin);
  }

  @override
  Future<void> logout() async => state = const AuthState();
}

Future<ProviderContainer> _openDrawer(WidgetTester tester, bool admin) async {
  tester.view.physicalSize = const Size(800, 2400);
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
    tester.view.physicalSize = const Size(800, 2400);
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

Future<void> _pumpWide(WidgetTester tester, double width,
    {bool admin = false}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith((ref) => _FakeAuth(ref, admin)),
    ],
    child: const MaterialApp(home: AppShell(title: 'T', body: SizedBox())),
  ));
}

void railTests() {
  testWidgets('a wide window has a permanent rail and no menu button',
      (tester) async {
    await _pumpWide(tester, railMinWidth);
    expect(find.byTooltip('Open navigation menu'), findsNothing);
    expect(find.byKey(const Key('nav-/')), findsOneWidget);
    expect(find.byKey(const Key('nav-/settings')), findsOneWidget);
    expect(find.byKey(const Key('sign-out')), findsOneWidget);
    expect(find.byKey(const Key('nav-/admin')), findsNothing);
  });

  testWidgets('the rail shows labels and keys in a very wide window',
      (tester) async {
    await _pumpWide(tester, railExtendedMinWidth, admin: true);
    expect(find.text('Tefteri'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('W'), findsOneWidget); // the shortcut key
    expect(find.byKey(const Key('nav-/admin')), findsOneWidget);
  });

  testWidgets('the icons of the labelled rail are indented from its edge',
      (tester) async {
    await _pumpWide(tester, railExtendedMinWidth, admin: true);
    double iconLeft(String key) => tester
        .getTopLeft(find.descendant(
            of: find.byKey(Key(key)), matching: find.byType(Icon)))
        .dx;
    // Clear of the edge, and the same for every entry, the sign-out one too.
    expect(iconLeft('nav-/week'), greaterThanOrEqualTo(24));
    expect(iconLeft('nav-/admin'), iconLeft('nav-/week'));
    expect(iconLeft('sign-out'), iconLeft('nav-/week'));
  });

  testWidgets('the compact rail has the mark but not the name', (tester) async {
    await _pumpWide(tester, railMinWidth);
    expect(find.text('Tefteri'), findsNothing);
    expect(find.text('Week'), findsOneWidget);
  });

  testWidgets('a narrow window keeps the drawer', (tester) async {
    await _pumpWide(tester, railMinWidth - 1);
    expect(find.byTooltip('Open navigation menu'), findsOneWidget);
    expect(find.byKey(const Key('nav-/')), findsNothing);
  });
}

void versionTests() {
  Future<void> pump(WidgetTester tester, double width,
      {bool known = true}) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => _FakeAuth(ref, false)),
        appVersionProvider.overrideWith((_) async {
          if (!known) throw StateError('unknown');
          return const AppVersion('0.1.0', 14);
        }),
      ],
      child: const MaterialApp(home: AppShell(title: 'T', body: SizedBox())),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the labelled rail shows the version of the app under Sign out',
      (tester) async {
    await pump(tester, railExtendedMinWidth);
    final label = find.byKey(const Key('nav-app-version'));
    expect(label, findsOneWidget);
    expect(tester.widget<Text>(label).data, 'Version 0.1.0 (build 14)');
    // It sits below the Sign out button.
    expect(
        tester.getTopLeft(label).dy,
        greaterThan(
            tester.getBottomLeft(find.byKey(const Key('sign-out'))).dy));
  });

  testWidgets('the drawer shows the version too', (tester) async {
    await pump(tester, 800);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav-app-version')), findsOneWidget);
  });

  testWidgets('no version label while the version is unknown', (tester) async {
    await pump(tester, railExtendedMinWidth, known: false);
    expect(find.byKey(const Key('nav-app-version')), findsNothing);
    expect(find.byKey(const Key('sign-out')), findsOneWidget);
  });

  test('a Flutter version splits into its name and build number', () {
    final v = parseAppVersion('0.1.0+14');
    expect((v.name, v.build), ('0.1.0', 14));
    expect(parseAppVersion('1.2.3').build, 0);
    expect(parseAppVersion('1.2.3+x').build, 0);
  });
}
