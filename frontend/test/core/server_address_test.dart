import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/core/server_address.dart';
import 'package:tefteri/features/auth/login_screen.dart';

void main() {
  group('normalizeServerAddress', () {
    test('adds https and drops slashes and the API path', () {
      expect(normalizeServerAddress(' tefteri.example.com/ '),
          'https://tefteri.example.com');
      expect(normalizeServerAddress('http://192.168.1.5:8000/api/v1/'),
          'http://192.168.1.5:8000');
      expect(normalizeServerAddress('https://host/tefteri'),
          'https://host/tefteri');
    });

    test('rejects empty and non-web addresses', () {
      expect(normalizeServerAddress('  '), isNull);
      expect(normalizeServerAddress('ftp://host'), isNull);
    });
  });

  testWidgets('login screen saves the server address', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LoginScreen(showServer: true)),
    ));
    await tester.tap(find.byKey(const Key('login-button')));
    await tester.pump();
    expect(find.text('Enter the address of your server'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('server')), 'my.server');
    await tester.tap(find.byKey(const Key('login-button')));
    await tester.pump();
    expect(container.read(serverAddressProvider), 'https://my.server');
    expect(container.read(apiBaseUrlProvider), 'https://my.server/api/v1');
  });
}
