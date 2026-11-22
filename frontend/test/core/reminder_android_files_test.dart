import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/reminder_sync.dart';

/// The reminders run in the Android part. These tests keep its files in step
/// with the app: the channel name, the permissions and the receivers.
const _android = 'android/app/src/main';
const _kotlin = '$_android/kotlin/dev/bergercookie/tefteri';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('the app and MainActivity use the same channel', () {
    expect(reminderChannel.name, 'dev.bergercookie.tefteri/reminders');
    final activity = _read('$_kotlin/MainActivity.kt');
    expect(activity, contains('"${reminderChannel.name}"'));
    for (final method in ['sync', 'requestPermission']) {
      expect(activity, contains('"$method"'));
    }
  });

  test('the manifest has the permissions and the receivers of the reminders',
      () {
    final manifest = _read('$_android/AndroidManifest.xml');
    for (final permission in [
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.SCHEDULE_EXACT_ALARM',
      'android.permission.RECEIVE_BOOT_COMPLETED',
    ]) {
      expect(manifest, contains('android:name="$permission"'));
    }
    expect(manifest, contains('android:name=".ReminderReceiver"'));
    expect(manifest, contains('android:name=".ReminderBootReceiver"'));
    expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
    expect(manifest, contains('android.intent.action.MY_PACKAGE_REPLACED'));
  });

  test('the Android part reads the list of the server and the saved login', () {
    final data = _read('$_kotlin/ReminderData.kt');
    expect(data, contains('/api/v1/reminders'));
    expect(data, contains('flutter.session_token'));
    expect(data, contains('flutter.server_address'));
    expect(File('$_android/res/drawable/ic_stat_reminder.xml').existsSync(),
        isTrue);
    expect(_read('$_android/res/values/widget_strings.xml'),
        contains('name="reminders_channel"'));
  });

  test('a tap on a notification opens a link that the app knows', () {
    final scheduler = _read('$_kotlin/ReminderScheduler.kt');
    expect(scheduler, contains('tefteri://app'));
    // The server sends links to these routes.
    final routes = _read('lib/app.dart');
    for (final path in ['/week', '/month', '/year']) {
      expect(routes, contains("path: '$path'"));
    }
  });
}
