import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/features/settings/connections_screen.dart';

/// Fake HTTP adapter that answers from a route table and records calls.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.routes);

  /// Maps "METHOD path" to a JSON body or a status code to fail with.
  final Map<String, Object> routes;

  /// Calls seen so far, as "METHOD path".
  final List<String> calls = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final key = '${options.method} ${options.path}';
    calls.add(key);
    final route = routes[key];
    if (route == null) {
      return ResponseBody.fromString('{}', 404, headers: _json);
    }
    return ResponseBody.fromString(jsonEncode(route), 200, headers: _json);
  }

  static const _json = {
    Headers.contentTypeHeader: ['application/json'],
  };
}

final _connections = [
  {
    'id': 'c1',
    'kind': 'calendar',
    'provider': 'google',
    'display_name': 'Work calendar',
    'default_context': 'work',
    'status': 'ok',
    'last_sync_at': '2026-11-01T09:30:00Z',
    'last_sync_outcome': 'ok',
  },
  {
    'id': 'c2',
    'kind': 'tasks',
    'provider': 'vikunja',
    'display_name': 'Home tasks',
    'default_context': 'personal',
    'status': 'ok',
    'last_sync_at': null,
    'last_sync_outcome': null,
  },
];

Map<String, Object?> _result(String id, String name, String outcome,
        [String? reason]) =>
    {
      'connection_id': id,
      'name': name,
      'outcome': outcome,
      'reason': reason,
      'counts': {'created': 1},
    };

Future<FakeAdapter> _pump(
    WidgetTester tester, Map<String, Object> routes) async {
  final adapter = FakeAdapter({
    'GET /connections': _connections,
    'GET /sync/status': {'last_sync_at': null, 'results': []},
    ...routes,
  });
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = adapter;
  await tester.pumpWidget(ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio)],
    child: const MaterialApp(home: ConnectionsScreen()),
  ));
  await tester.pumpAndSettle();
  return adapter;
}

void main() {
  testWidgets('lists connections with kind, provider and last sync',
      (tester) async {
    await _pump(tester, {});
    expect(find.text('Work calendar'), findsOneWidget);
    expect(find.textContaining('calendar - google'), findsOneWidget);
    expect(find.textContaining('(ok)'), findsOneWidget);
    expect(find.textContaining('never (none)'), findsOneWidget);
    expect(find.byKey(const Key('failure-c1')), findsNothing);
  });

  testWidgets('sync button calls POST /sync and shows success', (tester) async {
    final adapter = await _pump(tester, {
      'POST /sync': [
        _result('c1', 'Work calendar', 'ok'),
        _result('c2', 'Home tasks', 'ok'),
      ],
    });
    await tester.tap(find.byKey(const Key('sync-all-button')));
    await tester.pumpAndSettle();
    expect(adapter.calls, contains('POST /sync'));
    expect(find.byKey(const Key('failure-c1')), findsNothing);
    expect(find.byKey(const Key('failure-c2')), findsNothing);
  });

  testWidgets('app bar sync button runs the shared sync', (tester) async {
    final adapter = await _pump(tester, {
      'POST /sync': [_result('c1', 'Work calendar', 'ok')],
    });
    await tester.tap(find.byKey(const Key('sync-button')));
    await tester.pumpAndSettle();
    expect(adapter.calls, contains('POST /sync'));
    expect(find.text('Sync finished.'), findsOneWidget);
  });

  testWidgets('failing connections show name, reason and actions',
      (tester) async {
    await _pump(tester, {
      'POST /sync': [
        _result('c1', 'Work calendar', 'needs_attention', 'auth_expired'),
        _result('c2', 'Home tasks', 'error', 'unreachable'),
      ],
    });
    await tester.tap(find.byKey(const Key('sync-all-button')));
    await tester.pumpAndSettle();

    expect(find.text('Work calendar is unavailable'), findsOneWidget);
    expect(
        find.text('Your credentials expired or were revoked.'), findsOneWidget);
    expect(find.text('Home tasks is unavailable'), findsOneWidget);
    expect(find.text('The service is not reachable.'), findsOneWidget);
    for (final id in ['c1', 'c2']) {
      expect(find.byKey(Key('retry-$id')), findsOneWidget);
      expect(find.byKey(Key('reconnect-$id')), findsOneWidget);
      expect(find.byKey(Key('open-settings-$id')), findsOneWidget);
    }
  });

  testWidgets('other failures show a generic reason', (tester) async {
    await _pump(tester, {
      'POST /sync': [_result('c2', 'Home tasks', 'error', 'error')],
    });
    await tester.tap(find.byKey(const Key('sync-all-button')));
    await tester.pumpAndSettle();
    expect(find.text('The sync failed.'), findsOneWidget);
  });

  testWidgets('Retry calls POST /connections/{id}/sync and clears the failure',
      (tester) async {
    final adapter = await _pump(tester, {
      'POST /sync': [
        _result('c2', 'Home tasks', 'error', 'unreachable'),
      ],
      'POST /connections/c2/sync': [_result('c2', 'Home tasks', 'ok')],
    });
    await tester.tap(find.byKey(const Key('sync-all-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('failure-c2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('retry-c2')));
    await tester.pumpAndSettle();
    expect(adapter.calls, contains('POST /connections/c2/sync'));
    expect(find.byKey(const Key('failure-c2')), findsNothing);
  });

  testWidgets('a failed retry keeps the failure visible', (tester) async {
    await _pump(tester, {
      'POST /sync': [_result('c2', 'Home tasks', 'error', 'unreachable')],
      'POST /connections/c2/sync': [
        _result('c2', 'Home tasks', 'error', 'unreachable'),
      ],
    });
    await tester.tap(find.byKey(const Key('sync-all-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('retry-c2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('failure-c2')), findsOneWidget);
  });

  testWidgets('Open settings shows connection details', (tester) async {
    await _pump(tester, {
      'POST /sync': [_result('c2', 'Home tasks', 'error', 'unreachable')],
    });
    await tester.tap(find.byKey(const Key('sync-all-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-settings-c2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-sheet-c2')), findsOneWidget);
    expect(find.text('Provider: vikunja'), findsOneWidget);
  });

  testWidgets('Reconnect for Google fetches the sign-in link', (tester) async {
    final adapter = await _pump(tester, {
      'POST /sync': [
        _result('c1', 'Work calendar', 'needs_attention', 'auth_expired'),
      ],
      'GET /connections/google/authorize': {'url': 'https://example.com/auth'},
    });
    await tester.tap(find.byKey(const Key('sync-all-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reconnect-c1')));
    await tester.pumpAndSettle();
    expect(adapter.calls, contains('GET /connections/google/authorize'));
    expect(find.textContaining('https://example.com/auth'), findsOneWidget);
  });

  testWidgets('server failure is shown and no result is hidden',
      (tester) async {
    // No route for POST /sync, so the fake answers 404 (Dio throws).
    await _pump(tester, {});
    await tester.tap(find.byKey(const Key('sync-all-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sync-error')), findsOneWidget);
  });
}
