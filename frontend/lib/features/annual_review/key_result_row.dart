/// One key result: its values, outcome, deadline line, series and themes.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'annual_review_models.dart';
import 'series_strip.dart';
import 'theme_contribution_list.dart';

/// Shows one key result of a goal.
class KeyResultRow extends StatelessWidget {
  /// Creates the row.
  const KeyResultRow({required this.keyResult, super.key});

  /// The key result.
  final ReviewKeyResult keyResult;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final quiet = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final k = keyResult;
    final result = switch (k.outcome) {
      'hit' => 'Hit',
      'missed' => 'Missed',
      'retired' => 'Retired',
      'in_progress' => 'In progress',
      _ => 'No value stored',
    };
    final deadline = switch (k.deadlineLine?.state) {
      'reached' => 'Reached by deadline',
      'not_reached' => 'Not reached by deadline',
      'open' => 'Deadline still open',
      _ => 'No value by the deadline',
    };
    final last = k.lastValue == null
        ? 'No value stored'
        : k.yesNo
            ? '${k.lastValue! >= 0.5 ? 'Yes' : 'No'} in ${k.lastMonth ?? ''}'
            : '${_number(k.lastValue!)} in ${k.lastMonth ?? ''}';
    return Container(
      key: Key('key-result-${k.id}'),
      margin: const EdgeInsets.only(top: Space.sm),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(k.metric, style: text.titleSmall)),
              const SizedBox(width: Space.sm),
              Container(
                key: const Key('key-result-outcome'),
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm, vertical: Space.xs),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(Corner.pill),
                ),
                child: Text(result, style: text.labelMedium),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
              k.yesNo
                  ? 'Yes or No. Deadline ${k.deadline}.'
                  : 'Start ${_number(k.startValue)}. Target ${_number(k.target)}. '
                      'Deadline ${k.deadline}.',
              style: quiet),
          Text(last, key: const Key('key-result-last'), style: text.bodyMedium),
          Text(deadline,
              key: const Key('deadline-line'), style: text.bodySmall),
          const SizedBox(height: Space.sm),
          SeriesStrip(points: k.series),
          if (k.peakValue != null)
            Text(
                k.yesNo
                    ? 'Peak ${k.peakValue! >= 0.5 ? 'Yes' : 'No'} in ${k.peakMonth ?? ''}.'
                    : 'Peak ${_number(k.peakValue!)} in ${k.peakMonth ?? ''}.',
                style: quiet),
          if (k.movedAfterSnapshot != null)
            Text(
                k.yesNo
                    ? 'Current answer ${k.movedAfterSnapshot! >= 0.5 ? 'Yes' : 'No'} '
                        '(not from a snapshot).'
                    : 'Current value ${_number(k.movedAfterSnapshot!)} '
                        '(not from a snapshot).',
                style: quiet),
          if (k.changes.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            for (final c in k.changes)
              Text(
                  '${c.field ?? c.kind} changed from ${c.oldValue ?? 'none'} '
                  'to ${c.newValue ?? 'none'} on ${_day(c.at)}.',
                  style: quiet),
          ],
          if (k.flags.contains('no_usable_theme')) ...[
            const SizedBox(height: Space.xs),
            Row(children: [
              Expanded(
                child: Text('No usable theme is linked.',
                    key: const Key('no-usable-theme'), style: quiet),
              ),
              TextButton(
                key: const Key('link-theme'),
                onPressed: () {},
                child: const Text('Link a theme in annual planning'),
              ),
            ]),
          ],
          if (k.themes.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            ThemeContributionList(themes: k.themes),
          ],
        ],
      ),
    );
  }
}

String _number(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

String _day(DateTime? d) => d == null
    ? ''
    : '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
