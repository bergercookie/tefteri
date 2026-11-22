/// Keeps the reminders of the phone up to date while the app is open.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_controller.dart';
import '../../core/reminder_sync.dart';
import 'planner_settings_card.dart';

/// Keeps the reminders of the phone up to date while the app is open: when the user signs in,
/// when the app comes back to the front, and when a reminder setting changes.
class ReminderSyncHost extends ConsumerStatefulWidget {
  /// Wraps [child].
  const ReminderSyncHost({required this.child, super.key});

  /// The app.
  final Widget child;

  @override
  ConsumerState<ReminderSyncHost> createState() => _ReminderSyncHostState();
}

class _ReminderSyncHostState extends ConsumerState<ReminderSyncHost>
    with WidgetsBindingObserver {
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _signedIn());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _isSignedIn => ref.read(authControllerProvider).signedIn;

  /// After a sign in: ask for the permission once, then set the reminders.
  void _signedIn() {
    if (!mounted || !_isSignedIn) return;
    final bridge = ref.read(reminderSyncProvider);
    if (!_asked) {
      _asked = true;
      bridge.requestPermission();
    }
    bridge.sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isSignedIn) {
      ref.read(reminderSyncProvider).sync();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(
      authControllerProvider.select((s) => s.signedIn),
      (was, now) {
        if (now && was != true) _signedIn();
      },
    );
    // A new time for a task or an event changes when the notifications come.
    ref.listen<(int, int)?>(
      userSettingsProvider.select((s) => s.valueOrNull == null
          ? null
          : (
              s.requireValue.defaultReminderMinutes,
              s.requireValue.eventReminderMinutes
            )),
      (was, now) {
        if (was != null && now != null && was != now && _isSignedIn) {
          ref.read(reminderSyncProvider).sync();
        }
      },
    );
    return widget.child;
  }
}
