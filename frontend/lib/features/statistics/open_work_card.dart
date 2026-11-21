/// The card that shows what is still to do in a week, in the three work
/// categories.
library;

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../core/project_chip.dart';
import '../../theme/theme.dart';
import '../settings/sync_controller.dart';
import '../weekly/weekly_widgets.dart';
import 'category_counts_row.dart';
import 'category_style.dart';
import 'proportion_bar.dart';
import 'statistics_models.dart';
import 'statistics_providers.dart';
import 'task_status_button.dart';

/// The twin of the completed work card, for the tasks of the week of [day]
/// that are not done yet: three counts, one bar, and under them the tasks of
/// each category. A task is in the week when its due date or its planned start
/// is. The categories use the labels and the weekly commitment as they are
/// now.
///
/// A group folds away with its header; a tap on a count or on a segment of the
/// bar opens that group.
class OpenWorkCard extends ConsumerStatefulWidget {
  /// Creates the card for the week that holds [day].
  const OpenWorkCard({required this.day, this.onChanged, super.key});

  /// Any day inside the week.
  final DateTime day;

  /// Called after a task was marked done, so that the page reads the week
  /// again.
  final VoidCallback? onChanged;

  @override
  ConsumerState<OpenWorkCard> createState() => _OpenWorkCardState();
}

class _OpenWorkCardState extends ConsumerState<OpenWorkCard> {
  final Set<Category> _folded = {};
  String? _error;

  /// Marks the task done in the task app. A failed write shows the message of
  /// the server and changes nothing.
  Future<void> _complete(OpenTask task) async {
    try {
      await ref.read(planningApiProvider).completeTask(task.id);
    } on DioException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
      return;
    }
    if (!mounted) return;
    setState(() => _error = null);
    ref.invalidate(openTasksProvider);
    ref.invalidate(statisticsProvider);
    widget.onChanged?.call();
  }

  void _open(Category c) => setState(() => _folded.remove(c));

  void _toggle(Category c) =>
      setState(() => _folded.contains(c) ? _folded.remove(c) : _folded.add(c));

  @override
  Widget build(BuildContext context) {
    final key = periodDayKey('week', widget.day);
    // A sync that ends may have found new tasks: read the list again.
    ref.listen<SyncState>(syncControllerProvider, (prev, next) {
      if (prev != null && prev.busy && !next.busy) {
        ref.invalidate(openTasksProvider);
      }
    });
    final async = ref.watch(openTasksProvider(key));
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('open-work-card'),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Still to do', style: text.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            'Tasks due or planned this week that are not done yet.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.md),
          async.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(Space.xl), child: Loading()),
            error: (e, _) => Column(
              key: const Key('open-work-error'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tefteri could not load the tasks still to do.'),
                Text(apiErrorMessage(e),
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                TextButton(
                  key: const Key('open-work-retry'),
                  onPressed: () => ref.invalidate(openTasksProvider(key)),
                  child: const Text('Try again'),
                ),
              ],
            ),
            data: (s) => _body(context, s),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, OpenTasksSummary s) {
    final text = Theme.of(context).textTheme;
    final quiet = text.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    if (!s.available) {
      return Text(
        'Tefteri cannot read your weekly plan right now, so it shows no '
        'numbers instead of guessing them.',
        key: const Key('open-work-unavailable'),
        style: quiet,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CategoryCountsRow(
          counts: s.counts,
          percentages: s.percentages,
          onSelect: _open,
        ),
        const SizedBox(height: Space.md),
        ProportionBar(
          counts: s.counts,
          percentages: s.percentages,
          legend: false,
          onSelect: _open,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(_error!,
                key: const Key('open-work-action-error'),
                style: text.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: Space.sm),
        Text(
          s.total == 0
              ? 'Nothing is left to do this week.'
              : '${plural(s.total, 'task')} still to do',
          key: const Key('open-work-total'),
          style: quiet,
        ),
        if (s.hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              s.hidden == 1
                  ? '1 task in an ignored project is not counted'
                  : '${s.hidden} tasks in ignored projects are not counted',
              style: quiet,
            ),
          ),
        for (final c in Category.work)
          _Group(
            category: c,
            tasks: s.of(c),
            folded: _folded.contains(c),
            onToggle: () => _toggle(c),
            onComplete: _complete,
          ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.category,
    required this.tasks,
    required this.folded,
    required this.onToggle,
    required this.onComplete,
  });

  final Category category;
  final List<OpenTask> tasks;
  final bool folded;
  final VoidCallback onToggle;
  final void Function(OpenTask) onComplete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final empty = tasks.isEmpty;
    return Padding(
      key: Key('open-group-${category.json}'),
      padding: const EdgeInsets.only(top: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: Key('open-group-toggle-${category.json}'),
            onTap: empty ? null : onToggle,
            borderRadius: BorderRadius.circular(Corner.sm),
            child: Row(
              children: [
                CategoryBadge(category: category, count: tasks.length),
                const Spacer(),
                if (!empty)
                  Icon(folded ? Icons.expand_more : Icons.expand_less,
                      semanticLabel: folded ? 'Show tasks' : 'Hide tasks'),
              ],
            ),
          ),
          const SizedBox(height: Space.xs),
          if (empty)
            Text('Nothing left here.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))
          else if (!folded)
            for (final t in tasks)
              _TaskRow(task: t, onComplete: () => onComplete(t)),
          const Divider(height: Space.lg),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.onComplete});

  final OpenTask task;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final due = task.dueAt?.toLocal();
    return Padding(
      key: Key('open-task-${task.id}'),
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TaskStatusButton(
            key: Key('open-complete-${task.id}'),
            done: false,
            category: task.category,
            onPressed: onComplete,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: text.bodyMedium),
                if (task.project != null && task.project!.isNotEmpty)
                  ProjectChip(name: task.project!, color: task.projectColor),
              ],
            ),
          ),
          if (due != null) ...[
            const SizedBox(width: Space.sm),
            Text(dateKey(due),
                style:
                    text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
