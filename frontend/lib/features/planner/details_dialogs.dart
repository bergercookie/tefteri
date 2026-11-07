/// Pop-ups with the details of a task or of a calendar event.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/open_url.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import 'planner_providers.dart';

/// Loads one task from the server, by id.
final taskDetailProvider = FutureProvider.family<PlanTask, String>(
    (ref, id) => ref.watch(planningApiProvider).task(id));

/// Opens the pop-up with the details of the task [taskId].
///
/// Pass [initial] when the caller already has the task: the pop-up shows it
/// at once and then refreshes it from the server. [title] is shown while a
/// task that the caller does not have is loading.
Future<void> showTaskDetails(BuildContext context,
        {required String taskId, PlanTask? initial, String? title}) =>
    showDialog<void>(
      context: context,
      builder: (_) =>
          TaskDetailsDialog(taskId: taskId, initial: initial, title: title),
    );

/// Opens the pop-up with the details of a calendar event.
Future<void> showEventDetails(BuildContext context, CalendarItem event) =>
    showDialog<void>(
      context: context,
      builder: (_) => EventDetailsDialog(event: event),
    );

const double _dialogWidth = 420;

/// The details of one task, with buttons at the right of the title to mark it
/// done or not done, open it in its app and delete it.
class TaskDetailsDialog extends ConsumerStatefulWidget {
  /// Creates the pop-up.
  const TaskDetailsDialog(
      {required this.taskId, this.initial, this.title, super.key});

  /// Id of the task.
  final String taskId;

  /// The task, when the caller has it already.
  final PlanTask? initial;

  /// Title to show before the task has loaded.
  final String? title;

  @override
  ConsumerState<TaskDetailsDialog> createState() => _TaskDetailsDialogState();
}

class _TaskDetailsDialogState extends ConsumerState<TaskDetailsDialog> {
  bool _busy = false;
  String? _error;

  /// Runs [action] against the server, then reloads the task and the planner.
  Future<void> _run(Future<void> Function(PlanningApi api) action,
      {bool closeAfter = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(planningApiProvider));
    } on Object catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    ref.read(plannerActionsProvider).refresh();
    if (closeAfter) {
      if (mounted) Navigator.of(context).pop();
    } else {
      ref.invalidate(taskDetailProvider(widget.taskId));
    }
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('task-delete-confirm'),
        title: const Text('Delete this task?'),
        content: const Text('It is deleted in the app that holds it too.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('task-delete-confirm-yes'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (sure == true) {
      await _run((api) => api.deleteTask(widget.taskId), closeAfter: true);
    }
  }

  Future<void> _open(String url) async {
    final opened = await ref.read(openUrlProvider)(Uri.parse(url));
    if (!opened && mounted) setState(() => _error = 'Could not open the link.');
  }

  Widget _buttons(PlanTask task) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('task-toggle-done'),
            tooltip: task.done ? 'Mark not done' : 'Mark done',
            icon: Icon(task.done ? Icons.undo : Icons.check_circle_outline),
            onPressed: _busy
                ? null
                : () => _run((api) => task.done
                    ? api.reopenTask(task.id)
                    : api.completeTask(task.id)),
          ),
          if (task.url != null)
            IconButton(
              key: const Key('task-open-app'),
              tooltip: 'Open in Vikunja',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => _open(task.url!),
            ),
          IconButton(
            key: const Key('task-delete'),
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy ? null : _delete,
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(taskDetailProvider(widget.taskId));
    final task = loaded.valueOrNull ?? widget.initial;
    return AlertDialog(
      key: const Key('task-details'),
      title: Row(
        children: [
          Expanded(
            child: Text(task?.title ?? widget.title ?? 'Task',
                key: const Key('task-details-title')),
          ),
          if (task != null) _buttons(task),
        ],
      ),
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Text(_error!,
                    key: const Key('task-action-error'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Flexible(
              child: task != null
                  ? _TaskFields(task: task)
                  : loaded.when(
                      loading: () => const SizedBox(
                          height: 80,
                          child: Center(child: CircularProgressIndicator())),
                      error: (e, _) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(apiErrorMessage(e),
                              key: const Key('task-details-error')),
                          TextButton(
                            key: const Key('task-details-retry'),
                            onPressed: () => ref
                                .invalidate(taskDetailProvider(widget.taskId)),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                      data: (t) => _TaskFields(task: t),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('task-details-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _TaskFields extends StatelessWidget {
  const _TaskFields({required this.task});

  final PlanTask task;

  String get _due {
    final due = task.dueAt?.toLocal();
    if (due == null) return 'No due date';
    return task.scheduledStart == null
        ? dateKey(due)
        : '${dateKey(due)} ${hhmm(due)}';
  }

  String get _onCalendar {
    final start = task.scheduledStart?.toLocal();
    final end = task.scheduledEnd?.toLocal();
    if (start != null && end != null) {
      return '${dateKey(start)}, ${hhmm(start)} - ${hhmm(end)}';
    }
    final due = task.dueAt?.toLocal();
    if (due != null) return '${dateKey(due)}, all day';
    return 'Not on the calendar';
  }

  String get _context {
    final effective = task.effectiveContext ?? 'work';
    final name = effective == 'life' ? 'Life' : 'Work';
    return task.context == null ? '$name (no label, follows the app)' : name;
  }

  @override
  Widget build(BuildContext context) {
    final description = task.description?.trim() ?? '';
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row('Status', task.done ? 'Done' : 'Open', 'status'),
          _Row('Due', _due, 'due'),
          _Row('On the calendar', _onCalendar, 'calendar'),
          _Row('Context', _context, 'context'),
          if (task.project != null) _Row('Project', task.project!, 'project'),
          if (task.labels.isNotEmpty) _LabelsRow(labels: task.labels),
          if (task.syncState == 'conflict')
            const _Row('Sync',
                'Changed in both places. Open the Conflicts screen.', 'sync'),
          const SizedBox(height: 12),
          Text('Description', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            description.isEmpty ? 'No description.' : description,
            key: const Key('task-details-description'),
          ),
        ],
      ),
    );
  }
}

class _LabelsRow extends StatelessWidget {
  const _LabelsRow({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text('Labels',
                  style: Theme.of(context).textTheme.labelMedium),
            ),
            Expanded(
              child: Wrap(
                key: const Key('task-details-labels'),
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [for (final l in labels) Chip(label: Text(l))],
              ),
            ),
          ],
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, this.keyName);

  final String label;
  final String value;
  final String keyName;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child:
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
            ),
            Expanded(child: Text(value, key: Key('task-details-$keyName'))),
          ],
        ),
      );
}

/// The details of one calendar event, from the data of the calendar view.
class EventDetailsDialog extends StatelessWidget {
  /// Creates the pop-up.
  const EventDetailsDialog({required this.event, super.key});

  /// The event.
  final CalendarItem event;

  String get _when {
    final start = event.start?.toLocal();
    final end = event.end?.toLocal();
    if (start == null) return '';
    if (event.allDay) return '${dateKey(start)}, all day';
    final to = end == null ? '' : ' - ${hhmm(end)}';
    return '${dateKey(start)}, ${hhmm(start)}$to';
  }

  @override
  Widget build(BuildContext context) {
    final effective = event.effectiveContext == 'life' ? 'Life' : 'Work';
    return AlertDialog(
      key: const Key('event-details'),
      title: Text(event.title, key: const Key('event-details-title')),
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row('When', _when, 'when'),
            const _Row('Type', 'Calendar event', 'type'),
            _Row(
                'Context',
                event.context == null
                    ? '$effective (no label, follows the app)'
                    : effective,
                'context'),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('event-details-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
