import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/core/server_address.dart';
import 'package:tefteri/core/versions.dart';
import 'package:tefteri/features/auth/credential_form_spec.dart';
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
    // No real network: every request fails at once.
    final container = ProviderContainer(overrides: [
      dioProvider
          .overrideWithValue(Dio()..httpClientAdapter = _FailingAdapter()),
    ]);
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
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('login fields expose autofill hints to password managers',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: LoginScreen(showServer: false)),
    ));
    expect(find.byType(AutofillGroup), findsOneWidget);
    TextField field(String key) =>
        tester.widget<TextField>(find.byKey(Key(key)));
    expect(field('username').autofillHints, [AutofillHints.username]);
    expect(field('password').autofillHints, [AutofillHints.password]);
  });

  testWidgets('login screen shows the version of the typed server',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final asked = <String?>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        serverVersionProvider.overrideWith((ref, address) async {
          asked.add(address);
          return '2.1.0';
        }),
      ],
      child: const MaterialApp(home: LoginScreen(showServer: true)),
    ));
    expect(find.byKey(const Key('server-version')), findsNothing);

    await tester.enterText(find.byKey(const Key('server')), 'my.server');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(asked, ['https://my.server']);
    expect(find.text('Server version 2.1.0'), findsOneWidget);
  });

  // Regression: Bitwarden found no login form in the browser. Flutter's own
  // fields create their <input> only while focused (the other sits off screen
  // at size 0), so on the web the screen must show a real HTML form instead,
  // and what that form reports must be what gets submitted.
  group('web login form', () {
    testWidgets('replaces the Flutter fields and feeds the login',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final posted = <Object?>[];
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter =
            _FailingAdapter(onRequest: (o) => posted.add(o.data));
      late ValueChanged<String> fillUser, fillPass;
      late VoidCallback submit;
      await tester.pumpWidget(ProviderScope(
        overrides: [dioProvider.overrideWithValue(dio)],
        child: MaterialApp(
          home: LoginScreen(
            showServer: false,
            credentialForm: (context,
                {required onUser, required onPass, required onSubmit}) {
              fillUser = onUser;
              fillPass = onPass;
              submit = onSubmit;
              return const SizedBox(key: Key('fake-html-form'), height: 100);
            },
          ),
        ),
      ));
      expect(find.byKey(const Key('fake-html-form')), findsOneWidget);
      expect(find.byKey(const Key('username')), findsNothing);
      expect(find.byKey(const Key('password')), findsNothing);

      // What a password manager fills in reaches the login request.
      fillUser('alice');
      fillPass('s3cret');
      submit();
      await tester.pumpAndSettle();
      expect(posted, [
        {'username': 'alice', 'password': 's3cret'}
      ]);
    });

    test('the HTML autocomplete values are the ones password managers read',
        () {
      // The values of the HTML autocomplete attribute (WHATWG), which is
      // also what Flutter writes for the username hint.
      expect(usernameAutocomplete, AutofillHints.username);
      expect(passwordAutocomplete, 'current-password');
    });
  });
}

class _FailingAdapter implements HttpClientAdapter {
  _FailingAdapter({this.onRequest});

  final void Function(RequestOptions)? onRequest;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    onRequest?.call(options);
    throw DioException(requestOptions: options);
  }

  @override
  void close({bool force = false}) {}
}
