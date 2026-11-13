/// Twelve month cells with the snapshot status and an inline action.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme.dart';
import 'annual_review_models.dart';

/// Shows each month of the year and opens a missing month's review.
class MonthCoverageStrip extends StatelessWidget {
  /// Creates the strip.
  const MonthCoverageStrip({required this.months, super.key});

  /// The twelve months.
  final List<ReviewMonth> months;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      key: const Key('month-coverage'),
      spacing: Space.xs,
      runSpacing: Space.xs,
      children: [
        for (final month in months) _cell(context, month, text, scheme),
      ],
    );
  }

  Widget _cell(BuildContext context, ReviewMonth month, TextTheme text,
      ColorScheme scheme) {
    final (label, icon) = switch (month.status) {
      'stored' => ('Stored', Icons.check_circle_outline),
      'open' => ('Open', Icons.edit_outlined),
      'future' => ('Future', Icons.schedule_outlined),
      _ => ('Missing', Icons.radio_button_unchecked),
    };
    final cell = Container(
      key: Key('review-month-${month.month}'),
      width: 86,
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(month.month.substring(5), style: text.labelMedium),
          const SizedBox(height: Space.xs),
          Row(children: [
            Icon(icon, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: Space.xs),
            Flexible(child: Text(label, style: text.bodySmall)),
          ]),
        ],
      ),
    );
    if (month.action != 'open_monthly_review') return cell;
    return Semantics(
      button: true,
      label: 'Open the review of ${month.month}',
      child: InkWell(
        key: Key('open-month-${month.month}'),
        borderRadius: BorderRadius.circular(Corner.sm),
        onTap: () => GoRouter.maybeOf(context)
            ?.go('/month/review?date=${month.month}-01'),
        child: cell,
      ),
    );
  }
}
