/// A week against the weeks before it, in words.
library;

import 'package:flutter/material.dart';

import '../../core/planning_models.dart' show dateKey;
import '../../theme/theme.dart';
import 'trends_models.dart';

/// Lists the measures of [comparison]: each with an arrow, the word up, steady
/// or down, and the numbers. The direction is always written, never only
/// shown by a color. When there are too few earlier weeks it says so and makes
/// no claim.
class TrendLinesCard extends StatelessWidget {
  /// Creates the card.
  const TrendLinesCard({required this.comparison, this.title, super.key});

  /// What to show.
  final Comparison comparison;

  /// The heading; defaults to a line about the week.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('trend-lines'),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              title ??
                  'The week of ${dateKey(comparison.week)} against the weeks '
                      'before',
              style: text.titleMedium),
          const SizedBox(height: Space.xs),
          if (comparison.notEnough)
            Text(
              'Not enough earlier weeks yet to compare. Tefteri needs at least '
              '$minBaselineWeeks weeks with numbers before this one.',
              key: const Key('trend-not-enough'),
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            )
          else ...[
            Text(
              'Compared with the average of your ${comparison.before} earlier '
              '${comparison.before == 1 ? 'week' : 'weeks'} with numbers.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Space.sm),
            for (final line in comparison.lines) _Line(line: line),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.line});

  final TrendLine line;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (line.direction) {
      Direction.up => Icons.trending_up,
      Direction.down => Icons.trending_down,
      Direction.steady => Icons.trending_flat,
    };
    return Padding(
      key: Key('trend-line-${line.key}'),
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Semantics(
        label: '${line.sentence} ${line.direction.word}.',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: Space.sm),
            SizedBox(
              width: 52,
              child: Text(line.direction.word.toUpperCase(),
                  key: Key('trend-direction-${line.key}'),
                  style: text.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700, letterSpacing: .6)),
            ),
            Expanded(child: Text(line.sentence, style: text.bodyMedium)),
          ],
        ),
      ),
    );
  }
}
