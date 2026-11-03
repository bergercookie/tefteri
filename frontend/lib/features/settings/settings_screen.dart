/// The Settings page: the pages that every user can open.
library;

import 'package:flutter/material.dart';

import '../../core/settings_list.dart';
import '../../core/shell.dart';

/// Lists the settings pages of the signed-in user: Connections and Change
/// password. These pages are reached from here and not from the menu.
class SettingsScreen extends StatelessWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppShell(
      title: 'Settings',
      body: SettingsList(entries: [
        SettingsEntry(
          keyName: 'connections',
          icon: Icons.link,
          title: 'Connections',
          subtitle: 'Your task, calendar and notes apps, and sync.',
          path: '/settings/connections',
        ),
        SettingsEntry(
          keyName: 'password',
          icon: Icons.password,
          title: 'Change password',
          subtitle: 'Set a new password for your account.',
          path: '/settings/password',
        ),
      ]),
    );
  }
}
