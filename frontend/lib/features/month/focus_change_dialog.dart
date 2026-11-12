/// Effect-first confirmation for a mid-month focus change.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Shows a server-calculated change effect before applying the change.
Future<bool> showFocusChangeDialog(
  BuildContext context, {
  required String kind,
  required Map<String, dynamic> effect,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => FocusChangeDialog(
        kind: kind,
        effect: effect,
      ),
    ) ==
    true;

/// Confirmation dialog for swap, add, remove or target changes.
class FocusChangeDialog extends StatelessWidget {
  /// Creates the effect-first dialog.
  const FocusChangeDialog({
    required this.kind,
    required this.effect,
    super.key,
  });

  /// Change kind.
  final String kind;

  /// The server's dry-run effect.
  final Map<String, dynamic> effect;

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('focus-change-dialog'),
        title: Text(switch (kind) {
          'swap' => 'Swap a theme',
          'add' => 'Add a theme',
          'remove' => 'Remove a theme',
          _ => 'Change the target',
        }),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${effect['message'] ?? 'This change affects this month only.'}',
                  key: const Key('focus-change-effect'),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (effect['finished_earlier'] is List &&
                    (effect['finished_earlier'] as List).isNotEmpty) ...[
                  const SizedBox(height: Space.sm),
                  const Text('Finished earlier in the month:'),
                  for (final item in effect['finished_earlier'] as List)
                    if (item is Map) Text('${item['name'] ?? ''}'),
                ],
                if (kind == 'swap') ...[
                  const SizedBox(height: Space.md),
                  Text(
                    'Replace is a month-end decision; swap changes this '
                    'month’s focus during the month.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: Space.md),
                Text(
                  'Weekly commitments stay as they are. You can undo this '
                  'from the change history.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('focus-change-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('focus-change-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply change'),
          ),
        ],
      );
}
