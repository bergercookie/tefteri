/// Connections settings screen.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/api_error.dart';
import '../../core/open_url.dart';
import '../../core/shell.dart';
import 'connection_dialog.dart';
import 'connection_models.dart';
import 'failure_card.dart';
import 'planner_settings_card.dart';
import 'sync_controller.dart';

/// Formats a sync time for display, for example `2026-11-01 09:30`.
String formatSyncTime(DateTime? time) {
  if (time == null) return 'never';
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// Lists connections with last-sync info and any failures.
class ConnectionsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ConnectionsScreen({super.key});

  @override
  ConsumerState<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends ConsumerState<ConnectionsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(syncControllerProvider.notifier).loadStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncControllerProvider);
    final connections = ref.watch(connectionsProvider);
    return AppShell(
      title: 'Connections',
      backTo: '/settings',
      body: connections.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _Message(
          'Cannot load connections. Try again.',
          action: TextButton(
            key: const Key('reload-connections'),
            onPressed: () => ref.invalidate(connectionsProvider),
            child: const Text('Retry'),
          ),
        ),
        data: (list) => _buildList(context, sync, list),
      ),
    );
  }

  Widget _buildList(
      BuildContext context, SyncState sync, List<Connection> list) {
    final byId = {for (final c in list) c.id: c};
    // A failing connection comes from the latest sync result or from the
    // status the server reports for the connection.
    final failing = <String, FailureReason>{
      for (final c in list)
        if (c.isFailing)
          c.id: c.status == 'needs_attention'
              ? FailureReason.authExpired
              : FailureReason.other,
    };
    final details = <String, String>{};
    for (final r in sync.results.values) {
      if (r.failed) {
        failing[r.connectionId] = r.effectiveReason;
        if (r.detail != null) details[r.connectionId] = r.detail!;
      } else {
        failing.remove(r.connectionId);
      }
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            FilledButton.icon(
              key: const Key('sync-all-button'),
              onPressed: sync.busy
                  ? null
                  : () => ref.read(syncControllerProvider.notifier).syncAll(),
              icon: const Icon(Icons.sync),
              label: Text(sync.busy ? 'Syncing...' : 'Sync'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              key: const Key('add-connection'),
              onPressed: _add,
              icon: const Icon(Icons.add_link),
              label: const Text('Add connection'),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text('Last sync: ${formatSyncTime(sync.lastSyncAt)}'),
            ),
          ],
        ),
        if (sync.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(sync.error!, key: const Key('sync-error')),
          ),
        const SizedBox(height: 12),
        for (final entry in failing.entries)
          if (byId[entry.key] != null || sync.results[entry.key] != null)
            FailureCard(
              connectionId: entry.key,
              name:
                  byId[entry.key]?.displayName ?? sync.results[entry.key]!.name,
              reason: entry.value,
              detail: details[entry.key],
              onRetry: () =>
                  ref.read(syncControllerProvider.notifier).retry(entry.key),
              onReconnect: () => _reconnect(byId[entry.key]),
              onOpenSettings: () {
                final c = byId[entry.key];
                if (c != null) _edit(c);
              },
            ),
        if (list.isEmpty) const _Message('No connections yet.'),
        for (final c in list)
          _ConnectionTile(
            connection: c,
            result: sync.results[c.id],
            onEdit: () => _edit(c),
            onRemove: () => _remove(c),
          ),
        const PlannerSettingsCard(),
      ],
    );
  }

  Future<void> _add() async {
    final body = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => const ConnectionDialog(),
    );
    if (body == null || !mounted) return;
    if (body['provider'] == ConnectionProvider.googleCalendar.id) {
      await _signInWithGoogle(
        'Connect Google Calendar',
        {
          'display_name': body['display_name'],
          'default_context': body['default_context'],
        },
      );
      return;
    }
    await _send('Connected ${body['display_name']}.',
        (dio) => dio.post<void>('/connections', data: body));
  }

  Future<void> _edit(Connection c) async {
    final body = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => ConnectionDialog(initial: c),
    );
    if (body == null || !mounted) return;
    await _send('Saved ${body['display_name']}.',
        (dio) => dio.patch<void>('/connections/${c.id}', data: body));
  }

  Future<void> _remove(Connection c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('remove-dialog'),
        title: Text('Remove ${c.displayName}?'),
        content: const Text('Tefteri deletes the stored token and the copies '
            'of the items. Your data stays in your app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('remove-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _send('Removed ${c.displayName}.',
        (dio) => dio.delete<void>('/connections/${c.id}'));
  }

  /// Runs [request], then reloads the list and shows [done] or the error.
  Future<void> _send(
      String done, Future<void> Function(Dio dio) request) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await request(ref.read(dioProvider));
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on DioException catch (e) {
      messenger.showSnackBar(SnackBar(
        key: const Key('connection-error'),
        content: Text(apiErrorMessage(e)),
      ));
    }
    ref.invalidate(connectionsProvider);
  }

  /// Gets a Google sign-in link from the server and offers to open it.
  Future<void> _signInWithGoogle(
      String title, Map<String, Object?> query) async {
    final messenger = ScaffoldMessenger.of(context);
    final Object? url;
    try {
      final r = await ref.read(dioProvider).get<Map<String, dynamic>>(
          '/connections/google/authorize',
          queryParameters: query);
      url = r.data?['url'];
    } on DioException catch (e) {
      messenger.showSnackBar(SnackBar(
        key: const Key('connection-error'),
        content: Text(apiErrorMessage(e)),
      ));
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: url == null
            ? const Text('The server gave no sign-in link.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sign in on the Google page. Then come back to '
                      'this screen.'),
                  const SizedBox(height: 8),
                  SelectableText('$url',
                      key: const Key('sign-in-link'),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (url != null)
            FilledButton.icon(
              key: const Key('open-sign-in'),
              // Opened from the tap itself, so the browser does not block
              // the new tab.
              onPressed: () {
                ref.read(openUrlProvider)(Uri.parse('$url'));
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open Google sign-in'),
            ),
        ],
      ),
    );
    ref.invalidate(connectionsProvider);
  }

  Future<void> _reconnect(Connection? c) async {
    if (c == null) return;
    if (c.provider == ConnectionProvider.googleCalendar.id) {
      await _signInWithGoogle('Reconnect ${c.displayName}', {
        'display_name': c.displayName,
        if (c.defaultContext != null) 'default_context': c.defaultContext,
      });
      return;
    }
    // Apps with a token: enter the new token in the edit dialog.
    await _edit(c);
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({
    required this.connection,
    required this.onEdit,
    required this.onRemove,
    this.result,
  });

  final Connection connection;
  final SyncResult? result;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final outcome = result?.outcome ?? connection.lastSyncOutcome ?? 'none';
    final at = connection.lastSyncAt;
    final url = connection.settings['base_url'];
    return ListTile(
      key: Key('connection-${connection.id}'),
      title: Text(connection.displayName),
      subtitle: Text(
        '${connection.kind} - ${connection.provider}'
        '${url == null ? '' : ' - $url'}\n'
        'Last sync: ${formatSyncTime(at)} ($outcome)',
      ),
      isThreeLine: true,
      leading: Icon(
        outcome == 'ok' ? Icons.check_circle : Icons.warning_amber,
      ),
      trailing: Wrap(children: [
        IconButton(
          key: Key('edit-${connection.id}'),
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_outlined),
          onPressed: onEdit,
        ),
        IconButton(
          key: Key('remove-${connection.id}'),
          tooltip: 'Remove',
          icon: const Icon(Icons.delete_outline),
          onPressed: onRemove,
        ),
      ]),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Text(text), if (action != null) action!],
        ),
      );
}
