import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/core/auth_controller.dart';
import 'package:tefteri/core/shortcuts/app_shortcuts.dart';
import 'package:tefteri/core/shortcuts/keymap.dart';

import '../support/fake_api.dart';

class _Auth extends AuthController {
  _Auth(super.ref, {required bool signedIn}) {
    state = AuthState(signedIn: signedIn);
  }
}

late GoRouter _router;

Future<void> _pump(WidgetTester tester, {bool signedIn = true}) async {
  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const Scaffold(
          body: Column(children: [Text('page'), TextField(key: Key('field'))])),
    ),
    GoRoute(
        path: '/daily',
        builder: (_, __) => const Scaffold(body: Text('daily'))),
    GoRoute(
        path: '/goals',
        builder: (_, __) => const Scaffold(body: Text('goals'))),
  ]);
  _router = router;
  final api = FakeApi({
    'GET /connections': [connectionJson('c1', 'tasks', 'Home tasks')],
    'GET /connections/c1/containers': [
      {'id': 'k1', 'remote_id': '1', 'name': 'Inbox', 'parent_remote_id': null},
    ],
    'GET /connections/c1/labels': <Object?>[],
  });
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = api;
  final container = ProviderContainer(overrides: [
    dioProvider.overrideWithValue(dio),
    authControllerProvider
        .overrideWith((ref) => _Auth(ref, signedIn: signedIn)),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppShortcuts(router: router, child: child!),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _n(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.keyN, character: 'n');
  await tester.pumpAndSettle();
}

void main() {
  test('N is in the keymap, so the help overlay lists it', () {
    final n = appShortcuts.firstWhere((s) => s.keys == 'N');
    expect(n.description, 'Create a new task');
    expect(n.intent, isA<NewTaskIntent>());
    // No other shortcut uses the key.
    expect(appShortcuts.where((s) => s.keys == 'N'), hasLength(1));
    expect(appViews.where((v) => v.key == 'n'), isEmpty);
  });

  testWidgets('N opens the new task dialog', (tester) async {
    await _pump(tester);
    await _n(tester);
    expect(find.byKey(const Key('new-task-dialog')), findsOneWidget);
  });

  testWidgets('N typed in a text field is a letter, not a shortcut',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    await _n(tester);
    expect(find.byKey(const Key('new-task-dialog')), findsNothing);
  });

  testWidgets('N does not open a second dialog on top of the first',
      (tester) async {
    await _pump(tester);
    await _n(tester);
    await tester.tap(find.byKey(const Key('new-task-title')));
    await tester.pump();
    await _n(tester); // a letter for the title field, not a shortcut
    expect(find.byKey(const Key('new-task-dialog')), findsOneWidget);
  });

  testWidgets('letters typed in the dialog never run a shortcut',
      (tester) async {
    await _pump(tester);
    await _n(tester);
    // Tab from the title field to the controls that are not text fields (the
    // project is one; the day and the buttons are not) and type letters on
    // every stop: none of them may open a view behind the dialog.
    for (var stop = 0; stop < 8; stop++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      for (final (key, c) in [
        (LogicalKeyboardKey.keyT, 't'),
        (LogicalKeyboardKey.keyG, 'g'),
        (LogicalKeyboardKey.keyN, 'n'),
        (LogicalKeyboardKey.keyS, 's'),
      ]) {
        await tester.sendKeyEvent(key, character: c);
        await tester.pump();
      }
      expect(_router.routeInformationProvider.value.uri.path, '/',
          reason: 'after Tab number ${stop + 1}');
    }
    expect(find.byKey(const Key('new-task-dialog')), findsOneWidget);
  });

  testWidgets('N does nothing while signed out', (tester) async {
    await _pump(tester, signedIn: false);
    await _n(tester);
    expect(find.byKey(const Key('new-task-dialog')), findsNothing);
  });

  testWidgets('the help overlay shows N', (tester) async {
    await _pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shortcut-N')), findsOneWidget);
    expect(find.text('Create a new task'), findsOneWidget);
  });
}
