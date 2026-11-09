import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/server_address.dart';
import 'package:tefteri/core/versions.dart';
import 'package:tefteri/features/admin/admin_settings_screen.dart';

Future<void> _pump(WidgetTester tester,
    {bool serverReachable = true, bool appKnown = true}) async {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      serverAddressProvider
          .overrideWith((_) => ServerAddress('https://t.example')),
      serverVersionProvider.overrideWith((ref, address) async {
        if (!serverReachable) throw StateError('down');
        return '0.1.0.befb2e7.post14';
      }),
      appVersionProvider.overrideWith((_) async {
        if (!appKnown) throw StateError('unknown');
        return const AppVersion('0.1.0', 14);
      }),
    ],
    child: const MaterialApp(home: AdminSettingsScreen()),
  ));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<SelectableText>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('shows the version of the server and of the client app',
      (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('admin-versions')), findsOneWidget);
    expect(_text(tester, 'admin-server-version'), '0.1.0.befb2e7.post14');
    expect(_text(tester, 'admin-client-version'), '0.1.0 (build 14)');
    // The page still lists its entries.
    expect(find.byKey(const Key('settings-users')), findsOneWidget);
  });

  testWidgets('says so when a version cannot be read', (tester) async {
    await _pump(tester, serverReachable: false, appKnown: false);
    expect(_text(tester, 'admin-server-version'),
        'Unknown (cannot reach the server)');
    expect(_text(tester, 'admin-client-version'), 'Unknown');
  });
}
