/// Pop-ups with the details of a task or of a calendar event.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/open_url.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import 'picker_field.dart';
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
  final _titleCtl = TextEditingController();
  final _descriptionCtl = TextEditingController();

  /// The task as the server last sent it; the edits are measured against it.
  PlanTask? _base;
  DateTime? _date;
  TimeOfDay? _time;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    if (t != null) _load(t);
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _descriptionCtl.dispose();
    super.dispose();
  }

  /// The day and the start time of [t]: from its calendar block when it has
  /// one, else its due date as an all-day task.
  static (DateTime?, TimeOfDay?) _dayOf(PlanTask t) {
    final s = t.scheduledStart?.toLocal();
    if (s != null) {
      return (
        DateTime(s.year, s.month, s.day),
        TimeOfDay(hour: s.hour, minute: s.minute)
      );
    }
    final d = t.dueAt?.toLocal();
    if (d != null) return (DateTime(d.year, d.month, d.day), null);
    return (null, null);
  }

  /// Fills the form from [t].
  void _load(PlanTask t) {
    _base = t;
    _titleCtl.text = t.title;
    _descriptionCtl.text = t.description ?? '';
    final (date, time) = _dayOf(t);
    _date = date;
    _time = time;
  }

  bool get _textChanged =>
      _base != null &&
      (_titleCtl.text.trim() != _base!.title ||
          _descriptionCtl.text != (_base!.description ?? ''));

  bool get _dayChanged {
    if (_base == null) return false;
    final (d, t) = _dayOf(_base!);
    return d != _date || t != _time;
  }

  bool get _dirty => _textChanged || _dayChanged;

  bool get _canSave => _dirty && _titleCtl.text.trim().isNotEmpty && !_busy;

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

  /// Writes the edits to the task app: the text first, then the day.
  Future<void> _save() async {
    final base = _base!;
    final title = _titleCtl.text.trim();
    final description = _descriptionCtl.text;
    final textChanged = _textChanged;
    final dayChanged = _dayChanged;
    final date = _date;
    final time = _time;
    await _run((api) async {
      if (textChanged) {
        await api.updateTask(base.id, title: title, description: description);
      }
      if (dayChanged) {
        if (date == null) {
          await api.unscheduleTask(base.id);
        } else if (time == null) {
          await api.scheduleTaskOnDate(base.id, date);
        } else {
          await api.scheduleTaskAt(
              base.id,
              DateTime(
                  date.year, date.month, date.day, time.hour, time.minute));
        }
      }
    }, closeAfter: true);
  }

  Future<void> _close() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('task-discard-confirm'),
        title: const Text('Discard your changes?'),
        content: const Text('The task keeps its old values.'),
        actions: [
          TextButton(
              key: const Key('task-discard-keep'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep editing')),
          FilledButton(
              key: const Key('task-discard-yes'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Discard')),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
        context: context,
        initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0));
    if (picked != null && mounted) setState(() => _time = picked);
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
    // The server's copy replaces the form, unless the user is editing.
    ref.listen(taskDetailProvider(widget.taskId), (prev, next) {
      final t = next.valueOrNull;
      if (t != null && !_dirty) setState(() => _load(t));
    });
    final task = _base ?? loaded.valueOrNull;
    if (_base == null && task != null) _load(task);
    return AlertDialog(
      key: const Key('task-details'),
      title: Row(
        children: [
          Expanded(
            child: Text(task == null ? (widget.title ?? 'Task') : 'Task',
                key: const Key('task-details-heading')),
          ),
          if (task != null) _buttons(_base!),
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
              child: _base != null
                  ? _form(_base!)
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
                      data: (_) => const SizedBox.shrink(),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('task-details-close'),
          onPressed: _busy ? null : _close,
          child: Text(_dirty ? 'Cancel' : 'Close'),
        ),
        if (_base != null)
          FilledButton(
            key: const Key('task-save'),
            onPressed: _canSave ? _save : null,
            child: const Text('Save'),
          ),
      ],
    );
  }

  Widget _form(PlanTask task) {
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('task-edit-title'),
            controller: _titleCtl,
            textInputAction: TextInputAction.next,
            style: text.titleSmall,
            decoration: InputDecoration(
              labelText: 'Title',
              errorText:
                  _titleCtl.text.trim().isEmpty ? 'The title is needed.' : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: PickerField(
                  fieldKey: const ValueKey('task-edit-date'),
                  clearKey: const Key('task-edit-date-clear'),
                  label: 'Day',
                  value: _date == null ? null : dateKey(_date!),
                  empty: 'No date',
                  onTap: _busy ? null : _pickDate,
                  onClear: _date == null || _busy
                      ? null
                      : () => setState(() {
                            _date = null;
                            _time = null;
                          }),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                flex: 4,
                child: PickerField(
                  fieldKey: const ValueKey('task-edit-time'),
                  clearKey: const Key('task-edit-time-clear'),
                  label: 'Starts at',
                  value: _time == null
                      ? null
                      : '${_time!.hour.toString().padLeft(2, '0')}:'
                          '${_time!.minute.toString().padLeft(2, '0')}',
                  empty: _date == null ? '-' : 'All day',
                  onTap: _busy || _date == null ? null : _pickTime,
                  onClear: _time == null || _busy
                      ? null
                      : () => setState(() => _time = null),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              'Without a time, the task is all day. With a time, it takes one '
              'hour, and the due date is the end of that hour.',
              key: const Key('task-edit-day-hint'),
              style: text.bodySmall,
            ),
          ),
          const SizedBox(height: Space.md),
          TextField(
            key: const Key('task-edit-description'),
            controller: _descriptionCtl,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Description',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.md),
          _Row('Status', task.done ? 'Done' : 'Open', 'status'),
          _Row('On the calendar', _onCalendar(task), 'calendar'),
          if (task.project != null) _Row('Project', task.project!, 'project'),
          if (task.labels.isNotEmpty) _LabelsRow(labels: task.labels),
          if (task.syncState == 'conflict')
            const _Row('Sync',
                'Changed in both places. Open the Conflicts screen.', 'sync'),
        ],
      ),
    );
  }

  static String _onCalendar(PlanTask task) {
    final start = task.scheduledStart?.toLocal();
    final end = task.scheduledEnd?.toLocal();
    if (start != null && end != null) {
      return '${dateKey(start)}, ${hhmm(start)} - ${hhmm(end)}';
    }
    final due = task.dueAt?.toLocal();
    if (due != null) return '${dateKey(due)}, all day';
    return 'Not on the calendar';
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
