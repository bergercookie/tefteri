/// The numbers at the top of the weekly review: tasks and milestones done
/// out of committed, the pace across the week, and the focus share.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'weekly_models.dart';
import 'weekly_widgets.dart';

/// Shows how the week went in numbers. When nothing was committed it shows
/// the server's short note and no ratio. It has no goal text.
class ReviewSummaryCard extends StatelessWidget {
  /// Creates the card.
  const ReviewSummaryCard({required this.summary, super.key});

  /// The numbers of the week.
  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.tefteri;
    final s = summary;
    if (s.empty) {
      return Card(
        key: const Key('review-summary'),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Text(
            s.note ??
                'No task was committed that week, so there is nothing to '
                    'compare.',
            key: const Key('review-note'),
            style: text.bodyMedium,
          ),
        ),
      );
    }
    final focus = s.focusShare;
    return Card(
      key: const Key('review-summary'),
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: Space.xl,
              runSpacing: Space.md,
              children: [
                _Ratio(
                  key: const Key('review-tasks'),
                  done: s.doneTasks,
                  of: s.committedTasks,
                  label: s.committedTasks == 1 ? 'task done' : 'tasks done',
                  accent: colors.task,
                ),
                _Ratio(
                  key: const Key('review-milestones'),
                  done: s.milestonesDone,
                  of: s.milestonesCommitted,
                  label: s.milestonesCommitted == 1
                      ? 'milestone finished'
                      : 'milestones finished',
                  accent: colors.done,
                ),
              ],
            ),
            if (s.pace.isNotEmpty) ...[
              const SizedBox(height: Space.lg),
              Text('Done per day', style: text.titleSmall),
              const SizedBox(height: Space.xs),
              _Pace(pace: s.pace),
            ],
            if (focus != null) ...[
              const SizedBox(height: Space.md),
              Text(
                '${(focus * 100).round()}% of the tasks you finished were '
                'under this month\'s focus themes.',
                key: const Key('review-focus'),
                style: text.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Ratio extends StatelessWidget {
  const _Ratio(
      {required this.done,
      required this.of,
      required this.label,
      required this.accent,
      super.key});

  final int done;
  final int of;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(TextSpan(children: [
          TextSpan(
              text: '$done', style: text.displaySmall?.copyWith(color: accent)),
          TextSpan(text: ' of $of', style: text.titleMedium),
        ])),
        Text(label, style: text.bodySmall),
      ],
    );
  }
}

class _Pace extends StatelessWidget {
  const _Pace({required this.pace});

  final List<PaceDay> pace;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.tefteri;
    final peak = pace.fold<int>(1, (m, d) => d.done > m ? d.done : m);
    return Row(
      key: const Key('review-pace'),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final d in pace)
          Expanded(
            child: Column(
              children: [
                Text('${d.done}',
                    key:
                        Key('pace-${d.day.toIso8601String().substring(0, 10)}'),
                    style: text.labelMedium),
                const SizedBox(height: Space.xs),
                Container(
                  height: 4 + 36.0 * d.done / peak,
                  margin: const EdgeInsets.symmetric(horizontal: Space.xs),
                  decoration: BoxDecoration(
                    color: d.done == 0 ? colors.rule : colors.done,
                    borderRadius: BorderRadius.circular(Corner.sm),
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(dayName(d.day), style: text.labelSmall),
              ],
            ),
          ),
      ],
    );
  }
}
