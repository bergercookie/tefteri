/// Step 3: give the open tasks of the chosen projects a day.
library;

import 'package:flutter/material.dart';

import '../../core/project_chip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import '../week/week_screen.dart';
import 'projects_step.dart';
import 'weekly_models.dart';
import 'weekly_widgets.dart';

/// A strip of the seven days with their load, and the tasks of each project
/// with a day picker.
class TasksStep extends ConsumerWidget {
  /// Creates the step.
  const TasksStep({
    required this.state,
    required this.actions,
    required this.onBack,
    required this.onNext,
    super.key,
  });

  /// The loaded week.
  final WeeklyState state;

  /// What the step can ask the screen to do.
  final WeeklyActions actions;

  /// Goes back to choosing projects.
  final VoidCallback onBack;

  /// Goes on to the summary.
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = state.plan;
    final text = Theme.of(context).textTheme;
    if (plan == null || plan.projects.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const StepHeading(title: 'Give tasks a day'),
          const EmptyState(
            icon: Icons.folder_open_outlined,
            messageKey: Key('tasks-no-projects'),
            message: 'Choose a project first.',
          ),
          StepFooter(
              nextLabel: 'Commit the plan', onNext: null, onBack: onBack),
        ],
      );
    }
    final locked = plan.committed;
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(state.weekStart.year, state.weekStart.month,
            state.weekStart.day + i),
    ];
    final events = ref.watch(weekViewProvider(actions.week)).valueOrNull;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeading(
          title: 'Give every task a day',
          subtitle: 'Tap a day for each task. The day becomes the due date '
              'in your task app.',
        ),
        _WeekStrip(
            days: days,
            plan: plan,
            entries: events?.entries ?? const [],
            today: today),
        const SizedBox(height: Space.lg),
        SpreadRow(
          children: [
            Text(
              '${plan.plannedTasks} of ${plural(plan.openTasks, 'task')} have a day',
              key: const Key('day-progress'),
              style: text.titleSmall,
            ),
            if (plan.unscheduledTasks > 0 && !locked)
              OutlinedButton.icon(
                key: const Key('spread'),
                onPressed: () => actions.run((api) => api.spread(actions.week)),
                icon: const Icon(Icons.auto_awesome_motion_outlined, size: 18),
                label: const Text('Spread the rest evenly'),
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
        for (final p in plan.projects)
          _ProjectTasks(
              project: p,
              days: days,
              today: today,
              locked: locked,
              actions: actions),
        StepFooter(
          onBack: onBack,
          nextLabel: 'Review the plan',
          onNext: onNext,
          hint: plan.unscheduledTasks > 0
              ? '${plural(plan.unscheduledTasks, 'task')} still without a day.'
              : null,
        ),
      ],
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.days,
    required this.plan,
    required this.entries,
    required this.today,
  });

  final List<DateTime> days;
  final WeeklyPlan plan;
  final List<PlanEntry> entries;
  final DateTime today;

  int _tasks(DateTime d) => plan.projects.fold(
      0,
      (a, p) =>
          a +
          p.tasks
              .where((t) => t.plannedDay != null && _same(t.plannedDay!, d))
              .length);

  int _events(DateTime d) => entries.where((e) {
        final s = e.start?.toLocal();
        return s != null && _same(s, d);
      }).length;

  static bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final colors = context.tefteri;
    final text = Theme.of(context).textTheme;
    return Container(
      key: const Key('week-strip'),
      decoration: BoxDecoration(
        border: Border.all(color: colors.rule),
        borderRadius: BorderRadius.circular(Corner.lg),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Corner.lg),
        child: Row(
          children: [
            for (final d in days)
              Expanded(
                child: Container(
                  key: Key('strip-${dateKey(d)}'),
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  color: _same(d, today)
                      ? colors.today
                      : d.weekday >= 6
                          ? colors.weekend
                          : null,
                  child: Column(
                    children: [
                      Text(dayName(d), style: text.labelMedium),
                      Text('${d.day}', style: text.titleLarge),
                      Text('${_tasks(d)}',
                          key: Key('strip-tasks-${dateKey(d)}'),
                          style: text.labelLarge?.copyWith(color: colors.task)),
                      Text(
                          _events(d) == 0
                              ? ' '
                              : '${_events(d)} ${_events(d) == 1 ? 'event' : 'events'}',
                          key: Key('strip-events-${dateKey(d)}'),
                          style:
                              text.labelSmall?.copyWith(color: colors.event)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProjectTasks extends StatelessWidget {
  const _ProjectTasks({
    required this.project,
    required this.days,
    required this.today,
    required this.locked,
    required this.actions,
  });

  final WeeklyProject project;
  final List<DateTime> days;
  final DateTime today;
  final bool locked;
  final WeeklyActions actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ProjectCard(
      name: project.name,
      key: Key('tasks-of-${project.id}'),
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(project.name, style: text.titleMedium)),
                Text(
                  project.openTasks == 0
                      ? 'No tasks'
                      : '${project.scheduledTasks} of ${project.openTasks} have a day',
                  key: Key('project-progress-${project.id}'),
                  style: text.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            if (project.openTasks == 0)
              NoTasksNotice(project: project, actions: actions),
            for (final t in project.tasks)
              _TaskRow(
                  task: t,
                  days: days,
                  today: today,
                  locked: locked,
                  actions: actions),
          ],
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.days,
    required this.today,
    required this.locked,
    required this.actions,
  });

  final WeeklyTask task;
  final List<DateTime> days;
  final DateTime today;
  final bool locked;
  final WeeklyActions actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.tefteri;
    final stale = task.plannedDay == null && task.dueDay != null;
    return Container(
      key: Key('task-${task.id}'),
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: colors.rule))),
      child: SpreadRow(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 160, maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: text.bodyMedium),
                if (stale)
                  Text('Was due ${dayLong(task.dueDay!)}',
                      key: Key('was-due-${task.id}'), style: text.bodySmall),
              ],
            ),
          ),
          _DayPicker(
              task: task,
              days: days,
              today: today,
              locked: locked,
              actions: actions),
        ],
      ),
    );
  }
}

class _DayPicker extends StatelessWidget {
  const _DayPicker({
    required this.task,
    required this.days,
    required this.today,
    required this.locked,
    required this.actions,
  });

  final WeeklyTask task;
  final List<DateTime> days;
  final DateTime today;
  final bool locked;
  final WeeklyActions actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.tefteri;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final d in days)
          Builder(builder: (context) {
            final selected = task.plannedDay != null &&
                task.plannedDay!.year == d.year &&
                task.plannedDay!.month == d.month &&
                task.plannedDay!.day == d.day;
            final past = d.isBefore(today);
            final enabled = !locked && (!past || selected);
            return Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Semantics(
                button: true,
                selected: selected,
                label: dayLong(d),
                child: Tooltip(
                  message:
                      selected ? '${dayLong(d)} (tap to clear)' : dayLong(d),
                  child: InkWell(
                    key: Key('day-${task.id}-${dateKey(d)}'),
                    borderRadius: BorderRadius.circular(Corner.md),
                    onTap: enabled
                        ? () => actions.setDay(task.id, selected ? null : d)
                        : null,
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? colors.task : null,
                        borderRadius: BorderRadius.circular(Corner.md),
                        border: Border.all(
                            color: selected ? colors.task : colors.rule),
                      ),
                      child: Text(
                        dayName(d).substring(0, 2),
                        style: text.labelMedium?.copyWith(
                          color: selected
                              ? scheme.onPrimary
                              : enabled
                                  ? scheme.onSurface
                                  : scheme.onSurface.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}
