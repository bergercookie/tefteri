import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/settings/android_app_card.dart';

import '../../support/fake_api.dart';

Future<void> _pump(WidgetTester tester, Map<String, Object?> body) async {
  tester.view.physicalSize = const Size(1000, 2000);
  addTearDown(tester.view.reset);
  await pumpWithApi(tester, FakeApi({'GET /me/android-app': body}),
      const Scaffold(body: SingleChildScrollView(child: AndroidAppCard())));
}

void main() {
  testWidgets('shows the version, the QR code and the link, and copies it',
      (tester) async {
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
    await _pump(tester, {
      'version': '1.5.0',
      'available': true,
      'release_url': 'https://github.com/o/r/releases/tag/v1.5.0',
      'obtainium_link': 'obtainium://app/abc',
      'qr': ['1010', '0101', '1010', '0101'],
    });
    expect(
        tester.widget<Text>(find.byKey(const Key('android-app-version'))).data,
        'Server version 1.5.0');
    expect(find.byKey(const Key('android-app-qr')), findsOneWidget);
    expect(
        tester
            .widget<SelectableText>(find.byKey(const Key('android-app-link')))
            .data,
        'obtainium://app/abc');
    // The desktop test platform offers no "Open in Obtainium".
    expect(find.byKey(const Key('open-in-obtainium')), findsNothing);
    await tester.tap(find.byKey(const Key('copy-obtainium-link')));
    await tester.pump();
    expect(copied, 'obtainium://app/abc');
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('on Android the card offers Open in Obtainium', (tester) async {
    await _pump(tester, {
      'version': '1.5.0',
      'available': true,
      'release_url': 'https://github.com/o/r/releases/tag/v1.5.0',
      'obtainium_link': 'obtainium://app/abc',
      'qr': ['1010', '0101', '1010', '0101'],
    });
    expect(find.byKey(const Key('open-in-obtainium')), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('says so when the server is not a published release',
      (tester) async {
    await _pump(tester, {
      'version': 'unknown',
      'available': false,
      'release_url': null,
      'obtainium_link': null,
      'qr': <String>[],
    });
    expect(find.byKey(const Key('android-app-unavailable')), findsOneWidget);
    expect(find.byKey(const Key('android-app-qr')), findsNothing);
  });
}
