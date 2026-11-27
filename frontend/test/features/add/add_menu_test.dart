import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/core/auth_controller.dart';
import 'package:tefteri/core/shell.dart';
import 'package:tefteri/core/shortcuts/app_shortcuts.dart';
import 'package:tefteri/core/shortcuts/keymap.dart';

import '../../support/fake_api.dart';

class _Auth extends AuthController {
  _Auth(super.ref) {
    state = const AuthState(signedIn: true);
  }
}

late GoRouter _router;

Future<void> _pump(WidgetTester tester,
    {Size size = const Size(1000, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _router = GoRouter(initialLocation: '/', routes: [
    for (final path in ['/', '/week', '/projects', '/settings'])
      GoRoute(
        path: path,
        builder: (_, __) => AppShell(
          title: 'Page $path',
          body: const Column(children: [TextField(key: Key('field'))]),
        ),
      ),
  ]);
  final api = FakeApi({
    'GET /connections': [
      connectionJson('c1', 'tasks', 'Home tasks'),
      connectionJson('c2', 'calendar', 'Work calendar'),
    ],
    'GET /connections/c1/containers': [
      {'id': 'k1', 'remote_id': '1', 'name': 'Inbox', 'parent_remote_id': null},
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
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = api;
  final container = ProviderContainer(overrides: [
    dioProvider.overrideWithValue(dio),
    authControllerProvider.overrideWith((ref) => _Auth(ref)),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: _router,
      builder: (_, child) => AppShortcuts(router: _router, child: child!),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('add-button')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('add-menu')), findsOneWidget);
}

Future<void> _shiftN(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyN, character: 'N');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

Future<void> _key(
    WidgetTester tester, LogicalKeyboardKey key, String ch) async {
  await tester.sendKeyEvent(key, character: ch);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the button is on every screen and opens three choices',
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
      (tester) async {
    await _pump(tester);
    for (final path in ['/', '/week', '/projects', '/settings']) {
      _router.go(path);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-button')), findsOneWidget,
          reason: 'on $path');
    }
    await _openMenu(tester);
    expect(find.byKey(const Key('add-note')), findsOneWidget);
    expect(find.byKey(const Key('add-task')), findsOneWidget);
    expect(find.byKey(const Key('add-event')), findsOneWidget);
    // Each choice shows its key on a device with a keyboard.
    expect(find.text('D'), findsOneWidget);
    expect(find.text('N'), findsOneWidget);
    expect(find.text('Shift+N'), findsOneWidget);
  });

  testWidgets('each choice opens its own form and closes the menu',
      (tester) async {
    await _pump(tester);
    await _openMenu(tester);
    await tester.tap(find.byKey(const Key('add-note')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('daily-note-sheet')), findsOneWidget);
    expect(find.byKey(const Key('add-menu')), findsNothing);
    Navigator.of(tester.element(find.byKey(const Key('daily-note-sheet'))))
        .pop();
    await tester.pumpAndSettle();

    await _openMenu(tester);
    await tester.tap(find.byKey(const Key('add-task')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-task-dialog')), findsOneWidget);
    expect(find.byKey(const Key('add-menu')), findsNothing);
    Navigator.of(tester.element(find.byKey(const Key('new-task-dialog'))))
        .pop();
    await tester.pumpAndSettle();

    await _openMenu(tester);
    await tester.tap(find.byKey(const Key('add-event')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-event-dialog')), findsOneWidget);
  });

  testWidgets('the three paths have keys: D, N and Shift+N', (tester) async {
    await _pump(tester);
    await _key(tester, LogicalKeyboardKey.keyD, 'd');
    expect(find.byKey(const Key('daily-note-sheet')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('daily-note-sheet')), findsNothing);

    await _key(tester, LogicalKeyboardKey.keyN, 'n');
    expect(find.byKey(const Key('new-task-dialog')), findsOneWidget);
    _router.routerDelegate.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    await _shiftN(tester);
    expect(find.byKey(const Key('new-event-dialog')), findsOneWidget);
  });

  testWidgets('A opens the menu, and the keys work with the menu open',
      (tester) async {
    await _pump(tester);
    await _key(tester, LogicalKeyboardKey.keyA, 'a');
    expect(find.byKey(const Key('add-menu')), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.keyN, 'n');
    expect(find.byKey(const Key('new-task-dialog')), findsOneWidget);
    expect(find.byKey(const Key('add-menu')), findsNothing);
  });

  testWidgets('a key does not add while the user types in a field',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.keyD, 'd');
    await _key(tester, LogicalKeyboardKey.keyA, 'a');
    expect(find.byKey(const Key('add-menu')), findsNothing);
    expect(find.byKey(const Key('daily-note-sheet')), findsNothing);
  });

  testWidgets('the keymap lists the new keys for the help overlay',
      (tester) async {
    final keys = {for (final s in appShortcuts) s.keys: s.intent.runtimeType};
    expect(keys['A'], AddMenuIntent);
    expect(keys['D'], NewNoteIntent);
    expect(keys['N'], NewTaskIntent);
    expect(keys['Shift+N'], NewEventIntent);
  });

  testWidgets('a phone gets a round button, a wide screen gets the word Add',
      (tester) async {
    await _pump(tester, size: const Size(390, 800));
    expect(find.text('Add'), findsNothing);
    await _pump(tester);
    expect(find.text('Add'), findsOneWidget);
  });
}
