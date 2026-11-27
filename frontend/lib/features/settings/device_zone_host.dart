/// Tells the server the time zone of the device.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_controller.dart';
import '../../core/device_timezone.dart';
import '../../core/planning_api.dart';
import '../../core/reminder_sync.dart';
import 'planner_settings_card.dart';

/// Keeps the time zone of the user on the server the same as the one of the device: when the
/// user signs in and when the app comes back to the front (after a flight, for example).
///
/// The server decides where a day starts and at what hour a review reminder comes with this
/// zone, so a different zone shows events on the wrong day.
class DeviceZoneHost extends ConsumerStatefulWidget {
  /// Wraps [child].
  const DeviceZoneHost({required this.child, super.key});

  /// The app.
  final Widget child;

  @override
  ConsumerState<DeviceZoneHost> createState() => _DeviceZoneHostState();
}

class _DeviceZoneHostState extends ConsumerState<DeviceZoneHost>
    with WidgetsBindingObserver {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  /// Sends the zone of the device when it is not the one on the server. A failure is ignored:
  /// the next start or return to the front tries again.
  Future<void> _check() async {
    if (_busy || !mounted || !ref.read(authControllerProvider).signedIn) return;
    _busy = true;
    try {
      final zone = await ref.read(deviceTimezoneProvider)();
      if (zone == null || zone.isEmpty || !mounted) return;
      final saved = await ref.read(userSettingsProvider.future);
      if (saved.timezone == zone) return;
      await ref.read(planningApiProvider).updateSettings(timezone: zone);
      ref.invalidate(userSettingsProvider);
      // The reminders of the reviews come at an hour of the new zone.
      await ref.read(reminderSyncProvider).sync();
    } on Object {
      // Ignored on purpose.
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(
      authControllerProvider.select((s) => s.signedIn),
      (was, now) {
        if (now && was != true) _check();
      },
    );
    return widget.child;
  }
}
