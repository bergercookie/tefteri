import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/app.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/core/auth_controller.dart';

/// Answers `GET /auth/me` with [meStatus]; everything else with an empty
/// list, so the screens behind the login can load.
class _Server implements HttpClientAdapter {
  _Server(this.meStatus);

  final int meStatus;
  final List<RequestOptions> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    const json = {
      Headers.contentTypeHeader: ['application/json'],
    };
    if (options.path == '/auth/me') {
      return ResponseBody.fromString(
          jsonEncode({'username': 'admin', 'is_admin': true}), meStatus,
          headers: json);
    }
    return ResponseBody.fromString('[]', 200, headers: json);
  }
}

/// A container whose API client talks to [server], like `main()` builds it.
ProviderContainer _container(_Server server) {
  // The real provider, so the default headers are the app's own.
  final probe = ProviderContainer();
  final dio = probe.read(dioProvider)..httpClientAdapter = server;
  final container =
      ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
  addTearDown(container.dispose);
  addTearDown(probe.dispose);
  return container;
}

/// Lets the session check finish on the test clock. Fixed pumps, not
/// pumpAndSettle: the spinner and the screens animate without end.
Future<void> _finish(WidgetTester tester, Future<void> restored) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await restored;
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  test('a valid session from an earlier visit signs the user in', () async {
    final container = _container(_Server(200));
    await container.read(authControllerProvider.notifier).restore();
    final state = container.read(authControllerProvider);
    expect(state.signedIn, isTrue);
    expect(state.isAdmin, isTrue);
    expect(state.restoring, isFalse);
  });

  test('no session leaves the user signed out', () async {
    final container = _container(_Server(401));
    await container.read(authControllerProvider.notifier).restore();
    final state = container.read(authControllerProvider);
    expect(state.signedIn, isFalse);
    expect(state.restoring, isFalse);
  });

  test('every request names the client, as the cookie CSRF guard needs',
      () async {
    final server = _Server(200);
    await _container(server).read(authControllerProvider.notifier).restore();
    expect(server.requests.single.headers['X-Tefteri-Client'], 'tefteri');
  });

  testWidgets('a reload with a valid session skips the login screen',
      (tester) async {
    final container = _container(_Server(200));
    final restored = container.read(authControllerProvider.notifier).restore();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const TefteriApp()));
    expect(find.byKey(const Key('restoring-session')), findsOneWidget);
    await _finish(tester, restored);
    expect(find.byKey(const Key('restoring-session')), findsNothing);
    expect(find.byKey(const Key('login-button')), findsNothing);
  });

  testWidgets('a reload without a session shows the login screen',
      (tester) async {
    final container = _container(_Server(401));
    final restored = container.read(authControllerProvider.notifier).restore();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const TefteriApp()));
    await _finish(tester, restored);
    expect(find.byKey(const Key('login-button')), findsOneWidget);
  });
}
