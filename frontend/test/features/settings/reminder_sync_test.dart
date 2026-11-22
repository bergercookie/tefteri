import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/auth_controller.dart';
import 'package:tefteri/core/reminder_sync.dart';
import 'package:tefteri/core/planning_models.dart';
import 'package:tefteri/features/settings/planner_settings_card.dart';
import 'package:tefteri/features/settings/reminder_sync_host.dart';

class _Calls implements ReminderSync {
  final calls = <String>[];

  @override
  Future<void> sync() async => calls.add('sync');

  @override
  Future<void> requestPermission() async => calls.add('permission');
}

class _SignedIn extends AuthController {
  _SignedIn(super.ref, {required bool signedIn}) {
    state = AuthState(signedIn: signedIn);
  }
}

class _Auth extends AuthController {
  _Auth(super.ref) {
    state = const AuthState(signedIn: false);
  }

  void signIn() => state = const AuthState(signedIn: true);
}

UserSettings _settings({int task = 15, int event = 15}) => UserSettings(
      randomTimeOnDateDrop: false,
      defaultReminderMinutes: task,
      eventReminderMinutes: event,
    );

Future<(_Calls, ProviderContainer)> _pump(
  WidgetTester tester, {
  bool signedIn = true,
  UserSettings? settings,
}) async {
  final calls = _Calls();
  final container = ProviderContainer(overrides: [
    reminderSyncProvider.overrideWithValue(calls),
    authControllerProvider.overrideWith((ref) {
      return signedIn ? _SignedIn(ref, signedIn: true) : _Auth(ref);
    }),
    userSettingsProvider.overrideWith((ref) async => settings ?? _settings()),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: ReminderSyncHost(child: Scaffold(body: Text('app'))),
    ),
  ));
  await tester.pumpAndSettle();
  return (calls, container);
}

void main() {
  testWidgets(
      'a signed-in start asks for the permission once and sets the reminders',
      (tester) async {
    final (calls, _) = await _pump(tester);
    expect(calls.calls, ['permission', 'sync']);
  });

  testWidgets('nothing is asked while the user is signed out, then it is',
      (tester) async {
    final (calls, container) = await _pump(tester, signedIn: false);
    expect(calls.calls, isEmpty);
    (container.read(authControllerProvider.notifier) as _Auth).signIn();
    await tester.pumpAndSettle();
    expect(calls.calls, ['permission', 'sync']);
  });

  testWidgets('the reminders are set again when the app comes back',
      (tester) async {
    final (calls, _) = await _pump(tester);
    calls.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls.calls, ['sync']); // no second permission request
  });

  testWidgets('a new reminder time sets the reminders again', (tester) async {
    final (calls, container) = await _pump(tester);
    calls.calls.clear();
    container.read(userSettingsProvider); // loaded
    container.updateOverrides([
      reminderSyncProvider.overrideWithValue(calls),
      authControllerProvider
          .overrideWith((ref) => _SignedIn(ref, signedIn: true)),
      userSettingsProvider.overrideWith((ref) async => _settings(event: 30)),
    ]);
    container.invalidate(userSettingsProvider);
    await tester.pumpAndSettle();
    expect(calls.calls, ['sync']);
  });

  group('the Android bridge', () {
    final log = <String>[];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(reminderChannel, (call) async {
        log.add(call.method);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(reminderChannel, null));
    });

    test('asks the Android part to sync and for the permission', () async {
      const bridge = AndroidReminderSync();
      await bridge.sync();
      await bridge.requestPermission();
      expect(log, ['sync', 'requestPermission']);
    });

    test('a system without the Android part does not fail', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(reminderChannel, null);
      await const AndroidReminderSync().sync(); // MissingPluginException
      await const NoReminderSync().sync();
    });
  });
}
