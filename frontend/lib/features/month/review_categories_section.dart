/// Work-category counts and the server's display-only off-plan trend.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme.dart';
import '../projects/term_hint.dart';

/// Shows counts exactly as returned in the review snapshot.
class ReviewCategoriesSection extends StatelessWidget {
  /// Creates the section.
  const ReviewCategoriesSection({
    required this.snapshot,
    required this.trend,
    this.categoriesNote,
    super.key,
  });

  /// Snapshot's work-category counts, including hidden.
  final Map<String, dynamic> snapshot;

  /// Display-only trend from the API.
  final Map<String, dynamic> trend;

  /// `no_data` when the server found no completed work.
  final String? categoriesNote;

  @override
  Widget build(BuildContext context) {
    final raw = snapshot['categories'];
    final counts = raw is Map ? raw : const {};
    final goalAligned = _count(counts['goal_aligned']);
    final maintenance = _count(counts['maintenance']);
    final offPlan = _count(counts['off_plan']);
    final hidden = _count(counts['hidden']);
    final total = goalAligned + maintenance + offPlan;
    final state = '${trend['state'] ?? 'not_enough_history'}';
    final share = trend['share'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Work categories', style: Theme.of(context).textTheme.titleLarge),
        const TermHint(
          id: 'monthly-category-terms',
          title: 'These categories',
          terms: categoryTerms,
          compact: true,
        ),
        if (total == 0 && hidden == 0 || categoriesNote == 'no_data')
          EmptyState(
            message: 'No completed work to categorize this month.',
            action: TextButton(
              onPressed: () =>
                  context.go('/month?date=${snapshot['month'] ?? ''}'),
              child: const Text('Continue to theme decisions'),
            ),
          )
        else ...[
          if (total > 0)
            _CategoryBar(
              goalAligned: goalAligned,
              maintenance: maintenance,
              offPlan: offPlan,
            ),
          _CountLine(
            label: 'Goal-aligned',
            value: goalAligned,
          ),
          _CountLine(
            label: 'Maintenance',
            value: maintenance,
          ),
          _CountLine(
            label: 'Off-plan',
            value: offPlan,
          ),
          _CountLine(
            label: 'Hidden',
            value: hidden,
          ),
        ],
        if (state == 'rising')
          Text(
            'Off-plan share is rising${share is num ? ' · ${(share * 100).round()}%' : ''}.',
            key: const Key('off-plan-trend'),
            style: Theme.of(context).textTheme.titleSmall,
          )
        else if (state == 'not_enough_history')
          Text(
            'Not enough history to compare the off-plan share.',
            key: const Key('not-enough-history'),
            style: Theme.of(context).textTheme.bodySmall,
          )
      ],
    );
  }

  int _count(Object? value) => value is num ? value.toInt() : 0;
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.goalAligned,
    required this.maintenance,
    required this.offPlan,
  });

  final int goalAligned;
  final int maintenance;
  final int offPlan;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(Corner.sm),
        child: SizedBox(
          key: const Key('review-category-bar'),
          height: Space.md,
          child: Row(children: [
            if (goalAligned > 0)
              Expanded(
                flex: goalAligned,
                child: ColoredBox(color: Theme.of(context).colorScheme.primary),
              ),
            if (maintenance > 0)
              Expanded(
                flex: maintenance,
                child: ColoredBox(color: context.tefteri.taskContainer),
              ),
            if (offPlan > 0)
              Expanded(
                flex: offPlan,
                child: ColoredBox(color: context.tefteri.task),
              ),
          ]),
        ),
      );
}

class _CountLine extends StatelessWidget {
  const _CountLine({
    required this.label,
    required this.value,
  });

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(label, key: Key('category-$label')),
            ),
            Text('$value'),
          ],
        ),
      );
}
