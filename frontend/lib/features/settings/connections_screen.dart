/// Connections settings screen.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/shell.dart';
import 'connection_models.dart';
import 'failure_card.dart';
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
    for (final r in sync.results.values) {
      if (r.failed) {
        failing[r.connectionId] = r.effectiveReason;
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
            Text('Last sync: ${formatSyncTime(sync.lastSyncAt)}'),
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
              name: byId[entry.key]?.displayName ??
                  sync.results[entry.key]!.name,
              reason: entry.value,
              onRetry: () =>
                  ref.read(syncControllerProvider.notifier).retry(entry.key),
              onReconnect: () => _reconnect(entry.key, byId[entry.key]),
              onOpenSettings: () => _openSettings(entry.key, byId[entry.key]),
            ),
        if (list.isEmpty) const _Message('No connections yet.'),
        for (final c in list) _ConnectionTile(connection: c, result: sync.results[c.id]),
      ],
    );
  }

  Future<void> _reconnect(String id, Connection? c) async {
    final messenger = ScaffoldMessenger.of(context);
    if (c?.provider != 'google') {
      messenger.showSnackBar(const SnackBar(
        content: Text('Open settings and enter your new credentials.'),
      ));
      return;
    }
    try {
      final r = await ref
          .read(dioProvider)
          .get<Map<String, dynamic>>('/connections/google/authorize');
      final url = r.data?['url'] ?? r.data?['authorize_url'];
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Reconnect'),
          content: SelectableText(
            url == null
                ? 'The server gave no sign-in link.'
                : 'Open this link to sign in again:\n$url',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on DioException {
      messenger.showSnackBar(const SnackBar(
        content: Text('Cannot start sign-in. Try again later.'),
      ));
    }
  }

  void _openSettings(String id, Connection? c) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          key: Key('settings-sheet-$id'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c?.displayName ?? 'Connection',
                style: Theme.of(context).textTheme.titleLarge),
            Text('Provider: ${c?.provider ?? 'unknown'}'),
            Text('Kind: ${c?.kind ?? 'unknown'}'),
            Text('Status: ${c?.status ?? 'unknown'}'),
            Text('Default context: ${c?.defaultContext ?? 'none'}'),
            Text('Last sync: ${formatSyncTime(c?.lastSyncAt)}'),
          ],
        ),
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({required this.connection, this.result});

  final Connection connection;
  final SyncResult? result;

  @override
  Widget build(BuildContext context) {
    final outcome = result?.outcome ?? connection.lastSyncOutcome ?? 'none';
    final at = connection.lastSyncAt;
    return ListTile(
      key: Key('connection-${connection.id}'),
      title: Text(connection.displayName),
      subtitle: Text(
        '${connection.kind} - ${connection.provider}\n'
        'Last sync: ${formatSyncTime(at)} ($outcome)',
      ),
      isThreeLine: true,
      leading: Icon(
        outcome == 'ok' ? Icons.check_circle : Icons.warning_amber,
      ),
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
