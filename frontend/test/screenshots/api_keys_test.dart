@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/settings/api_keys_card.dart';

import 'screenshot_helper.dart';

FakeApi _api() => FakeApi({
      'GET /me/api-keys': [
        {
          'id': 'k2',
          'name': 'Cursor',
          'prefix': 'tft_Hy4kLm',
          'created_at': '2026-11-02T08:20:00Z',
          'last_used_at': null,
        },
        {
          'id': 'k1',
          'name': 'Claude Code',
          'prefix': 'tft_Qz81aB',
          'created_at': '2026-11-01T18:05:00Z',
          'last_used_at': '2026-11-02T08:40:00Z',
        },
      ],
      'POST /me/api-keys': {
        'id': 'k3',
        'name': 'Claude Code',
        'prefix': 'tft_Qz81aB',
        'created_at': '2026-11-02T09:00:00Z',
        'last_used_at': null,
        'key': 'tft_Qz81aBexampleexampleexampleexampleexample',
      },
    });

const _screen = Scaffold(
  body: SingleChildScrollView(
    padding: EdgeInsets.all(24),
    child: ApiKeysCard(),
  ),
);

void main() {
  testWidgets('api keys', (tester) async {
    await pumpScreen(tester, _api(), _screen);
    await saveScreenshot('settings-api-keys');
  });

  testWidgets('new api key', (tester) async {
    await pumpScreen(tester, _api(), _screen, size: const Size(1100, 900));
    await tester.tap(find.byKey(const Key('create-api-key')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('api-key-name-create')));
    await tester.pumpAndSettle();
    await saveScreenshot('settings-api-key-new');
  });
}
