import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/auth_controller.dart';
import 'package:tefteri/core/device_timezone.dart';
import 'package:tefteri/core/reminder_sync.dart';
import 'package:tefteri/features/settings/device_zone_host.dart';

import '../../support/fake_api.dart';

class _SignedIn extends AuthController {
  _SignedIn(super.ref) {
    state = const AuthState(signedIn: true);
  }
}

Map<String, Object?> _settings(String zone) => {
      'random_time_on_date_drop': false,
      'default_reminder_minutes': 15,
      'event_reminder_minutes': 15,
      'checklists': <String, Object?>{},
      'checklist_sources': <String, Object?>{},
      'event_invitees': <String>[],
      'seen_hints': <String>[],
      'timezone': zone,
    };

Future<FakeApi> _pump(WidgetTester tester,
    {required String saved, required String? device}) async {
  final api = FakeApi({
    'GET /me/settings': _settings(saved),
    'PATCH /me/settings': _settings(device ?? saved),
  });
  await pumpWithApi(
    tester,
    api,
    const DeviceZoneHost(child: Scaffold(body: Text('app'))),
    overrides: [
      authControllerProvider.overrideWith((ref) => _SignedIn(ref)),
      deviceTimezoneProvider.overrideWithValue(() async => device),
      reminderSyncProvider.overrideWithValue(const NoReminderSync()),
    ],
  );
  return api;
}

void main() {
  testWidgets('a zone that differs from the one on the server is sent',
      (tester) async {
    final api = await _pump(tester, saved: 'UTC', device: 'Europe/Athens');
    final patch = api.where('PATCH /me/settings');
    expect(patch, hasLength(1));
    expect(patch.single.data, {'timezone': 'Europe/Athens'});
  });

  testWidgets('the same zone is not sent again', (tester) async {
    final api =
        await _pump(tester, saved: 'Europe/Athens', device: 'Europe/Athens');
    expect(api.where('PATCH /me/settings'), isEmpty);
  });

  testWidgets('a device that does not tell its zone changes nothing',
      (tester) async {
    final api = await _pump(tester, saved: 'UTC', device: null);
    expect(api.where('PATCH /me/settings'), isEmpty);
  });
}
