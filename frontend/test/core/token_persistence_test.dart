import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/core/auth_controller.dart';

/// A server with a login and `/auth/me`. [meStatus] is what `/auth/me`
/// answers (0: the connection fails).
class _Server implements HttpClientAdapter {
  _Server({this.meStatus = 200});

  int meStatus;
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
    if (options.path == '/auth/login') {
      return ResponseBody.fromString(jsonEncode({'token': 'tok-1'}), 200,
          headers: json);
    }
    if (options.path == '/auth/me') {
      if (meStatus == 0) {
        throw DioException(
            requestOptions: options, type: DioExceptionType.connectionError);
      }
      return ResponseBody.fromString(
          jsonEncode({'username': 'admin', 'is_admin': true}), meStatus,
          headers: json);
    }
    return ResponseBody.fromString('{}', 200, headers: json);
  }
}

/// What a start of the app builds, like `main()`: the saved token, and a
/// store that saves changes.
Future<ProviderContainer> _start(_Server server) async {
  final token = await TokenStore.load();
  final container = ProviderContainer(overrides: [
    tokenStoreProvider.overrideWith((_) => TokenStore(token, true)),
  ]);
  // The app's own client, with its token interceptor, talking to the fake.
  container.read(dioProvider).httpClientAdapter = server;
  addTearDown(container.dispose);
  return container;
}

Future<String?> _saved() async =>
    (await SharedPreferences.getInstance()).getString('session_token');

String? _bearer(_Server server) =>
    server.requests.last.headers['Authorization'] as String?;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a login is saved, so that a new start of the app is still signed in',
      () async {
    final first = await _start(_Server());
    await first.read(authControllerProvider.notifier).login('admin', 'pw');
    expect(first.read(authControllerProvider).signedIn, isTrue);
    await pumpEventQueue();
    expect(await _saved(), 'tok-1');

    // Android ended the process while the app was in the background. The
    // next start has an empty memory and only the saved token.
    final server = _Server();
    final second = await _start(server);
    expect(second.read(tokenStoreProvider), 'tok-1');
    await second.read(authControllerProvider.notifier).restore();
    expect(second.read(authControllerProvider).signedIn, isTrue);
    expect(second.read(authControllerProvider).isAdmin, isTrue);
    expect(_bearer(server), 'Bearer tok-1');
  });

  test('a start without a saved token is signed out', () async {
    final server = _Server(meStatus: 401);
    final c = await _start(server);
    await c.read(authControllerProvider.notifier).restore();
    expect(c.read(authControllerProvider).signedIn, isFalse);
    expect(c.read(authControllerProvider).restoring, isFalse);
  });

  test('a token that the server refuses is dropped from the device', () async {
    SharedPreferences.setMockInitialValues({'session_token': 'old'});
    final c = await _start(_Server(meStatus: 401));
    await c.read(authControllerProvider.notifier).restore();
    expect(c.read(authControllerProvider).signedIn, isFalse);
    expect(c.read(tokenStoreProvider), isNull);
    await pumpEventQueue();
    expect(await _saved(), isNull); // the next start asks for a login
  });

  test('a server that cannot be reached does not sign the user out', () async {
    SharedPreferences.setMockInitialValues({'session_token': 'tok-1'});
    final c = await _start(_Server(meStatus: 0));
    await c.read(authControllerProvider.notifier).restore();
    expect(c.read(authControllerProvider).signedIn, isTrue);
    expect(c.read(tokenStoreProvider), 'tok-1');
    expect(await _saved(), 'tok-1'); // still there for the next try
  });

  test('without a saved token, an unreachable server leaves the user out',
      () async {
    final c = await _start(_Server(meStatus: 0));
    await c.read(authControllerProvider.notifier).restore();
    expect(c.read(authControllerProvider).signedIn, isFalse);
  });

  test('signing out forgets the saved token', () async {
    SharedPreferences.setMockInitialValues({'session_token': 'tok-1'});
    final c = await _start(_Server());
    await c.read(authControllerProvider.notifier).restore();
    await c.read(authControllerProvider.notifier).logout();
    await pumpEventQueue();
    expect(await _saved(), isNull);
    expect(await TokenStore.load(), isNull);
    expect(c.read(authControllerProvider).signedIn, isFalse);
  });

  test('a store without persistence saves nothing', () async {
    final store = TokenStore();
    store.set('secret');
    await pumpEventQueue();
    expect(await _saved(), isNull);
  });
}
