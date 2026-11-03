/// "Service unavailable" presentation for a failing connection.
library;

import 'package:flutter/material.dart';

import 'connection_models.dart';

/// Shows a failing connection with its reason and the recovery actions.
///
/// The card stays visible until a later sync succeeds. Nothing is hidden
/// and no change is queued silently.
class FailureCard extends StatelessWidget {
  /// Creates a card for connection [name] with failure [reason].
  const FailureCard({
    required this.connectionId,
    required this.name,
    required this.reason,
    this.detail,
    required this.onRetry,
    required this.onReconnect,
    required this.onOpenSettings,
    super.key,
  });

  /// Id of the failing connection.
  final String connectionId;

  /// Name of the failing connection.
  final String name;

  /// Why the connection failed.
  final FailureReason reason;

  /// The underlying error, when the last sync gave one.
  final String? detail;

  /// Called when the user taps Retry.
  final VoidCallback onRetry;

  /// Called when the user taps Reconnect.
  final VoidCallback onReconnect;

  /// Called when the user taps Open settings.
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: Key('failure-$connectionId'),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$name is unavailable',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(reason.message),
            if (detail != null)
              SelectableText(
                detail!,
                key: Key('failure-detail-$connectionId'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const Text('Your changes are not synced yet. They are not lost.'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: Key('retry-$connectionId'),
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
                OutlinedButton(
                  key: Key('reconnect-$connectionId'),
                  onPressed: onReconnect,
                  child: const Text('Reconnect'),
                ),
                TextButton(
                  key: Key('open-settings-$connectionId'),
                  onPressed: onOpenSettings,
                  child: const Text('Open settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
