import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/auth/change_password_screen.dart';

import '../../support/fake_api.dart';

Future<void> _fill(
    WidgetTester tester, String cur, String next, String again) async {
  await tester.enterText(find.byKey(const Key('current-password')), cur);
  await tester.enterText(find.byKey(const Key('new-password')), next);
  await tester.enterText(find.byKey(const Key('confirm-password')), again);
  await tester.tap(find.byKey(const Key('password-save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sends the passwords and shows success', (tester) async {
    final api = FakeApi({'POST /auth/password': const NoContent()});
    await pumpWithApi(tester, api, const ChangePasswordScreen());
    await _fill(tester, 'old-pass', 'new-password', 'new-password');
    final sent = api.where('POST /auth/password').single.data as Map;
    expect(sent['current_password'], 'old-pass');
    expect(sent['new_password'], 'new-password');
    expect(find.byKey(const Key('password-changed')), findsOneWidget);
  });

  testWidgets('shows the server error for a wrong current password',
      (tester) async {
    final api = FakeApi({
      'POST /auth/password': const ApiFailure(
          401, 'Current password is wrong.', 'invalid_credentials'),
    });
    await pumpWithApi(tester, api, const ChangePasswordScreen());
    await _fill(tester, 'bad', 'new-password', 'new-password');
    expect(find.byKey(const Key('error-banner')), findsOneWidget);
    expect(find.text('Current password is wrong.'), findsOneWidget);
    expect(find.byKey(const Key('password-changed')), findsNothing);
  });

  testWidgets('does not call the server when the passwords differ',
      (tester) async {
    final api = FakeApi({'POST /auth/password': const NoContent()});
    await pumpWithApi(tester, api, const ChangePasswordScreen());
    await _fill(tester, 'old-pass', 'new-password', 'other-password');
    expect(api.where('POST /auth/password'), isEmpty);
    expect(find.text('The new passwords do not match.'), findsOneWidget);
  });
}
