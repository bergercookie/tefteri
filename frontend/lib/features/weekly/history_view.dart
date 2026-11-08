/// The earlier weeks: what the user committed to and what got done.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../theme/theme.dart';
import 'weekly_api.dart';
import 'weekly_models.dart';
import 'weekly_widgets.dart';

/// The sentence that tells the user how realistic their plans are.
///
/// Compares the share of committed projects that got done with two
/// thresholds. It says nothing until there are at least two weeks.
String? realismNote(WeeklyHistory h) {
  final rate = h.projectRate;
  if (rate == null || h.weeks < 2) return null;
  if (rate < 0.5) {
    return 'You tend to plan more than you finish. Try fewer projects, '
        'or fewer tasks in each.';
  }
  if (rate >= 0.9) {
    return 'You finish nearly everything you plan. You could take on a '
        'little more.';
  }
  return 'Your plans are realistic: you finish most of what you commit to.';
}

/// Lists every reviewed week, newest first, with two counters each:
/// projects committed to and projects done.
class HistoryView extends ConsumerWidget {
  /// Creates the view. [history] overrides loading (right after a review).
  const HistoryView({this.history, super.key});

  /// A history that is already loaded.
  final WeeklyHistory? history;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (history != null) return _body(context, history!);
    return ref.watch(weeklyHistoryProvider).when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.xl),
            child: Loading(),
          ),
          error: (e, _) =>
              Text(apiErrorMessage(e), key: const Key('history-error')),
          data: (h) => _body(context, h),
        );
  }

  Widget _body(BuildContext context, WeeklyHistory h) {
    final text = Theme.of(context).textTheme;
    if (h.entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        child: Text(
          'No earlier weeks yet. After this week, your look-back shows up here.',
          key: const Key('history-empty'),
          style: text.bodyMedium,
        ),
      );
    }
    final note = realismNote(h);
    return Column(
      key: const Key('history'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Over ${plural(h.weeks, 'week')}',
                    style: text.titleMedium),
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    Counter(
                        key: const Key('total-committed'),
                        label:
                            '${noun(h.committedProjects, 'project')} committed',
                        value: h.committedProjects),
                    const SizedBox(width: Space.xl),
                    Counter(
                        key: const Key('total-done'),
                        label: '${noun(h.doneProjects, 'project')} done',
                        value: h.doneProjects,
                        accent: context.tefteri.done),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Text(
                  '${plural(h.doneTasks, 'task')} done of '
                  '${h.committedTasks} planned.',
                  style: text.bodySmall,
                ),
                if (note != null) ...[
                  const SizedBox(height: Space.md),
                  Text(note,
                      key: const Key('realism-note'), style: text.bodyMedium),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.md),
        for (final e in h.entries) _EntryCard(entry: e),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final WeeklyHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.tefteri;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: Key('history-${entry.planId}'),
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(weekTitle(entry.weekStart), style: text.titleMedium),
            const SizedBox(height: Space.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Counter(
                    key: Key('committed-${entry.planId}'),
                    label: 'committed',
                    value: entry.committedProjects),
                const SizedBox(width: Space.xl),
                Counter(
                    key: Key('done-${entry.planId}'),
                    label: 'done',
                    value: entry.doneProjects,
                    accent: colors.done),
                const Spacer(),
                Text(
                    '${entry.doneTasks} of ${plural(entry.committedTasks, 'task')} done',
                    style: text.bodySmall),
              ],
            ),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              children: [
                for (final p in entry.projects)
                  Chip(
                    avatar: Icon(
                      p.done
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: p.done ? colors.done : scheme.onSurfaceVariant,
                      semanticLabel: p.done ? 'Done' : 'Not done',
                    ),
                    label: Text(p.name),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (entry.reflection.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Text('“${entry.reflection}”',
                  style:
                      text.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
            ],
          ],
        ),
      ),
    );
  }
}
