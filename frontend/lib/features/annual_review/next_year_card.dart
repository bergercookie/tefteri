/// The "Start next year" card. It creates nothing; it opens annual planning.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme.dart';
import 'annual_review_models.dart';

/// Shows what planning offers for the next year and opens it.
class NextYearCard extends StatelessWidget {
  /// Creates the card.
  const NextYearCard(
      {required this.nextYear, required this.storedReview, super.key});

  /// The counts.
  final NextYear nextYear;

  /// A stored period review of this year, or null.
  final StoredPeriodReview? storedReview;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final quiet = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Container(
      key: const Key('next-year-card'),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Start ${nextYear.year}', style: text.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            '${nextYear.unmetKeyResults} key results and ${nextYear.links} links '
            'are offered again. Annual planning decides what to keep.',
            key: const Key('next-year-counts'),
            style: quiet,
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            children: [
              FilledButton.icon(
                key: const Key('start-next-year'),
                onPressed: nextYear.available
                    ? () => GoRouter.maybeOf(context)?.go(
                        '/annual?year=${nextYear.year}&from_year=${nextYear.fromYear}')
                    : null,
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('Start next year'),
              ),
              if (storedReview != null)
                OutlinedButton.icon(
                  key: const Key('earlier-reviews'),
                  onPressed: () => GoRouter.maybeOf(context)
                      ?.go('/review?period=year&year=${nextYear.fromYear}'),
                  icon: const Icon(Icons.auto_stories_outlined, size: 18),
                  label: const Text('Earlier reviews of this year'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
