/// The left column of the planner: filters, search and the task list.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_models.dart';
import 'details_dialogs.dart';
import 'hover_lift.dart';
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
              isDense: true,
              hintText: 'Search tasks',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
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
                loading: () => const Center(child: CircularProgressIndicator()),
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

  Widget _empty(bool searching, String query) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              searching
                  ? 'No tasks match "${query.trim()}".'
                  : 'No tasks here.',
              key: const Key('task-empty'),
            ),
            if (searching)
              TextButton(
                key: const Key('task-search-clear-empty'),
                onPressed: _clear,
                child: const Text('Clear search'),
              ),
          ],
        ),
      );

  Widget _row(PlanTask t, bool pending) {
    final tile = ListTile(
      key: Key('task-${t.id}'),
      dense: true,
      onTap: () => showTaskDetails(context, taskId: t.id, initial: t),
      title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(_due(t), key: Key('task-due-${t.id}')),
      leading: Icon(
        t.isScheduled ? Icons.event_available : Icons.radio_button_unchecked,
        key: Key(t.isScheduled ? 'scheduled-${t.id}' : 'unscheduled-${t.id}'),
        size: 20,
      ),
      trailing: pending
          ? const SizedBox(
              key: Key('pending'),
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : widget.onScheduleTask == null
              ? null
              : TextButton(
                  key: Key('schedule-task-${t.id}'),
                  onPressed: () => widget.onScheduleTask!(t),
                  child: const Text('Schedule…'),
                ),
    );
    return PlannerDraggable<PlanTask>(
      key: Key('drag-task-${t.id}'),
      data: t,
      label: t.title,
      dimmed: pending,
      child: HoverLift(id: t.id, child: tile),
    );
  }

  String _due(PlanTask t) {
    final due = t.dueAt?.toLocal();
    if (due == null) return 'No due date';
    final timed = t.scheduledStart != null;
    return timed ? 'Due ${dateKey(due)} ${hhmm(due)}' : 'Due ${dateKey(due)}';
  }
}
