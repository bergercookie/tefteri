/// The Admin settings page, for administrators only.
library;

import 'package:flutter/material.dart';

import '../../core/settings_list.dart';
import '../../core/shell.dart';

/// Lists the pages that only an administrator can use. The server checks the
/// rights too; the router only hides this page from other users.
class AdminSettingsScreen extends StatelessWidget {
  /// Creates the screen.
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppShell(
      title: 'Admin settings',
      body: SettingsList(entries: [
        SettingsEntry(
          keyName: 'users',
          icon: Icons.group,
          title: 'Users',
          subtitle: 'Add, disable and delete users, and reset passwords.',
          path: '/admin/users',
        ),
      ]),
    );
  }
}
