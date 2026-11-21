/// Settings card: bring the hints back.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme.dart';
import '../projects/term_hint.dart';

/// Explains that each hint shows only once, and has a button that shows all of
/// them once again, on every device of the user.
class HintsCard extends ConsumerWidget {
  /// Creates the card.
  const HintsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('hints-card'),
      margin: const EdgeInsets.only(top: Space.lg),
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hints', style: text.titleMedium),
            const SizedBox(height: Space.xs),
            Text(
              'Tefteri explains new words in a box the first time that you '
              'see them. Each box shows only once. You can show all of them '
              'again, for example to read them once more or to show them to '
              'someone new.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Space.md),
            OutlinedButton.icon(
              key: const Key('reset-hints'),
              icon: const Icon(Icons.lightbulb_outline),
              label: const Text('Show the hints again'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await ref.read(closedHintsProvider.notifier).reset();
                messenger.showSnackBar(const SnackBar(
                  key: Key('hints-reset-note'),
                  content: Text('The hints will show again, one time each.'),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }
}
