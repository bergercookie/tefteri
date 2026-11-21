/// Shared page body for the week, month and year views.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/project_chip.dart';
import '../../core/section_heading.dart';
import '../../core/work_mark.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_api.dart';
import '../../core/periods.dart';
import '../../core/planning_models.dart';
import '../../core/shell.dart';
import '../../theme/theme.dart';
import '../planner/schedule_dialog.dart';
import '../statistics/statistics_models.dart' show Category;
import '../statistics/task_status_button.dart';
import 'task_goal_picker.dart';

/// Page with, for a week, the tasks of one period. Goals belong to the annual
/// plan only; a task shows the goal it points to.
///
/// From here the user can schedule a task onto a day and time, remove its
/// time, or link it to a goal of this year's annual plan. Failed writes show
/// the server message.
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
    this.footer,
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

  /// A widget below the lists, such as the completed tasks of a week.
  final Widget? footer;

  @override
  ConsumerState<PeriodPage> createState() => _PeriodPageState();
}

class _PeriodPageState extends ConsumerState<PeriodPage> {
  String? _error;

  /// Whether done tasks show in the "All due this week" list.
  bool _showDone = true;

  /// The themes and projects of that list that the user folded away. A theme
  /// is `theme:<name>`; a project is `project:<theme>/<name>`.
  final Set<String> _folded = {};

  void _fold(String id) => setState(
      () => _folded.contains(id) ? _folded.remove(id) : _folded.add(id));

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

  Future<void> _complete(PlanTask task) =>
      _run(() => ref.read(planningApiProvider).completeTask(task.id));

