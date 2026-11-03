/// Common scaffold with the context switch and sync button.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/settings/sync_controller.dart';
import 'auth_controller.dart';
import 'context_filter.dart';
import 'shortcuts/app_shortcuts.dart';
import 'shortcuts/keymap.dart';

/// App scaffold shared by all views.
class AppShell extends ConsumerWidget {
  /// Creates a shell showing [body] under [title].
  const AppShell({
    required this.title,
    required this.body,
    this.backTo,
    super.key,
  });

  /// Title shown in the app bar.
  final String title;

  /// Router location of the parent page. When set, the app bar shows a back
  /// button next to the menu button (used by the pages under Settings and
  /// Admin settings).
  final String? backTo;

  /// View content.
  final Widget body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(contextFilterProvider);
    final sync = ref.watch(syncControllerProvider);
    final isAdmin = ref.watch(authControllerProvider).isAdmin;
    ref.listen<SyncState>(syncControllerProvider, (prev, next) {
      if (prev == null || !prev.busy || next.busy || !next.announce) return;
      final text = next.error ??
          (next.failures.isEmpty
              ? 'Sync finished.'
              : '${next.failures.length} connection(s) need attention. '
                  'Open Connections for details.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    });
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          children: [
            for (final v in appViews)
              ListTile(
                key: Key('nav-${v.path}'),
                title: Text(v.label),
                trailing: v.key == null ? null : Text(v.key!.toUpperCase()),
                onTap: () {
                  Navigator.of(context).pop();
                  context.go(v.path);
                },
              ),
            if (isAdmin)
              ListTile(
                key: const Key('nav-/admin'),
                title: const Text('Admin settings'),
                onTap: () {
                  Navigator.of(context).pop();
                  context.go('/admin');
                },
              ),
            const Divider(),
            ListTile(
              key: const Key('sign-out'),
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () {
                Navigator.of(context).pop();
                ref.read(authControllerProvider.notifier).logout();
              },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        leadingWidth: backTo == null ? null : 104,
        leading: backTo == null ? null : _BackAndMenu(backTo: backTo!),
        title: Text(title),
        actions: [
          SegmentedButton<ContextFilter>(
            segments: [
              for (final f in ContextFilter.values)
                ButtonSegment(value: f, label: Text(f.name)),
            ],
            selected: {filter},
            onSelectionChanged: (s) =>
                ref.read(contextFilterProvider.notifier).state = s.first,
          ),
          IconButton(
            key: const Key('shortcuts-button'),
            tooltip: 'Keyboard shortcuts (?)',
            icon: const Icon(Icons.keyboard_outlined),
            onPressed: () => showShortcutHelp(context),
          ),
          IconButton(
            key: const Key('sync-button'),
            tooltip: 'Sync (F5)',
            icon: const Icon(Icons.sync),
            onPressed: sync.busy
                ? null
                : () => ref.read(syncControllerProvider.notifier).syncAll(),
          ),
        ],
      ),
      body: body,
    );
  }
}

/// The menu button and a back button side by side, for pages below Settings
/// and Admin settings.
class _BackAndMenu extends StatelessWidget {
  const _BackAndMenu({required this.backTo});

  final String backTo;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
          IconButton(
            key: const Key('back-button'),
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go(backTo),
          ),
        ],
      );
}
