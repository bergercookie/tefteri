/// Common scaffold with the context switch and sync button.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/settings/sync_controller.dart';
import 'auth_controller.dart';
import 'context_filter.dart';

/// App scaffold shared by all views.
class AppShell extends ConsumerWidget {
  /// Creates a shell showing [body] under [title].
  const AppShell({required this.title, required this.body, super.key});

  /// Title shown in the app bar.
  final String title;

  /// View content.
  final Widget body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(contextFilterProvider);
    final sync = ref.watch(syncControllerProvider);
    final isAdmin = ref.watch(authControllerProvider).isAdmin;
    ref.listen<SyncState>(syncControllerProvider, (prev, next) {
      if (prev == null || !prev.busy || next.busy) return;
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
            for (final (label, path) in const [
              ('Today', '/'),
              ('Calendar', '/calendar'),
              ('Week', '/week'),
              ('Month', '/month'),
              ('Year', '/year'),
              ('Goals', '/goals'),
              ('Conflicts', '/conflicts'),
              ('Connections', '/settings'),
              ('Change password', '/password'),
            ])
              ListTile(
                key: Key('nav-$path'),
                title: Text(label),
                onTap: () {
                  Navigator.of(context).pop();
                  context.go(path);
                },
              ),
            if (isAdmin)
              ListTile(
                key: const Key('nav-/users'),
                title: const Text('Users'),
                onTap: () {
                  Navigator.of(context).pop();
                  context.go('/users');
                },
              ),
          ],
        ),
      ),
      appBar: AppBar(
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
            key: const Key('sync-button'),
            tooltip: 'Sync',
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