  Future<void> _link(PlanTask task) async {
    final picked = await showTaskGoalPicker(context, year: DateTime.now().year);
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
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        if (widget.banner != null) ...[
          widget.banner!,
          const SizedBox(height: 8),
        ],
        // These views are about the plan, not the calendar, so they list no
        // events. Only the week lists single tasks.
        if (v.periodType == 'week') ...[
          const SectionHeading(
            title: 'All due this week',
            info: 'Every task with a due date in this week, done or not. '
                'A tick marks a done task. Use the Completed chip to show or '
                'hide the done tasks. Tasks sit under their theme and their '
                'project: choose a name to fold or unfold it. A task that you '
                'finished without a due date in this week is not here.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              key: const Key('show-done-filter'),
              label: const Text('Completed'),
              selected: _showDone,
              onSelected: (value) => setState(() => _showDone = value),
            ),
          ),
          ..._groupedTasks(v),
        ],
        if (widget.footer != null) ...[
          const SizedBox(height: 16),
          widget.footer!,
        ],
      ],
    );
  }

  /// The tasks of the week grouped by theme, then by project inside the
  /// theme. Done tasks are left out when the filter is off.
  List<Widget> _groupedTasks(PeriodView v) {
    final tasks = [
      for (final t in v.tasks)
        if (_showDone || !t.done) t,
    ];
    if (tasks.isEmpty) {
      return [
        Text(
            v.tasks.isEmpty
                ? 'No tasks are due this week.'
                : 'All tasks due this week are done. Turn on Completed to '
                    'see them.',
            key: const Key('no-tasks')),
      ];
    }
    // Themes and projects in order of first appearance, "No theme" and
    // "No project" last.
    final themes = <String?, Map<String?, List<PlanTask>>>{};
    for (final t in tasks) {
      final project =
          t.project != null && t.project!.isNotEmpty ? t.project : null;
      themes
          .putIfAbsent(t.theme, () => {})
          .putIfAbsent(project, () => [])
          .add(t);
    }
    int byName(String? a, String? b) {
      if (a == null || b == null) return a == null ? (b == null ? 0 : 1) : -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    }

    final out = <Widget>[];
    for (final theme in themes.keys.toList()..sort(byName)) {
      final projects = themes[theme]!;
      final themeId = 'theme:${theme ?? ''}';
      final themeFolded = _folded.contains(themeId);
      final themeCount =
          projects.values.fold<int>(0, (sum, list) => sum + list.length);
      out.add(_GroupHeader(
        key: Key('theme-${theme ?? 'none'}'),
        label: theme ?? 'No theme',
        count: themeCount,
        folded: themeFolded,
        level: 0,
        // Work is a property of the theme, so every task under it agrees.
        work: projects.values.any((tasks) => tasks.any((t) => t.work)),
        onTap: () => _fold(themeId),
      ));
      if (themeFolded) continue;
      for (final project in projects.keys.toList()..sort(byName)) {
        // Tasks held directly by the theme project need no subheading.
        final heading = project != null && project != theme
            ? project
            : (project == null && theme != null ? 'No project' : null);
        final projectId = 'project:${theme ?? ''}/${project ?? ''}';
        final projectFolded = heading != null && _folded.contains(projectId);
        if (heading != null) {
          out.add(_GroupHeader(
            key: Key('subproject-${theme ?? 'none'}-${project ?? 'none'}'),
            label: heading,
            count: projects[project]!.length,
            folded: projectFolded,
            level: 1,
            onTap: () => _fold(projectId),
          ));
        }
        if (projectFolded) continue;
        for (final t in projects[project]!) {
          out.add(_taskTile(t, v));
        }
      }
    }
    return out;
  }

  String _when(DateTime? start, bool allDay) {
    if (start == null) return 'No time';
    final l = start.toLocal();
    return allDay ? '${dateKey(l)} - All day' : '${dateKey(l)} ${hhmm(l)}';
  }

  /// A task has a day when it has a due date or a planned start.
  bool _hasDay(PlanTask t) => t.isScheduled || t.scheduledStart != null;

  /// Says whether the task is done and when, or that it is still pending.
  String _status(PlanTask t) {
    if (!t.done) return 'Pending - not done yet';
    final at = t.completedAt?.toLocal();
    return at == null
        ? 'Done - completion time not known'
        : 'Done ${dateKey(at)} ${hhmm(at)}';
  }

  Widget _taskTile(PlanTask t, PeriodView v) {
    final title = t.goalId == null ? null : v.goalTitles[t.goalId];
    // A goal of an old month or week plan shows as history.
    final goal = title == null
        ? null
        : title.annual
            ? 'Goal: ${title.title}'
            : 'Goal (history): ${title.title}';
    final time = t.scheduledStart != null
        ? 'Planned ${_when(t.scheduledStart, false)}'
        : t.dueAt != null
            ? 'Planned ${_when(t.dueAt, true)}'
            : 'Not scheduled';
    return ListTile(
      key: Key('task-${t.id}'),
      dense: true,
      leading: TaskStatusButton(
        key: Key(t.done ? 'task-done-${t.id}' : 'task-complete-${t.id}'),
        done: t.done,
        category: Category.tryParse(t.category),
        onPressed: () => _complete(t),
      ),
      title: Text(t.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t.project != null && t.project!.isNotEmpty)
            ProjectChip(name: t.project!, color: t.projectColor, work: t.work),
          Text(goal == null ? time : '$time - $goal'),
          Text(
            _status(t),
            key: Key('task-status-${t.id}'),
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: t.done ? context.tefteri.done : null),
          ),
        ],
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        PopupMenuButton<String>(
          key: Key('task-menu-${t.id}'),
          onSelected: (value) {
            switch (value) {
              case 'complete':
                _complete(t);
              case 'schedule':
                _schedule(t, v);
              case 'unschedule':
                _run(() => ref.read(planningApiProvider).unscheduleTask(t.id));
              case 'link':
                _link(t);
              case 'unlink':
                _run(() =>
                    ref.read(planningApiProvider).linkTaskToGoal(t.id, null));
            }
          },
          itemBuilder: (_) => [
            if (!t.done)
              const PopupMenuItem(value: 'complete', child: Text('Mark done')),
            if (!t.done)
              PopupMenuItem(
                  value: 'schedule',
                  child: Text(_hasDay(t) ? 'Change time' : 'Schedule')),
            if (_hasDay(t))
              const PopupMenuItem(
                  value: 'unschedule', child: Text('Unschedule')),
            const PopupMenuItem(value: 'link', child: Text('Link to goal')),
            if (t.goalId != null)
              const PopupMenuItem(value: 'unlink', child: Text('Remove goal')),
          ],
        ),
      ]),
    );
  }
}

/// The name of a theme or a project in the list of tasks due this week. A tap
/// folds or unfolds the tasks under it.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.label,
    required this.count,
    required this.folded,
    required this.level,
    required this.onTap,
    this.work = false,
    super.key,
  });

  final String label;

  /// The theme is work: the pill "Work" follows its name.
  final bool work;
  final int count;
  final bool folded;

  /// 0 for a theme, 1 for a project inside it.
  final int level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      expanded: !folded,
      label: '$label, $count ${count == 1 ? 'task' : 'tasks'}',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(Corner.sm),
        child: Padding(
          padding: EdgeInsets.only(
            left: level * Space.sm,
            top: level == 0 ? Space.md : Space.xs,
            bottom: Space.xs,
          ),
          child: Row(
            children: [
              Icon(folded ? Icons.chevron_right : Icons.expand_more,
                  size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: Space.xs),
              Flexible(
                child: Text(label,
                    style: level == 0 ? text.titleSmall : text.labelLarge),
              ),
              if (work) ...[
                const SizedBox(width: Space.sm),
                const WorkPill(),
              ],
              const SizedBox(width: Space.sm),
              Text('$count',
                  style:
                      text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
