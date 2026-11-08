import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/app.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/core/auth_controller.dart';

import '../../support/fake_api.dart';
import 'planner_helpers.dart';

class _SignedIn extends AuthController {
  _SignedIn(super.ref) {
    state = const AuthState(signedIn: true);
  }
}

/// The real app (router, shell, planner), signed in, with a fake backend.
Future<ProviderContainer> _app(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = plannerApi(extra: {
    'GET /connections': [connectionJson('c1', 'tasks', 'Home tasks')],
    'GET /connections/c1/containers': [
      {'id': 'k1', 'remote_id': '1', 'name': 'Inbox', 'parent_remote_id': null},
    ],
    'GET /connections/c1/labels': ['Urgent'],
    'GET /sync/status': {'last_sync_at': null, 'results': <Object?>[]},
  });
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = api;
  final container = ProviderContainer(overrides: [
    dioProvider.overrideWithValue(dio),
    authControllerProvider.overrideWith(_SignedIn.new),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const TefteriApp(),
  ));
  await settle(tester);
  return container;
}

String _path(ProviderContainer c) =>
    c.read(routerProvider).routeInformationProvider.value.uri.path;

void main() {
  testWidgets('N opens the dialog, and no letter in it opens a view',
      (tester) async {
    final c = await _app(tester);
    expect(_path(c), '/');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN, character: 'n');
    await settle(tester);
    expect(find.byKey(const Key('new-task-dialog')), findsOneWidget);
    for (var stop = 0; stop < 9; stop++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      for (final (key, ch) in [
        (LogicalKeyboardKey.keyT, 't'),
        (LogicalKeyboardKey.keyG, 'g'),
        (LogicalKeyboardKey.keyW, 'w'),
        (LogicalKeyboardKey.keyR, 'r'),
        (LogicalKeyboardKey.keyN, 'n'),
      ]) {
        await tester.sendKeyEvent(key, character: ch);
        await tester.pump();
      }
      expect(_path(c), '/', reason: 'after Tab number ${stop + 1}');
    }
    expect(find.byKey(const Key('new-task-dialog')), findsOneWidget);
  });

  testWidgets('the button opens the dialog and letters in it are safe too',
      (tester) async {
    final c = await _app(tester);
    await tester.tap(find.byKey(const Key('new-task-button')));
    await settle(tester);
    for (var stop = 0; stop < 9; stop++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT, character: 't');
      await tester.pump();
      expect(_path(c), '/', reason: 'after Tab number ${stop + 1}');
    }
  });
}
