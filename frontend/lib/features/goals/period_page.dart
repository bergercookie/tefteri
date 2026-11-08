/// Shared page body for the week, month and year views.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/project_chip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/context_filter.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../core/shell.dart';
import '../../theme/theme.dart';
import '../planner/schedule_dialog.dart';
import 'goal_providers.dart';
import 'goal_widgets.dart';
import 'periods.dart';

/// Page with goals (and progress), entries and tasks of one period.
///
/// From here the user can schedule a task onto a day and time, remove its
/// time, or link it to a goal. Failed writes show the server message.
class PeriodPage extends ConsumerStatefulWidget {
  /// Creates the page. [view] is the loaded period; [onReload] must refresh
  /// it; [onShift] moves the period by `-1` or `+1`.
  const PeriodPage({
    required this.title,
    required this.label,
    required this.view,
    required this.onReload,
    required this.onShift,
    required this.onToday,
    this.banner,
    super.key,
  });

  /// App bar title.
  final String title;

  /// Text between the arrows, such as `Week of 2026-11-02`.
  final String label;

  /// The loaded period.
  final AsyncValue<PeriodView> view;

  /// Reloads the period.
  final VoidCallback onReload;

  /// Moves to the previous (`-1`) or next (`1`) period.
  final void Function(int delta) onShift;

  /// Moves to the period that holds today (the Today button).
  final VoidCallback onToday;

  /// A widget above the lists, such as the weekly planning card.
  final Widget? banner;

  @override
  ConsumerState<PeriodPage> createState() => _PeriodPageState();
}

