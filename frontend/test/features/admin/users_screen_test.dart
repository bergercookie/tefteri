import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/admin/users_screen.dart';

import '../../support/fake_api.dart';

Map<String, Object?> _user(String id, String name,
        {bool admin = false, bool disabled = false}) =>
    {
      'id': id,
      'username': name,
      'is_admin': admin,
      'timezone': 'UTC',
      'disabled': disabled,
    };

final _users = [_user('u1', 'root', admin: true), _user('u2', 'ann')];

void main() {
  testWidgets('lists users', (tester) async {
    final api = FakeApi({'GET /users': _users});
    await pumpWithApi(tester, api, const UsersScreen());
    expect(find.text('root'), findsOneWidget);
    expect(find.text('ann'), findsOneWidget);
    expect(find.text('Admin - UTC'), findsOneWidget);
  });

  testWidgets('disables a user', (tester) async {
    final api = FakeApi({
      'GET /users': _users,
      'PATCH /users/u2': _user('u2', 'ann', disabled: true),
    });
    await pumpWithApi(tester, api, const UsersScreen());
    await tester.tap(find.byKey(const Key('toggle-u2')));
    await tester.pumpAndSettle();
    expect(api.where('PATCH /users/u2').single.data, {'disabled': true});
  });

  testWidgets('adds a user', (tester) async {
    final api = FakeApi({
      'GET /users': _users,
      'POST /users': _user('u3', 'bob', admin: true),
    });
    await pumpWithApi(tester, api, const UsersScreen());
    await tester.tap(find.byKey(const Key('add-user')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-username')), 'bob');
    await tester.enterText(
        find.byKey(const Key('new-password')), 'secret-pass');
    await tester.tap(find.byKey(const Key('new-admin')));
    await tester.tap(find.byKey(const Key('new-save')));
    await tester.pumpAndSettle();
    expect(api.where('POST /users').single.data,
        {'username': 'bob', 'password': 'secret-pass', 'is_admin': true});
  });

  testWidgets('shows the server error when the name is taken', (tester) async {
    final api = FakeApi({
      'GET /users': _users,
      'POST /users':
          const ApiFailure(409, 'Username is taken.', 'username_taken'),
    });
    await pumpWithApi(tester, api, const UsersScreen());
    await tester.tap(find.byKey(const Key('add-user')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-username')), 'ann');
    await tester.enterText(
        find.byKey(const Key('new-password')), 'secret-pass');
    await tester.tap(find.byKey(const Key('new-save')));
    await tester.pumpAndSettle();
    expect(find.text('Username is taken.'), findsOneWidget);
  });

  testWidgets('resets a password', (tester) async {
    final api = FakeApi({
      'GET /users': _users,
      'PATCH /users/u2': _user('u2', 'ann'),
    });
    await pumpWithApi(tester, api, const UsersScreen());
    await tester.tap(find.byKey(const Key('reset-u2')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('reset-password')), 'fresh-password');
    await tester.tap(find.byKey(const Key('reset-save')));
    await tester.pumpAndSettle();
    expect(api.where('PATCH /users/u2').single.data,
        {'password': 'fresh-password'});
  });

  testWidgets('delete asks first and warns about data', (tester) async {
    final api = FakeApi({
      'GET /users': _users,
      'DELETE /users/u2': const NoContent(),
    });
    await pumpWithApi(tester, api, const UsersScreen());
    await tester.tap(find.byKey(const Key('delete-u2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('All data of this user is deleted'),
        findsOneWidget);
    expect(api.where('DELETE /users/u2'), isEmpty);
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();
    expect(api.where('DELETE /users/u2'), hasLength(1));
  });

  testWidgets('shows the error when the server refuses', (tester) async {
    final api = FakeApi({
      'GET /users': _users,
      'DELETE /users/u1': const ApiFailure(
          409, 'You cannot delete the last admin.', 'not_allowed'),
    });
    await pumpWithApi(tester, api, const UsersScreen());
    await tester.tap(find.byKey(const Key('delete-u1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('error-banner')), findsOneWidget);
    expect(find.text('You cannot delete the last admin.'), findsOneWidget);
  });
}
