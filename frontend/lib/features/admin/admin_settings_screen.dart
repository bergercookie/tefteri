/// The Admin settings page, for administrators only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/server_address.dart';
import '../../core/settings_list.dart';
import '../../core/shell.dart';
import '../../core/versions.dart';
import '../../theme/theme.dart';

/// Lists the pages that only an administrator can use, and the versions that
/// run. The server checks the rights too; the router only hides this page
/// from other users.
class AdminSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server =
        ref.watch(serverVersionProvider(ref.watch(serverAddressProvider)));
    final app = ref.watch(appVersionProvider);
    return AppShell(
      title: 'Admin settings',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _VersionsPanel(
            server: server.when(
              data: (v) => v,
              loading: () => 'Checking...',
              error: (_, __) => 'Unknown (cannot reach the server)',
            ),
            client: app.when(
              data: (v) => '$v',
              loading: () => 'Checking...',
              error: (_, __) => 'Unknown',
            ),
          ),
          const Expanded(
            child: SettingsList(entries: [
              SettingsEntry(
                keyName: 'users',
                icon: Icons.group,
                title: 'Users',
                subtitle: 'Add, disable and delete users, and reset passwords.',
                path: '/admin/users',
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// The version of the server and the version of the app in this window.
class _VersionsPanel extends StatelessWidget {
  const _VersionsPanel({required this.server, required this.client});

  final String server;
  final String client;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.tefteri;
    Widget row(String key, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 130, child: Text(label, style: text.bodySmall)),
              Expanded(
                  child: SelectableText(value,
                      key: Key(key), style: text.bodyMedium)),
            ],
          ),
        );
    return Container(
      key: const Key('admin-versions'),
      padding: const EdgeInsets.all(Space.lg),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: colors.rule))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Versions', style: text.titleSmall),
          const SizedBox(height: Space.xs),
          row('admin-server-version', 'Server', server),
          row('admin-client-version', 'Client app', client),
        ],
      ),
    );
  }
}