class _PeriodPageState extends ConsumerState<PeriodPage> {
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on DioException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
      return;
    }
    if (!mounted) return;
    setState(() => _error = null);
    widget.onReload();
  }

  Future<void> _schedule(PlanTask task, PeriodView view) async {
    final days =
        daysBetween(DateTime.parse(view.start), DateTime.parse(view.end));
    if (days.isEmpty) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final base = task.scheduledStart?.toLocal() ??
        (days.any((d) => d == today) ? today : days.first);
    final initial = task.scheduledStart != null
        ? base
        : DateTime(base.year, base.month, base.day, defaultScheduleHour);
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => ScheduleDialog(days: days, initial: initial),
    );
    if (picked == null) return;
    await _run(
        () => ref.read(planningApiProvider).scheduleTaskAt(task.id, picked));
  }

  Future<void> _link(PlanTask task, List<PlanGoal> goals) async {
    final picked = await showDialog<PlanGoal>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Link to a goal'),
        children: [
          for (final g in goals)
            SimpleDialogOption(
              key: Key('link-goal-${g.id}'),
              onPressed: () => Navigator.of(context).pop(g),
              child: Text(g.title),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await _run(
        () => ref.read(planningApiProvider).linkTaskToGoal(task.id, picked.id));
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: widget.title,
      body: Column(
        children: [
          if (_error != null)
            ErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                key: const Key('today-button'),
                onPressed: widget.onToday,
                child: const Text('Today'),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('prev-period'),
                tooltip: 'Previous',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => widget.onShift(-1),
              ),
              Text(widget.label, key: const Key('period-label')),
              IconButton(
                key: const Key('next-period'),
                tooltip: 'Next',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => widget.onShift(1),
              ),
            ],
          ),
          Expanded(
            child: widget.view.when(
              loading: () => const Loading(),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(apiErrorMessage(e), key: const Key('load-error')),
                    TextButton(
                      key: const Key('reload-button'),
                      onPressed: widget.onReload,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
              data: _content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(PeriodView v) {
    final titles = {for (final g in v.goals) g.id: g.title};
    final entries = [...v.entries]..sort(
        (a, b) => (a.start ?? DateTime(0)).compareTo(b.start ?? DateTime(0)));
    final heading = Theme.of(context).textTheme.titleMedium;
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        if (widget.banner != null) ...[
          widget.banner!,
          const SizedBox(height: 8),
        ],
        Text('Goals', style: heading),
        if (v.goals.isEmpty)
          const Text('No goals for this period.', key: Key('no-goals')),
        for (final g in v.goals)
          if (v.periodType == 'year')
            _YearGoal(goal: g, onChanged: widget.onReload)
          else
            GoalTile(goal: g, onChanged: widget.onReload),
        const SizedBox(height: 8),
        if (v.periodType != 'year') ...[
          Text('Events', style: heading),
          if (entries.isEmpty) const Text('No events.', key: Key('no-events')),
          for (final e in entries)
            ListTile(
              key: Key('entry-${e.id}'),
              dense: true,
              leading: const Icon(Icons.event),
              title: Text(e.title),
              subtitle: Text(_when(e.start, e.allDay)),
              trailing: ContextMarker(itemContext: e.context),
            ),
          const SizedBox(height: 8),
        ],
        // The month and year views show goals, not single tasks.
        if (v.periodType == 'week') ...[
          Text('Tasks', style: heading),
          if (v.tasks.isEmpty) const Text('No tasks.', key: Key('no-tasks')),
          for (final t in v.tasks) _taskTile(t, v, titles),
        ],
      ],
    );
  }

  String _when(DateTime? start, bool allDay) {
    if (start == null) return 'No time';
    final l = start.toLocal();
    return allDay ? '${dateKey(l)} - All day' : '${dateKey(l)} ${hhmm(l)}';
  }

  /// A task has a day when it has a due date or a planned start.
  bool _hasDay(PlanTask t) => t.isScheduled || t.scheduledStart != null;

  Widget _taskTile(PlanTask t, PeriodView v, Map<String, String> titles) {
    final goal = t.goalId == null ? null : titles[t.goalId];
    final time = t.scheduledStart != null
        ? 'Planned ${_when(t.scheduledStart, false)}'
        : t.dueAt != null
            ? 'Planned ${_when(t.dueAt, true)}'
            : 'Not scheduled';
    return ListTile(
      key: Key('task-${t.id}'),
      dense: true,
      leading: Icon(t.done ? Icons.check_circle : Icons.task_alt),
      title: Text(t.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t.project != null && t.project!.isNotEmpty)
            ProjectChip(name: t.project!),
          Text(goal == null ? time : '$time - Goal: $goal'),
        ],
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        ContextMarker(itemContext: t.context),
        PopupMenuButton<String>(
          key: Key('task-menu-${t.id}'),
          onSelected: (value) {
            switch (value) {
              case 'schedule':
                _schedule(t, v);
              case 'unschedule':
                _run(() => ref.read(planningApiProvider).unscheduleTask(t.id));
              case 'link':
                _link(t, v.goals);
              case 'unlink':
                _run(() =>
                    ref.read(planningApiProvider).linkTaskToGoal(t.id, null));
            }
          },
          itemBuilder: (_) => [
            if (!t.done)
              PopupMenuItem(
                  value: 'schedule',
                  child: Text(_hasDay(t) ? 'Change time' : 'Schedule')),
            if (_hasDay(t))
              const PopupMenuItem(
                  value: 'unschedule', child: Text('Unschedule')),
            if (v.goals.isNotEmpty)
              const PopupMenuItem(value: 'link', child: Text('Link to goal')),
            if (t.goalId != null)
              const PopupMenuItem(value: 'unlink', child: Text('Remove goal')),
          ],
        ),
      ]),
    );
  }
}

/// An annual goal with its monthly goals below it.
class _YearGoal extends ConsumerWidget {
  const _YearGoal({required this.goal, required this.onChanged});

  final PlanGoal goal;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void changed() {
      ref.invalidate(childGoalsProvider(goal.id));
      onChanged();
    }

    final kids = ref.watch(childGoalsProvider(goal.id)).valueOrNull ?? const [];
    final sorted = [...kids]
      ..sort((a, b) => a.periodStart.compareTo(b.periodStart));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GoalTile(goal: goal, onChanged: changed),
        for (final k in sorted)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: GoalTile(goal: k, onChanged: changed),
          ),
      ],
    );
  }
}
