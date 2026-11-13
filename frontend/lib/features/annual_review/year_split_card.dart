/// The year split as one proportion bar and twelve month rows.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../statistics/category_counts_row.dart';
import '../statistics/drilldown_screen.dart';
import '../statistics/proportion_bar.dart';
import '../statistics/statistics_models.dart' as stats;
import 'annual_review_models.dart';

/// Shows the stored year split. Its numbers never change with the live list.
class YearSplitCard extends StatelessWidget {
  /// Creates the card.
  const YearSplitCard({required this.split, required this.year, super.key});

  /// The split.
  final ReviewSplit split;

  /// The planning year.
  final int year;

  stats.CategoryCounts get _counts => stats.CategoryCounts(
      split.counts.goalAligned, split.counts.maintenance, split.counts.offPlan);

  stats.CategoryCounts get _percentages => stats.CategoryCounts(
      split.percentages.goalAligned,
      split.percentages.maintenance,
      split.percentages.offPlan);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final quiet = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    void open(stats.Category? category) =>
        openDrilldown(context, 'year', '$year-01-01', category);
    return Container(
      key: const Key('year-split'),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                  child:
                      Text('Completed work in $year', style: text.titleMedium)),
              Text('${split.monthsCovered} of 12 months', style: quiet),
            ],
          ),
          const SizedBox(height: Space.md),
          CategoryCountsRow(
            counts: _counts,
            percentages: _percentages,
            onSelect: open,
          ),
          const SizedBox(height: Space.sm),
          ProportionBar(
              counts: _counts, percentages: _percentages, onSelect: open),
          const SizedBox(height: Space.sm),
          Text('${split.total} tasks counted. ${split.hidden} hidden.',
              key: const Key('split-total'), style: quiet),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.xs,
            children: [
              OutlinedButton.icon(
                key: const Key('drill-down-open'),
                onPressed: () => open(null),
                icon: const Icon(Icons.list_alt_outlined, size: 18),
                label: const Text('Open the live list'),
              ),
              Text('Live list, may differ from the bar.', style: quiet),
            ],
          ),
          const SizedBox(height: Space.md),
          for (final month in split.months) _monthRow(context, month, quiet),
        ],
      ),
    );
  }

  Widget _monthRow(BuildContext context, SplitMonth month, TextStyle? quiet) {
    final text = Theme.of(context).textTheme;
    final counts = month.counts;
    final line = counts == null
        ? (month.notStored ? 'Not stored' : 'No snapshot')
        : '${counts.goalAligned} + ${counts.maintenance} + '
            '${counts.offPlan} tasks, ${month.hidden} hidden';
    return Padding(
      key: Key('split-month-${month.month}'),
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          SizedBox(
              width: 62,
              child: Text(month.month.substring(5), style: text.labelMedium)),
          Expanded(child: Text(line, style: quiet)),
        ],
      ),
    );
  }
}
