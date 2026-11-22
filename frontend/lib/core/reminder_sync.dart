/// Tells the Android app to set its reminders.
///
/// The server works out what to remind the user of (`GET /reminders`). The Android part of the
/// app asks for that list by itself every half hour and when the phone starts. It must also ask
/// when this app starts, when the user signs in and when the user changes a reminder setting,
/// and it needs the permission to show notifications. On the other systems nothing happens.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The channel that the Android part (`MainActivity`) listens on.
const reminderChannel = MethodChannel('dev.bergercookie.tefteri/reminders');

/// What the app asks of the reminders of the phone.
abstract class ReminderSync {
  /// Asks the server what to remind the user of, and sets the alarms.
  Future<void> sync();

  /// Asks the user to let the app show notifications (Android 13 and newer).
  Future<void> requestPermission();
}

/// Talks to the Android part. A failure is ignored: a reminder that is not set is not worth a
/// message, and the half-hourly check tries again.
class AndroidReminderSync implements ReminderSync {
  /// Creates the bridge.
  const AndroidReminderSync();

  Future<void> _call(String method) async {
    try {
      await reminderChannel.invokeMethod<Object?>(method);
    } on MissingPluginException {
      // Not running on Android (a test, for example).
    } on PlatformException catch (e) {
      debugPrint('Reminders: $method failed: ${e.message}');
    }
  }

  @override
  Future<void> sync() => _call('sync');

  @override
  Future<void> requestPermission() => _call('requestPermission');
}

/// Does nothing, on the systems that have no reminders.
class NoReminderSync implements ReminderSync {
  /// Creates the bridge.
  const NoReminderSync();

  @override
  Future<void> sync() async {}

  @override
  Future<void> requestPermission() async {}
}

/// The bridge for this system: Android only.
final reminderSyncProvider = Provider<ReminderSync>((ref) =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? const AndroidReminderSync()
        : const NoReminderSync());
