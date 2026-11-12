/// The completed tasks of a week, in three groups.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme.dart';
import 'category_style.dart';
import 'category_task_list.dart';
import 'statistics_models.dart';
import 'statistics_providers.dart';

/// Every task completed in the week of [day], grouped by category: goal-aligned,
/// maintenance and off-plan, each with its count, its style and the project of
/// each task. A group with no task is still there, with a zero. There is no
/// cap: each group loads further pages on "Show more".
class CompletedByCategory extends ConsumerWidget {
  /// Creates the list for the week that holds [day].
  const CompletedByCategory({required this.day, super.key});

  /// A day of the week.
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = periodDayKey('week', day);
    final summary =
        ref.watch(statisticsProvider(StatsQuery('week', key))).valueOrNull;
    // The card above says why there is nothing to list.
    if (summary == null || !summary.available || summary.empty != null) {
      return const SizedBox.shrink();
    }
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: const Key('completed-by-category'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Completed this week', style: text.titleMedium),
        Text(
          'A live list: it shows the tasks as of the last sync.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        for (final c in Category.work)
          _Group(
            category: c,
            count: summary.counts.of(c),
            query: TaskListQuery(period: 'week', day: key, category: c),
          ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(
      {required this.category, required this.count, required this.query});

  final Category category;
  final int count;
  final TaskListQuery query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key('completed-group-${category.json}'),
      padding: const EdgeInsets.only(top: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: CategoryBadge(category: category, count: count),
          ),
          const SizedBox(height: Space.xs),
          if (count == 0)
            Text(
              'Nothing completed here.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            )
          else
            CategoryTaskList(query: query, showHints: false),
          // The style is on the badge; the line below keeps the groups apart.
          const Divider(height: Space.lg),
        ],
      ),
    );
  }
}
