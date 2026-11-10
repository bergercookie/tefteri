/// The left column of the planner: filters, search and the task list.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/calendar_color.dart';
import '../../core/control_key.dart';
import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import 'details_dialogs.dart';
import 'hover_lift.dart';
import 'new_task_dialog.dart';
import 'planner_draggable.dart';
import 'planner_providers.dart';

/// Filter chips with counts, a search bar and the draggable task list.
///
/// A task block dropped on this column loses its due date (unschedule).
/// [onScheduleTask], when set, adds a "Schedule…" action to each task for
/// screens that cannot drag.
class TaskPane extends ConsumerStatefulWidget {
  /// Creates the pane.
  const TaskPane({this.onScheduleTask, super.key});

  /// Called when the user chooses "Schedule…" on a task.
  final void Function(PlanTask task)? onScheduleTask;

  @override
  ConsumerState<TaskPane> createState() => _TaskPaneState();
}

class _TaskPaneState extends ConsumerState<TaskPane> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    ControlKey.watch();
    _controller.text = ref.read(taskSearchProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200),
        () => ref.read(taskSearchProvider.notifier).state = text);
    setState(() {});
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    ref.read(taskSearchProvider.notifier).state = '';
    setState(() {});
  }

  bool get _touch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(dueFilterProvider);
    final query = ref.watch(taskSearchProvider);
    final searching = query.trim().isNotEmpty;
    final counts = ref.watch(taskCountsProvider).valueOrNull ?? const {};
    final tasks = ref.watch(plannerTasksProvider);
    final pending = ref.watch(pendingTaskProvider);
    return Column(
      key: const Key('task-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('new-task-button'),
              onPressed: () => showNewTaskDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New task'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Wrap(
            spacing: 6,
            runSpacing: 0,
            children: [
              for (final f in DueFilter.values)
                ChoiceChip(
                  key: Key('filter-${f.apiValue}'),
                  label: Text(counts[f.apiValue] == null
                      ? f.label
                      : '${f.label} (${counts[f.apiValue]})'),
                  selected: f == active && !searching,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    _clear();
                    ref.read(dueFilterProvider.notifier).state = f;
                  },
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            key: const Key('task-search'),
            controller: _controller,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search tasks',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      key: const Key('task-search-clear'),
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: _clear,
                    ),
            ),
          ),
        ),
        if (widget.onScheduleTask == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Text(
              _touch
                  ? 'Press and hold a task, then drag it onto the calendar.'
                  : 'Drag a task onto the calendar to schedule it.',
              key: const Key('drag-hint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (searching)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('Searching all open tasks',
                key: const Key('search-note'),
                style: Theme.of(context).textTheme.bodySmall),
          ),
        Expanded(
          child: DragTarget<CalendarItem>(
            onWillAcceptWithDetails: (d) => d.data.isTask,
            onAcceptWithDetails: (d) =>
                ref.read(plannerActionsProvider).unschedule(d.data.id),
            builder: (context, candidates, _) => DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: candidates.isEmpty
                      ? Colors.transparent
                      : Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
              child: tasks.when(
                loading: () => const Loading(),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(apiErrorMessage(e), key: const Key('tasks-error')),
                      TextButton(
                        key: const Key('tasks-reload'),
                        onPressed: () =>
                            ref.read(plannerActionsProvider).refresh(),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
                data: (list) => list.isEmpty
                    ? _empty(searching, query)
                    : ListView(
                        children: [
                          for (final t in list) _row(t, pending == t.id),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _empty(bool searching, String query) => EmptyState(
        messageKey: const Key('task-empty'),
        icon: searching ? Icons.search_off_outlined : Icons.edit_note_outlined,
        message:
            searching ? 'No tasks match "${query.trim()}".' : 'No tasks here.',
        action: searching
            ? TextButton(
                key: const Key('task-search-clear-empty'),
                onPressed: _clear,
                child: const Text('Clear search'),
              )
            : null,
      );

  Widget _row(PlanTask t, bool pending) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.tefteri;
    final text = Theme.of(context).textTheme;
    final row = InkWell(
      key: Key('task-${t.id}'),
      onTap: () {
        // Ctrl and a click mark the task as done (see the calendar).
        if (ControlKey.heldRecently) {
          if (!t.done) ref.read(plannerActionsProvider).complete(t.id);
          return;
        }
        showTaskDetails(context, taskId: t.id, initial: t);
      },
      child: DecoratedBox(
        // A ruled line under every task, like the lines of a notebook page.
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.rule)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 40,
                child: Center(
                  child: Icon(
                    t.isScheduled
                        ? Icons.event_available_outlined
                        : Icons.radio_button_unchecked,
                    key: Key(t.isScheduled
                        ? 'scheduled-${t.id}'
                        : 'unscheduled-${t.id}'),
                    size: 20,
                    // A planned task has the color of its project.
                    color: t.isScheduled
                        ? (parseCalendarColor(t.projectColor) ?? colors.task)
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              // The red margin line of the page.
              VerticalDivider(
                  width: 1, color: colors.margin.withValues(alpha: 0.7)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Space.md, vertical: Space.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      Text(_due(t),
                          key: Key('task-due-${t.id}'), style: text.bodySmall),
                    ],
                  ),
                ),
              ),
              if (pending)
                const Padding(
                  padding: EdgeInsets.only(right: Space.md),
                  child: Center(
                    child: SizedBox(
                        key: Key('pending'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                )
              else if (widget.onScheduleTask != null)
                Center(
                  child: TextButton(
                    key: Key('schedule-task-${t.id}'),
                    onPressed: () => widget.onScheduleTask!(t),
                    child: const Text('Schedule…'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return PlannerDraggable<PlanTask>(
      key: Key('drag-task-${t.id}'),
      data: t,
      label: t.title,
      dimmed: pending,
      child: HoverLift(id: t.id, child: row),
    );
  }

  String _due(PlanTask t) {
    final due = t.dueAt?.toLocal();
    if (due == null) return 'No due date';
    final timed = t.scheduledStart != null;
    return timed ? 'Due ${dateKey(due)} ${hhmm(due)}' : 'Due ${dateKey(due)}';
  }
}
