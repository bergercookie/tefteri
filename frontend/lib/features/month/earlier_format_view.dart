/// Read-only view for legacy goal data from an earlier Month format.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../theme/theme.dart';
import 'month_api.dart';

/// Shows legacy monthly goals without any edit or create controls.
class EarlierFormatView extends ConsumerWidget {
  /// Creates the earlier-format view.
  const EarlierFormatView({required this.month, super.key});

  /// Month key, `YYYY-MM`.
  final String month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(earlierMonthGoalsProvider(month));
    return goals.when(
      loading: () => const Loading(),
      error: (error, _) => EmptyState(
        message: apiErrorMessage(error),
        action: TextButton(
          onPressed: () => ref.invalidate(earlierMonthGoalsProvider(month)),
          child: const Text('Try again'),
        ),
      ),
      data: (items) => Container(
        key: const Key('earlier-format-view'),
        margin: const EdgeInsets.only(top: Space.lg),
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          border: Border.all(color: context.tefteri.rule),
          borderRadius: BorderRadius.circular(Corner.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Earlier format',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.xs),
            Text(
              'These month goals are read-only history. They are not part of '
              'the new monthly focus and no review snapshot is made from them.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: Space.md),
            if (items.isEmpty)
              EmptyState(
                message: 'No earlier month goals were found.',
                action: TextButton(
                  onPressed: () =>
                      ref.invalidate(earlierMonthGoalsProvider(month)),
                  child: const Text('Reload earlier goals'),
                ),
              )
            else
              for (final goal in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${goal['title'] ?? ''}',
                          style: Theme.of(context).textTheme.titleSmall),
                      if ((goal['description'] as String? ?? '').isNotEmpty)
                        Text('${goal['description']}'),
                      if ((goal['criteria'] as String? ?? '').isNotEmpty)
                        Text('${goal['criteria']}',
                            style: Theme.of(context).textTheme.bodySmall),
                      const Divider(height: Space.md),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Legacy goal data is isolated by month key.
final earlierMonthGoalsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, month) {
  return ref.watch(monthApiProvider).earlierGoals(month);
});
