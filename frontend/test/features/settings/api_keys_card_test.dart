import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/settings/api_keys_card.dart';

import '../../support/fake_api.dart';

Map<String, Object?> _key(String id, String name,
        {String? lastUsed, String created = '2026-11-02T09:00:00Z'}) =>
    {
      'id': id,
      'name': name,
      'prefix': 'tft_ab12cd',
      'created_at': created,
      'last_used_at': lastUsed,
    };

Future<FakeApi> _pump(WidgetTester tester, Map<String, Object?> routes) async {
  final api = FakeApi(routes);
  tester.view.physicalSize = const Size(1000, 2000);
  addTearDown(tester.view.reset);
  await pumpWithApi(tester, api,
      const Scaffold(body: SingleChildScrollView(child: ApiKeysCard())));
  return api;
}

void main() {
  testWidgets('with no key it says so and shows the address of the MCP server',
      (tester) async {
    await _pump(tester, {'GET /me/api-keys': <Object?>[]});
    expect(find.byKey(const Key('api-keys-empty')), findsOneWidget);
    expect(find.byKey(const Key('create-api-key')), findsOneWidget);
    // The address is the server of the app, and /mcp.
    final url = tester.widget<SelectableText>(find.byKey(const Key('mcp-url')));
    expect(url.data, endsWith('/mcp'));
    expect(url.data, isNot(contains('/api/v1')));
  });

  testWidgets('the keys are listed with their name and when they were used',
      (tester) async {
    await _pump(tester, {
      'GET /me/api-keys': [
        _key('k1', 'Claude Desktop', lastUsed: '2026-11-05T14:30:00Z'),
        _key('k2', 'Old script'),
      ],
    });
    expect(find.text('Claude Desktop'), findsOneWidget);
    expect(find.text('Old script'), findsOneWidget);
    final used =
        tester.widget<Text>(find.byKey(const Key('api-key-detail-k1')));
    expect(used.data, contains('tft_ab12cd...'));
    expect(used.data, contains('Used '));
    final never =
        tester.widget<Text>(find.byKey(const Key('api-key-detail-k2')));
    expect(never.data, contains('Never used.'));
  });

  testWidgets(
      'a new key is named, shown once with the lines to connect a tool, and copied',
      (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    var made = false;
    final api = await _pump(tester, {
      'GET /me/api-keys': (_) => made ? [_key('k1', 'Claude')] : <Object?>[],
      'POST /me/api-keys': (o) {
        made = true;
        return {
          ..._key('k1', (o.data as Map)['name'] as String),
          'key': 'tft_SECRET'
        };
      },
    });
    await tester.tap(find.byKey(const Key('create-api-key')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('api-key-name-dialog')), findsOneWidget);
    // The name starts as Claude, and can change.
    await tester.enterText(
        find.byKey(const Key('api-key-name-field')), 'My laptop');
    await tester.tap(find.byKey(const Key('api-key-name-create')));
    await tester.pumpAndSettle();

    expect(api.where('POST /me/api-keys').single.data, {'name': 'My laptop'});
    expect(find.byKey(const Key('new-api-key-dialog')), findsOneWidget);
    expect(find.byKey(const Key('api-key-once-note')), findsOneWidget);
    expect(
        tester
            .widget<SelectableText>(find.byKey(const Key('new-api-key')))
            .data,
        'tft_SECRET');
    final command = tester
        .widget<SelectableText>(find.byKey(const Key('claude-code-command')))
        .data!;
    expect(command, startsWith('claude mcp add --transport http tefteri '));
    expect(command, contains('/mcp'));
    expect(command, contains('Authorization: Bearer tft_SECRET'));
    expect(
        tester.widget<SelectableText>(find.byKey(const Key('mcp-config'))).data,
        contains('"Authorization": "Bearer tft_SECRET"'));

    await tester.tap(find.byKey(const Key('copy-api-key')));
    await tester.pump();
    expect(copied.last, 'tft_SECRET');
    await tester.tap(find.byKey(const Key('copy-claude-command')));
    await tester.pump();
    expect(copied.last, command);

    await tester.tap(find.byKey(const Key('api-key-done')));
    await tester.pumpAndSettle();
    // The list shows the key, but not the key itself.
    expect(find.byKey(const Key('new-api-key-dialog')), findsNothing);
    expect(find.text('Claude'), findsOneWidget);
    expect(find.textContaining('tft_SECRET'), findsNothing);
  });

  testWidgets('a key without a name cannot be made', (tester) async {
    await _pump(tester, {'GET /me/api-keys': <Object?>[]});
    await tester.tap(find.byKey(const Key('create-api-key')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key-name-field')), '   ');
    await tester.pump();
    final create = tester
        .widget<FilledButton>(find.byKey(const Key('api-key-name-create')));
    expect(create.onPressed, isNull);
  });

  testWidgets('a key is revoked after the user confirms', (tester) async {
    var revoked = false;
    final api = await _pump(tester, {
      'GET /me/api-keys': (_) => revoked ? <Object?>[] : [_key('k1', 'Claude')],
      'DELETE /me/api-keys/k1': (_) {
        revoked = true;
        return const NoContent();
      },
    });
    await tester.tap(find.byKey(const Key('revoke-k1')));
    await tester.pumpAndSettle();
    // Cancel keeps it.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.where('DELETE /me/api-keys/k1'), isEmpty);
    await tester.tap(find.byKey(const Key('revoke-k1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('revoke-confirm-yes')));
    await tester.pumpAndSettle();
    expect(api.where('DELETE /me/api-keys/k1'), hasLength(1));
    expect(find.byKey(const Key('api-keys-empty')), findsOneWidget);
  });

  testWidgets('a server error is shown in plain words', (tester) async {
    await _pump(tester, {
      'GET /me/api-keys': const ApiFailure(
          500, 'Something is wrong on the server.', 'server_error'),
    });
    expect(find.byKey(const Key('api-keys-error')), findsOneWidget);
  });
}
