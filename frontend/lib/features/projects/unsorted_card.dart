/// A card that tells the user how many projects have no label yet and opens
/// the Projects screen. It never blocks anything.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme.dart';
import 'projects_api.dart';

/// Opens the Projects screen; does nothing without a router (tests of
/// single widgets).
void openProjects(BuildContext context) =>
    GoRouter.maybeOf(context)?.go('/projects');

/// "N projects need a label". Shows nothing while all projects are sorted or
/// the count is not known. With [quiet] it is a single line, for places where
/// the user is busy with something else, such as the weekly picker.
class UnsortedCard extends ConsumerWidget {
  /// Creates the card.
  const UnsortedCard({this.quiet = false, super.key});

  /// A single quiet line instead of a card.
  final bool quiet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(unsortedCountProvider).valueOrNull ?? 0;
    if (n == 0) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final projects = n == 1 ? '1 project has' : '$n projects have';
    if (quiet) {
      return Padding(
        key: const Key('unsorted-reminder'),
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.xs,
          children: [
            Text('$projects no label yet.', style: text.bodySmall),
            TextButton(
              key: const Key('unsorted-open'),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: Space.xs)),
              onPressed: () => openProjects(context),
              child: const Text('Label them'),
            ),
          ],
        ),
      );
    }
    return Container(
      key: const Key('unsorted-card'),
      margin: const EdgeInsets.only(bottom: Space.lg),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
        borderRadius: BorderRadius.circular(Corner.md),
      ),
      child: Wrap(
        spacing: Space.lg,
        runSpacing: Space.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$projects no label yet', style: text.titleMedium),
                const SizedBox(height: Space.xs),
                Text(
                  'Tefteri suggests a label for each one. Check them in a '
                  'minute and your planning stays tidy.',
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
          FilledButton(
            key: const Key('unsorted-open'),
            onPressed: () => openProjects(context),
            child: const Text('Review projects'),
          ),
        ],
      ),
    );
  }
}
