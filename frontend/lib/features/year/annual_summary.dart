/// The annual plan of a year, read only, for the year view.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../theme/theme.dart';
import '../annual/annual_controller.dart';
import '../annual/annual_models.dart';

/// The goals and key results of [year] with their progress, and a link to the
/// annual plan where they can change.
class AnnualSummary extends ConsumerWidget {
  /// Creates the summary.
  const AnnualSummary({required this.year, super.key});

  /// The planning year.
  final int year;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(annualPlanReadProvider(year));
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final link = TextButton.icon(
      key: const Key('open-annual-plan'),
      onPressed: () => GoRouter.maybeOf(context)?.go('/annual?year=$year'),
      icon: const Icon(Icons.flag_outlined, size: 18),
      label: const Text('Open the annual plan'),
    );
    return Container(
      key: const Key('annual-summary'),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Annual plan', style: text.titleLarge)),
              link,
            ],
          ),
          plan.when(
            loading: () => const SizedBox(height: 48, child: Loading()),
            error: (e, _) => Text(apiErrorMessage(e), style: text.bodySmall),
            data: (p) => p.goals.isEmpty
                ? Text('No goals for $year yet.',
                    key: const Key('annual-summary-empty'),
                    style: text.bodyMedium)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final g in p.goals) _goal(context, g)],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _goal(BuildContext context, AnnualGoal g) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: Key('summary-goal-${g.id}'),
      padding: const EdgeInsets.only(top: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(g.title, style: text.titleSmall),
          if (g.activeKeyResults.isEmpty)
            Text('No key result yet.',
                style:
                    text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          for (final k in g.activeKeyResults)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs, left: Space.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                        '${k.metric}: ${formatNumber(k.currentValue)} of '
                        '${formatNumber(k.target)}',
                        style: text.bodySmall),
                  ),
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                      key: Key('summary-progress-${k.id}'),
                      value:
                          k.progress.isFinite ? k.progress.clamp(0.0, 1.0) : 0,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  SizedBox(
                    width: 44,
                    child: Text(
                        '${((k.progress.isFinite ? k.progress : 0) * 100).round()}%',
                        textAlign: TextAlign.end,
                        style: text.labelMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
