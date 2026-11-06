@Tags(['screenshots'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/auth_controller.dart';
import 'package:tefteri/features/admin/admin_settings_screen.dart';
import 'package:tefteri/features/admin/users_screen.dart';
import 'package:tefteri/features/auth/login_screen.dart';
import 'package:tefteri/features/settings/settings_screen.dart';

import 'screenshot_helper.dart';

class _Admin extends AuthController {
  _Admin(super.ref) {
    state = const AuthState(signedIn: true, isAdmin: true);
  }
}

Map<String, Object?> _user(String id, String name,
        {bool admin = false, bool disabled = false, String tz = 'UTC'}) =>
    {
      'id': id,
      'username': name,
      'is_admin': admin,
      'timezone': tz,
      'disabled': disabled,
    };

void main() {
  testWidgets('login screen', (tester) async {
    await pumpScreen(tester, FakeApi({}), const LoginScreen(showServer: false));
    await saveScreenshot('accounts-login');
  });

  testWidgets('admin user management', (tester) async {
    final api = FakeApi({
      'GET /users': [
        _user('u1', 'admin', admin: true, tz: 'Europe/London'),
        _user('u2', 'alex', tz: 'Europe/Athens'),
        _user('u3', 'sam', disabled: true),
      ],
    });
    await pumpScreen(tester, api, const UsersScreen(), overrides: [
      authControllerProvider.overrideWith(_Admin.new),
    ]);
    await saveScreenshot('accounts-users');
  });

  testWidgets('settings page', (tester) async {
    await pumpScreen(tester, FakeApi({}), const SettingsScreen());
    await saveScreenshot('settings-page');
  });

  testWidgets('admin settings page', (tester) async {
    await pumpScreen(tester, FakeApi({}), const AdminSettingsScreen(),
        overrides: [authControllerProvider.overrideWith(_Admin.new)]);
    await saveScreenshot('admin-settings-page');
  });
}
