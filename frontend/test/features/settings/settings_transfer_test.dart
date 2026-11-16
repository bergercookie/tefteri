import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/settings/settings_transfer_card.dart';

import '../../support/fake_api.dart';

const _file = {
  'format': 'tefteri-settings',
  'version': 1,
  'settings': {
    'random_time_on_date_drop': true,
    'default_reminder_minutes': 45,
  },
};

void main() {
  test('parseSettingsExport accepts an export and refuses anything else', () {
    expect(parseSettingsExport(jsonEncode(_file)), _file);
    expect(() => parseSettingsExport('not json'), throwsFormatException);
    expect(() => parseSettingsExport('{"format": "other"}'),
        throwsFormatException);
    expect(() => parseSettingsExport('[1, 2]'), throwsFormatException);
  });

  testWidgets('export shows the file and copies it', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final api = FakeApi({'GET /me/settings/export': _file});
    await pumpWithApi(
        tester, api, const Scaffold(body: SettingsTransferCard()));

    await tester.tap(find.byKey(const Key('export-settings-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export-settings-text')), findsOneWidget);

    await tester.tap(find.byKey(const Key('export-copy-button')));
    await tester.pumpAndSettle();
    expect(jsonDecode(copied!), _file);
    expect(find.text('Settings copied.'), findsOneWidget);
  });

  testWidgets('a failed export shows the message', (tester) async {
    final api = FakeApi({
      'GET /me/settings/export':
          const ApiFailure(500, 'Could not export.', 'error'),
    });
    await pumpWithApi(
        tester, api, const Scaffold(body: SettingsTransferCard()));
    await tester.tap(find.byKey(const Key('export-settings-button')));
    await tester.pumpAndSettle();
    expect(find.text('Could not export.'), findsOneWidget);
  });

  testWidgets('import sends the pasted file', (tester) async {
    final api = FakeApi({
      'POST /me/settings/import': {'random_time_on_date_drop': true},
    });
    await pumpWithApi(
        tester, api, const Scaffold(body: SettingsTransferCard()));
    await tester.tap(find.byKey(const Key('import-settings-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('import-settings-field')), jsonEncode(_file));
    await tester.tap(find.byKey(const Key('import-submit-button')));
    await tester.pumpAndSettle();
    expect(api.where('POST /me/settings/import').single.data, _file);
    expect(find.text('Settings imported.'), findsOneWidget);
    expect(find.byKey(const Key('import-settings-field')), findsNothing);
  });

  testWidgets('import refuses text that is not an export, without a request',
      (tester) async {
    final api = FakeApi({});
    await pumpWithApi(
        tester, api, const Scaffold(body: SettingsTransferCard()));
    await tester.tap(find.byKey(const Key('import-settings-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('import-settings-field')), '{"a": 1}');
    await tester.tap(find.byKey(const Key('import-submit-button')));
    await tester.pumpAndSettle();
    expect(find.text('This is not a Tefteri settings export.'), findsOneWidget);
    expect(api.where('POST /me/settings/import'), isEmpty);
  });

  testWidgets('a server refusal stays in the dialog', (tester) async {
    final api = FakeApi({
      'POST /me/settings/import':
          const ApiFailure(422, 'Reminder is too long.', 'invalid'),
    });
    await pumpWithApi(
        tester, api, const Scaffold(body: SettingsTransferCard()));
    await tester.tap(find.byKey(const Key('import-settings-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('import-settings-field')), jsonEncode(_file));
    await tester.tap(find.byKey(const Key('import-submit-button')));
    await tester.pumpAndSettle();
    expect(find.text('Reminder is too long.'), findsOneWidget);
    expect(find.byKey(const Key('import-settings-field')), findsOneWidget);
  });
}
