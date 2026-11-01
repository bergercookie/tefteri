/// Conflict resolution: shows both versions and lets the user pick one.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../core/shell.dart';

/// Loads open conflicts (`GET /conflicts`). The API has no context filter
/// for conflicts, so all of them are shown.
final conflictsProvider = FutureProvider<List<SyncConflict>>(
    (ref) => ref.watch(planningApiProvider).conflicts());

/// Lists conflicts with the local and remote version side by side.
class ConflictsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ConflictsScreen({super.key});

  @override
  ConsumerState<ConflictsScreen> createState() => _ConflictsScreenState();
}

class _ConflictsScreenState extends ConsumerState<ConflictsScreen> {
  String? _error;

  Future<void> _resolve(SyncConflict c, {required bool keepLocal}) async {
    try {
      await ref
          .read(planningApiProvider)
          .resolveConflict(c.id, keepLocal: keepLocal);
    } on DioException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
      return;
    }
    if (!mounted) return;
    setState(() => _error = null);
    ref.invalidate(conflictsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final conflicts = ref.watch(conflictsProvider);
    return AppShell(
      title: 'Conflicts',
      body: Column(
        children: [
          if (_error != null)
            ErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null)),
          Expanded(
            child: conflicts.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(apiErrorMessage(e), key: const Key('load-error')),
                    TextButton(
                      key: const Key('reload-button'),
                      onPressed: () => ref.invalidate(conflictsProvider),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
              data: (list) => list.isEmpty
                  ? const Center(child: Text('No conflicts.'))
                  : ListView(
                      padding: const EdgeInsets.all(8),
                      children: [for (final c in list) _card(c)],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(SyncConflict c) {
    final keys = {...c.local.keys, ...c.remote.keys}.toList()..sort();
    return Card(
      key: Key('conflict-${c.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c.entityType}: ${c.title}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: _version('Your version', c.local, c.remote, keys,
                        Key('local-${c.id}'))),
                const SizedBox(width: 12),
                Expanded(
                    child: _version('Other app version', c.remote, c.local,
                        keys, Key('remote-${c.id}'))),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: Key('keep-local-${c.id}'),
                  onPressed: () => _resolve(c, keepLocal: true),
                  child: const Text('Keep your version'),
                ),
                OutlinedButton(
                  key: Key('keep-remote-${c.id}'),
                  onPressed: () => _resolve(c, keepLocal: false),
                  child: const Text('Keep other app version'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _version(String heading, Map<String, dynamic> mine,
      Map<String, dynamic> other, List<String> keys, Key key) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: Theme.of(context).textTheme.titleSmall),
        for (final k in keys)
          Container(
            color:
                '${mine[k]}' == '${other[k]}' ? null : scheme.tertiaryContainer,
            child: Text('$k: ${mine[k] ?? '-'}'),
          ),
      ],
    );
  }
}
