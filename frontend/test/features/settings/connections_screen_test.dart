import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/core/open_url.dart';
import 'package:tefteri/features/settings/connections_screen.dart';

/// Fake HTTP adapter that answers from a route table and records calls.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.routes);

  /// Maps "METHOD path" to a JSON body, or to a function of the request
  /// that returns one.
  final Map<String, Object> routes;

  /// Calls seen so far, as "METHOD path".
  final List<String> calls = [];

  /// The last request seen for each "METHOD path".
  final Map<String, RequestOptions> requests = {};

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final key = '${options.method} ${options.path}';
    calls.add(key);
    requests[key] = options;
    var route = routes[key];
    if (route is Object Function(RequestOptions)) route = route(options);
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
    'provider': 'google_calendar',
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
    'default_context': 'life',
    'settings': {'base_url': 'https://old.test'},
    'status': 'ok',
    'last_sync_at': null,
    'last_sync_outcome': null,
  },
];

/// URLs the screen asked to open in the browser, in order.
final _opened = <Uri>[];

Map<String, Object?> _result(String id, String name, String outcome,
        [String? reason, String? detail]) =>
    {
      'connection_id': id,
      'name': name,
      'outcome': outcome,
      'reason': reason,
      'detail': detail,
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
  _opened.clear();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(dio),
      openUrlProvider.overrideWithValue((uri) async {
        _opened.add(uri);
        return true;
      }),
    ],
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
    expect(find.textContaining('calendar - google_calendar'), findsOneWidget);
    expect(find.textContaining('vikunja - https://old.test'), findsOneWidget);
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

  testWidgets('opening the screen loads the status without a message',
      (tester) async {
    final adapter = await _pump(tester, {});
    expect(adapter.calls, contains('GET /sync/status'));
    expect(find.text('Sync finished.'), findsNothing);
  });

  testWidgets('a sync with failures says so in the message', (tester) async {
    await _pump(tester, {
      'POST /sync': [_result('c2', 'Home tasks', 'error', 'unreachable')],
    });
    await tester.tap(find.byKey(const Key('sync-button')));
    await tester.pumpAndSettle();
    expect(find.text('Sync finished.'), findsNothing);
    expect(
        find.textContaining('1 connection(s) need attention'), findsOneWidget);
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

  testWidgets('Open settings opens the edit dialog', (tester) async {
    await _pump(tester, {
      'POST /sync': [_result('c2', 'Home tasks', 'error', 'unreachable')],
    });
    await tester.tap(find.byKey(const Key('sync-all-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-settings-c2')));
    await tester.pumpAndSettle();
    expect(find.text('Edit connection'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'https://old.test'), findsOneWidget);
  });

  testWidgets('a failed sync shows the error from the server', (tester) async {
    await _pump(tester, {
      'POST /sync': [
        _result('c2', 'Home tasks', 'error', 'unreachable',
            'cannot reach http://localhost:3456/api/v1/projects'),
      ],
    });
    await tester.tap(find.byKey(const Key('sync-all-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('failure-detail-c2')), findsOneWidget);
    expect(find.textContaining('localhost:3456'), findsOneWidget);
  });

  testWidgets('Reconnect for a token app opens the edit dialog',
      (tester) async {
    await _pump(tester, {
      'POST /sync': [_result('c2', 'Home tasks', 'needs_attention')],
    });
    await tester.tap(find.byKey(const Key('sync-all-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reconnect-c2')));
    await tester.pumpAndSettle();
    expect(find.text('Edit connection'), findsOneWidget);
  });

  group('Testing a connection after it is saved', () {
    Future<FakeAdapter> editAndSave(
        WidgetTester tester, Map<String, Object> extra) async {
      final adapter = await _pump(tester, {
        'PATCH /connections/c2': <String, Object?>{},
        ...extra,
      });
      await tester.tap(find.byKey(const Key('edit-c2')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('new-connection-url')), 'https://new.test');
      await tester.pump();
      await tester.tap(find.byKey(const Key('new-connection-save')));
      await tester.pumpAndSettle();
      return adapter;
    }

    testWidgets('a working connection says it is saved', (tester) async {
      final adapter = await editAndSave(tester, {
        'POST /connections/c2/check': {
          'status': 'ok',
          'reason': null,
          'message': null,
        },
      });
      expect(adapter.calls, contains('POST /connections/c2/check'));
      expect(find.text('Saved Home tasks.'), findsOneWidget);
      expect(find.byKey(const Key('connection-check-failed')), findsNothing);
    });

    testWidgets('a connection that does not work shows the reason',
        (tester) async {
      await editAndSave(tester, {
        'POST /connections/c2/check': {
          'status': 'error',
          'reason': 'error',
          'message': 'GET https://new.test/etapi/app-info answered 404. '
              'Check the address and the root note.',
        },
      });
      expect(find.byKey(const Key('connection-check-failed')), findsOneWidget);
      expect(find.textContaining('Home tasks is saved, but it does not work.'),
          findsOneWidget);
      expect(find.textContaining('app-info answered 404'), findsOneWidget);
      expect(find.text('Saved Home tasks.'), findsNothing);
    });

    testWidgets('without a message, the reason code gets plain words',
        (tester) async {
      await editAndSave(tester, {
        'POST /connections/c2/check': {
          'status': 'error',
          'reason': 'unreachable',
          'message': null,
        },
      });
      expect(
          find.textContaining('The service is not reachable.'), findsOneWidget);
    });

    testWidgets('when the test itself cannot run, the save still counts',
        (tester) async {
      // No route for the check: the fake answers 404.
      await editAndSave(tester, {});
      expect(find.text('Saved Home tasks.'), findsOneWidget);
    });

    testWidgets('a new connection is tested with the id the server gave it',
        (tester) async {
      final adapter = await _pump(tester, {
        'POST /connections': {'id': 'c9', 'display_name': 'Notes'},
        'POST /connections/c9/check': {
          'status': 'needs_attention',
          'reason': 'auth_expired',
          'message': 'credentials rejected. Check the ETAPI token.',
        },
      });
      await tester.tap(find.byKey(const Key('add-connection')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-connection-provider')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trilium Next').last);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('new-connection-name')), 'Notes');
      await tester.enterText(
          find.byKey(const Key('new-connection-url')), 'https://trilium.test');
      await tester.enterText(
          find.byKey(const Key('new-connection-token')), 'secret');
      await tester.pump();
      await tester.tap(find.byKey(const Key('new-connection-save')));
      await tester.pumpAndSettle();
      expect(
          adapter.calls,
          containsAllInOrder(
              ['POST /connections', 'POST /connections/c9/check']));
      expect(find.textContaining('Check the ETAPI token.'), findsOneWidget);
    });
  });

  group('Edit and remove', () {
    testWidgets('editing the URL keeps the token and sends a PATCH',
        (tester) async {
      final adapter =
          await _pump(tester, {'PATCH /connections/c2': <String, Object?>{}});
      await tester.tap(find.byKey(const Key('edit-c2')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('new-connection-url')), 'https://new.test');
      await tester.tap(find.text('Work'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('new-connection-save')));
      await tester.pumpAndSettle();
      expect(adapter.requests['PATCH /connections/c2']!.data, {
        'display_name': 'Home tasks',
        'default_context': 'both',
        'settings': {'base_url': 'https://new.test'},
      });
      expect(find.text('Saved Home tasks.'), findsOneWidget);
    });

    testWidgets('a new token is sent as credentials', (tester) async {
      final adapter =
          await _pump(tester, {'PATCH /connections/c2': <String, Object?>{}});
      await tester.tap(find.byKey(const Key('edit-c2')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('new-connection-token')), 'fresh');
      await tester.pump();
      await tester.tap(find.byKey(const Key('new-connection-save')));
      await tester.pumpAndSettle();
      expect(
          (adapter.requests['PATCH /connections/c2']!.data
              as Map)['credentials'],
          {'token': 'fresh'});
    });

    testWidgets('Remove asks first, then sends a DELETE', (tester) async {
      final adapter =
          await _pump(tester, {'DELETE /connections/c2': <String, Object?>{}});
      await tester.tap(find.byKey(const Key('remove-c2')));
      await tester.pumpAndSettle();
      expect(find.text('Remove Home tasks?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('remove-confirm')));
      await tester.pumpAndSettle();
      expect(adapter.calls, contains('DELETE /connections/c2'));
      expect(find.text('Removed Home tasks.'), findsOneWidget);
    });

    testWidgets('cancelling Remove sends nothing', (tester) async {
      final adapter = await _pump(tester, {});
      await tester.tap(find.byKey(const Key('remove-c2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(adapter.calls, isNot(contains('DELETE /connections/c2')));
    });
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

  group('Add connection', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('add-connection')));
      await tester.pumpAndSettle();
    }

    FilledButton saveButton(WidgetTester tester) => tester
        .widget<FilledButton>(find.byKey(const Key('new-connection-save')));

    testWidgets(
        'a new user with no connections adds Vikunja and sees it listed',
        (tester) async {
      // Onboarding: the list starts empty and the server stores what we post.
      final stored = <Map<String, Object?>>[];
      final adapter = await _pump(tester, {
        'GET /connections': (RequestOptions _) => stored,
        'POST /connections': (RequestOptions o) {
          final body = o.data as Map<String, Object?>;
          final created = {
            'id': 'new1',
            'kind': 'tasks',
            'provider': body['provider'],
            'display_name': body['display_name'],
            'default_context': body['default_context'],
            'status': 'ok',
            'last_sync_at': null,
            'last_sync_outcome': null,
          };
          stored.add(created);
          return created;
        },
      });
      expect(find.text('No connections yet.'), findsOneWidget);

      await openDialog(tester);
      expect(saveButton(tester).onPressed, isNull);
      await tester.enterText(
          find.byKey(const Key('new-connection-name')), 'Home tasks');
      await tester.enterText(
          find.byKey(const Key('new-connection-url')), 'https://vikunja.test/');
      await tester.enterText(
          find.byKey(const Key('new-connection-token')), 'tok');
      await tester.pump();
      await tester.tap(find.byKey(const Key('new-connection-save')));
      await tester.pumpAndSettle();

      // The body that backend/tests/e2e/test_onboarding.py sends to the
      // real adapters; keep the two in step.
      expect(adapter.requests['POST /connections']!.data, {
        'provider': 'vikunja',
        'display_name': 'Home tasks',
        'default_context': 'life',
        'settings': {'base_url': 'https://vikunja.test/'},
        'credentials': {'token': 'tok'},
      });
      expect(find.text('Connected Home tasks.'), findsOneWidget);
      expect(find.byKey(const Key('connection-new1')), findsOneWidget);
      expect(find.text('No connections yet.'), findsNothing);
    });

    Future<Object?> addTrilium(
        WidgetTester tester, List<String> contextTaps) async {
      final adapter =
          await _pump(tester, {'POST /connections': <String, Object?>{}});
      await openDialog(tester);
      await tester.tap(find.byKey(const Key('new-connection-provider')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trilium Next').last);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'ETAPI token'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('new-connection-url')), 'https://notes.test');
      await tester.enterText(
          find.byKey(const Key('new-connection-token')), 'etapi');
      for (final label in contextTaps) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('new-connection-save')));
      await tester.pumpAndSettle();
      return adapter.requests['POST /connections']!.data;
    }

    testWidgets('Trilium Next sends its provider and Work alone',
        (tester) async {
      // Life starts selected: add Work, then remove Life.
      expect(await addTrilium(tester, ['Work', 'Life']), {
        'provider': 'trilium',
        'display_name': 'Trilium Next',
        'default_context': 'work',
        'settings': {'base_url': 'https://notes.test'},
        'credentials': {'token': 'etapi'},
      });
    });

    testWidgets('selecting Life and Work sends both', (tester) async {
      final body = await addTrilium(tester, ['Work']);
      expect((body! as Map)['default_context'], 'both');
    });

    testWidgets('the last selected context cannot be removed', (tester) async {
      final body = await addTrilium(tester, ['Life']);
      expect((body! as Map)['default_context'], 'life');
    });

    testWidgets('Google Calendar asks the server for the sign-in link',
        (tester) async {
      final adapter = await _pump(tester, {
        'GET /connections/google/authorize': {
          'url': 'https://accounts.example/auth'
        },
      });
      await openDialog(tester);
      await tester.tap(find.byKey(const Key('new-connection-provider')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Google Calendar').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-connection-token')), findsNothing);
      await tester.tap(find.byKey(const Key('new-connection-save')));
      await tester.pumpAndSettle();

      final request = adapter.requests['GET /connections/google/authorize']!;
      expect(request.queryParameters, {
        'display_name': 'Google Calendar',
        'default_context': 'life',
      });
      expect(adapter.calls, isNot(contains('POST /connections')));
      expect(
          find.textContaining('https://accounts.example/auth'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-sign-in')));
      await tester.pumpAndSettle();
      expect(_opened, [Uri.parse('https://accounts.example/auth')]);
    });

    testWidgets('a refused connection shows the server message',
        (tester) async {
      // No route for POST /connections, so the fake answers 404.
      await _pump(tester, {});
      await openDialog(tester);
      await tester.enterText(
          find.byKey(const Key('new-connection-url')), 'https://vikunja.test');
      await tester.enterText(
          find.byKey(const Key('new-connection-token')), 'tok');
      await tester.pump();
      await tester.tap(find.byKey(const Key('new-connection-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('connection-error')), findsOneWidget);
    });

    testWidgets('Cancel sends nothing', (tester) async {
      final adapter = await _pump(tester, {});
      await openDialog(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(adapter.calls, isNot(contains('POST /connections')));
    });
  });
}
