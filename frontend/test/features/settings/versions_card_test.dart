import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/core/server_address.dart';
import 'package:tefteri/core/update_check.dart';
import 'package:tefteri/core/versions.dart';
import 'package:tefteri/features/settings/versions_card.dart';

Future<void> _pump(WidgetTester tester,
    {PublishedRelease? latest, List<UpdateChannel>? asked}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appVersionProvider
          .overrideWith((_) async => const AppVersion('1.4.0', 2)),
      serverVersionProvider.overrideWith((ref, address) async => '1.3.0'),
      serverAddressProvider
          .overrideWith((_) => ServerAddress('https://t.example')),
      releaseFetcherProvider.overrideWithValue((channel) async {
        asked?.add(channel);
        return latest ??
            const PublishedRelease(
                name: '1.4.0', post: null, url: '', label: '1.4.0');
      }),
    ],
    child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: VersionsCard()))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('versions are hidden until the switch is on', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('backend-version')), findsNothing);
    await tester.tap(find.byKey(const Key('show-versions-switch')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('backend-version'))).data,
        '1.3.0');
    expect(tester.widget<Text>(find.byKey(const Key('app-version'))).data,
        '1.4.0 (build 2)');
  });

  testWidgets('the update check follows the chosen channel', (tester) async {
    final asked = <UpdateChannel>[];
    await _pump(tester,
        asked: asked,
        latest: const PublishedRelease(
            name: '1.5.0', post: null, url: 'u', label: '1.5.0'));
    await tester.tap(find.byKey(const Key('check-updates')));
    await tester.pumpAndSettle();
    expect(asked, [UpdateChannel.standard]);
    expect(find.text('A newer version is available: 1.5.0.'), findsOneWidget);
    expect(find.byKey(const Key('update-open')), findsOneWidget);

    await tester.tap(find.text('Nightly'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update-result')), findsNothing);
    await tester.tap(find.byKey(const Key('check-updates')));
    await tester.pumpAndSettle();
    expect(asked, [UpdateChannel.standard, UpdateChannel.nightly]);
  });

  testWidgets('up to date says so', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('check-updates')));
    await tester.pumpAndSettle();
    expect(find.text('You have the latest version (1.4.0).'), findsOneWidget);
  });

  test('only Android and Linux get the card', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(isInstalledClient, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(isInstalledClient, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(isInstalledClient, isFalse);
  });
}
