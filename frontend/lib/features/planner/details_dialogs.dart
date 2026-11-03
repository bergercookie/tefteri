/// Pop-ups with the details of a task or of a calendar event.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';

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

/// The details of one task. It only shows data; nothing here changes the task.
class TaskDetailsDialog extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(taskDetailProvider(taskId));
    final task = loaded.valueOrNull ?? initial;
    return AlertDialog(
      key: const Key('task-details'),
      title: Text(task?.title ?? title ?? 'Task',
          key: const Key('task-details-title')),
      content: SizedBox(
        width: _dialogWidth,
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
                      onPressed: () =>
                          ref.invalidate(taskDetailProvider(taskId)),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
                data: (t) => _TaskFields(task: t),
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
