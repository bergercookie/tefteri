/// Pop-ups with the details of a task or of a calendar event.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/event_input.dart';
import '../../core/html_description.dart';
import '../../core/open_url.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../core/reminder_text.dart';
import '../../theme/theme.dart';
import '../settings/planner_settings_card.dart' show userSettingsProvider;
import 'picker_field.dart';
import 'planner_providers.dart';
import 'shared_events.dart';

/// Loads one task from the server, by id.
final taskDetailProvider = FutureProvider.family<PlanTask, String>(
    (ref, id) => ref.watch(planningApiProvider).task(id));

/// Loads the reminder of one task from its task app, by task id.
final taskReminderProvider = FutureProvider.autoDispose
    .family<TaskReminder, String>(
        (ref, id) => ref.watch(planningApiProvider).taskReminder(id));

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

  /// The user opened the text of an HTML description to change it.
  bool _editingHtml = false;
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

  /// An HTML description (Vikunja keeps rich text as HTML) shows formatted,
  /// with the raw text behind a button, as long as the user does not edit it.
  /// It follows the description as the server sent it, not what is typed, so
  /// the view does not change while the user types.
  bool get _showFormatted =>
      !_editingHtml && _base != null && looksLikeHtml(_base!.description ?? '');

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

  /// Changes the reminder in the task app, then reads it again.
  Future<void> _changeReminder(
      Future<void> Function(PlanningApi api) action) async {
    await _run(action);
    ref.invalidate(taskReminderProvider(widget.taskId));
  }

  /// The reminder of the task: a button to add one, or what it is and a
  /// button to remove it. Nothing when the task app has no reminders.
  Widget _reminder(PlanTask task) {
    final reminder = ref.watch(taskReminderProvider(widget.taskId)).valueOrNull;
    if (reminder == null || !reminder.supported) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final minutes = reminder.minutesBefore;
    // A reminder is set against the saved due time, so the day must be saved.
    final canAdd = task.scheduledStart != null && !_dayChanged && !_busy;
    final standard = ref.watch(userSettingsProvider).valueOrNull;
    final offset = standard?.defaultReminderMinutes ?? defaultReminderOffset;
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: minutes == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton.icon(
                  key: const Key('task-reminder-add'),
                  icon: const Icon(Icons.notifications_none),
                  label: Text('Remind me ${reminderOffsetText(offset)}'),
                  onPressed: canAdd
                      ? () => _changeReminder((api) =>
                          api.setTaskReminder(widget.taskId).then((_) {}))
                      : null,
                ),
                if (task.scheduledStart == null || _dayChanged)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(
                      'Give the task a day and a time, and save it, to add '
                      'a reminder in Vikunja.',
                      key: const Key('task-reminder-hint'),
                      style: text.bodySmall,
                    ),
                  ),
              ],
            )
          : Row(
              children: [
                Icon(Icons.notifications_active_outlined,
                    color: context.tefteri.task),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    minutes == 0
                        ? 'Reminder at the due time'
                        : 'Reminder ${reminderOffsetText(minutes)} the due time',
                    key: const Key('task-reminder-text'),
                  ),
                ),
                TextButton(
                  key: const Key('task-reminder-remove'),
                  onPressed: _busy
                      ? null
                      : () => _changeReminder(
                          (api) => api.clearTaskReminder(widget.taskId)),
                  child: const Text('Remove'),
                ),
              ],
            ),
    );
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
          _reminder(task),
          const SizedBox(height: Space.md),
          if (_showFormatted) ...[
            Text('Description', style: text.labelMedium),
            const SizedBox(height: Space.xs),
            HtmlDescription(
              key: const Key('task-edit-description-formatted'),
              html: _descriptionCtl.text,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('task-edit-description-edit'),
                onPressed:
                    _busy ? null : () => setState(() => _editingHtml = true),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit the text'),
              ),
            ),
          ] else ...[
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
            if (looksLikeHtml(_descriptionCtl.text)) ...[
              const SizedBox(height: Space.sm),
              Text('Formatted', style: text.labelMedium),
              const SizedBox(height: Space.xs),
              HtmlDescription(
                key: const Key('task-edit-description-formatted'),
                html: _descriptionCtl.text,
              ),
            ],
            if (_editingHtml)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('task-edit-description-view'),
                  onPressed: () => setState(() => _editingHtml = false),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Show it formatted'),
                ),
              ),
          ],
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

/// The details of one calendar event, which the user can change.
///
/// The title, the day, the start time, the length, the place and the
/// description are fields. The day, the start and the length are typed in the
/// same plain forms as in the pop-up for a new event (`20261102`, `1105`,
/// `1h30`), in 24 hours. An all-day event keeps its time: only its text can
/// change. The fields of an event in a calendar that is read-only cannot be
/// changed.
class EventDetailsDialog extends ConsumerStatefulWidget {
  /// Creates the pop-up.
  const EventDetailsDialog({required this.event, super.key});

  /// The event.
  final CalendarItem event;

  @override
  ConsumerState<EventDetailsDialog> createState() => _EventDetailsDialogState();
}

class _EventDetailsDialogState extends ConsumerState<EventDetailsDialog> {
  late final CalendarItem _event = widget.event;
  late final DateTime _start = (_event.start ?? DateTime.now()).toLocal();
  late final Duration _length = _event.end == null
      ? const Duration(hours: 1)
      : _event.end!.toLocal().difference(_start);

  late final _title = TextEditingController(text: _event.title);
  late final _day = TextEditingController(text: formatDay(_start));
  late final _time =
      TextEditingController(text: formatTime(TimeOfDay.fromDateTime(_start)));
  late final _lengthCtl = TextEditingController(
      text: formatEventLength(_length.inMinutes > 0 ? _length : Duration.zero));
  late final _location = TextEditingController(text: _event.location ?? '');
  late final _description =
      TextEditingController(text: _event.description ?? '');

  /// The user opened the text of an HTML description to change it.
  bool _editingHtml = false;
  bool _busy = false;
  String? _error;

  bool get _editable => !_event.readOnly;
  bool get _timed => !_event.allDay && _event.start != null;

  @override
  void dispose() {
    for (final c in [
      _title,
      _day,
      _time,
      _lengthCtl,
      _location,
      _description
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime? get _dayValue => parseDay(_day.text);
  TimeOfDay? get _timeValue => parseTime(_time.text);
  Duration? get _lengthValue => parseEventLength(_lengthCtl.text);

  bool get _timeOk =>
      !_timed ||
      (_dayValue != null && _timeValue != null && _lengthValue != null);

  /// The new start, or null while the day or the time is not valid.
  DateTime? get _newStart {
    final d = _dayValue;
    final t = _timeValue;
    return d == null || t == null
        ? null
        : DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  bool get _timeChanged {
    if (!_timed) return false;
    final s = _newStart;
    final l = _lengthValue;
    return s != _start || (l != null && l != _length);
  }

  bool get _textChanged =>
      _title.text.trim() != _event.title ||
      _location.text.trim() != (_event.location ?? '') ||
      _description.text != (_event.description ?? '');

  bool get _canSave =>
      _editable &&
      !_busy &&
      _title.text.trim().isNotEmpty &&
      _timeOk &&
      (_textChanged || _timeChanged);

  bool get _showFormatted =>
      !_editingHtml &&
      _editable &&
      looksLikeHtml(_event.description ?? '') &&
      _description.text == (_event.description ?? '');

  void _set(TextEditingController c, String text) => c.value = TextEditingValue(
      text: text, selection: TextSelection.collapsed(offset: text.length));

  /// A full `YYYYMMDDTHHmm` in the day or the time field sets both.
  void _typed(String text) {
    final p = parseDayAndTime(text);
    if (p != null && p.time != null) {
      _set(_day, formatDay(p.day));
      _set(_time, formatTime(p.time!));
    }
    setState(() {});
  }

  void _tidy(TextEditingController c, String? Function() standard) {
    final text = standard();
    if (text != null && text != c.text) _set(c, text);
    if (mounted) setState(() {});
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dayValue ?? _start,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _set(_day, formatDay(picked)));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeValue ?? TimeOfDay.fromDateTime(_start),
      // Times are 24 hours everywhere in tefteri: no AM or PM.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _set(_time, formatTime(picked)));
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final navigator = Navigator.of(context);
    final actions = ref.read(plannerActionsProvider);
    final api = ref.read(planningApiProvider);
    final start = _timeChanged ? _newStart : null;
    final end = start?.add(_lengthValue!);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.updateEntry(
        _event.id,
        title: _title.text.trim() != _event.title ? _title.text.trim() : null,
        start: start,
        end: end,
        location: _location.text.trim() != (_event.location ?? '')
            ? _location.text.trim()
            : null,
        description: _description.text != (_event.description ?? '')
            ? _description.text
            : null,
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = apiErrorMessage(e);
        });
      }
      return;
    }
    actions.refresh();
    navigator.pop();
  }

  /// A text field for typed input, with a button that opens a picker that the
  /// mouse can use. Tab skips the button.
  Widget _typedField({
    required String name,
    required TextEditingController controller,
    required String label,
    required String hint,
    required String? Function() standard,
    required bool valid,
    required String problem,
    IconData? icon,
    String? pickTooltip,
    VoidCallback? onPick,
    ValueChanged<String>? onChanged,
  }) {
    return Focus(
      // Only to hear when the field loses the focus: it is not a stop of its
      // own when the user presses Tab.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (!focused) _tidy(controller, standard);
      },
      child: TextField(
        key: Key('event-edit-$name'),
        controller: controller,
        enabled: _editable && !_busy,
        keyboardType: TextInputType.datetime,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: valid ? null : problem,
          suffixIcon: icon == null
              ? null
              : ExcludeFocus(
                  child: IconButton(
                    key: Key('event-edit-$name-pick'),
                    tooltip: pickTooltip,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(icon, size: 18),
                    onPressed: _editable && !_busy ? onPick : null,
                  ),
                ),
        ),
        onChanged: onChanged ?? (_) => setState(() {}),
        onSubmitted: (_) => _tidy(controller, standard),
      ),
    );
  }

  Widget _descriptionField(TextTheme text) {
    if (_showFormatted) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Description', style: text.labelMedium),
          const SizedBox(height: Space.xs),
          HtmlDescription(
            key: const Key('event-edit-description-formatted'),
            html: _description.text,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('event-edit-description-edit'),
              onPressed:
                  _busy ? null : () => setState(() => _editingHtml = true),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit the text'),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('event-edit-description'),
          controller: _description,
          enabled: _editable && !_busy,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Description',
            alignLabelWithHint: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (looksLikeHtml(_description.text)) ...[
          const SizedBox(height: Space.sm),
          Text('Formatted', style: text.labelMedium),
          const SizedBox(height: Space.xs),
          HtmlDescription(
            key: const Key('event-edit-description-formatted'),
            html: _description.text,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final newStart = _newStart;
    final length = _lengthValue;
    final end = _timed && newStart != null && length != null
        ? newStart.add(length)
        : null;
    const gap = SizedBox(height: Space.md);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
      },
      child: AlertDialog(
        key: const Key('event-details'),
        title: const Text('Event', key: Key('event-details-title')),
        content: SizedBox(
          width: _dialogWidth,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: Text(_error!,
                        key: const Key('event-edit-error'),
                        style: TextStyle(color: scheme.error)),
                  ),
                if (!_editable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: Text(
                      'This calendar is read-only, so the event cannot be '
                      'changed here.',
                      key: const Key('event-edit-readonly'),
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                TextField(
                  key: const Key('event-edit-title'),
                  controller: _title,
                  autofocus: _editable,
                  enabled: _editable && !_busy,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Title'),
                  onChanged: (_) => setState(() {}),
                ),
                gap,
                if (_timed) ...[
                  _typedField(
                    name: 'day',
                    controller: _day,
                    label: 'Day',
                    hint: 'YYYYMMDD',
                    standard: () {
                      final d = _dayValue;
                      return d == null ? null : formatDay(d);
                    },
                    valid: _dayValue != null,
                    problem: 'Type the day as YYYYMMDD',
                    icon: Icons.calendar_today_outlined,
                    pickTooltip: 'Pick a day',
                    onPick: _pickDate,
                    onChanged: _typed,
                  ),
                  gap,
                  _typedField(
                    name: 'start',
                    controller: _time,
                    label: 'Starts at',
                    hint: 'HHmm',
                    standard: () {
                      final t = _timeValue;
                      return t == null ? null : formatTime(t);
                    },
                    valid: _timeValue != null,
                    problem: 'Type the time as HHmm',
                    icon: Icons.schedule_outlined,
                    pickTooltip: 'Pick a time',
                    onPick: _pickTime,
                    onChanged: _typed,
                  ),
                  gap,
                  _typedField(
                    name: 'length',
                    controller: _lengthCtl,
                    label: 'Length',
                    hint: '1h30',
                    standard: () {
                      final d = _lengthValue;
                      return d == null ? null : formatEventLength(d);
                    },
                    valid: _lengthValue != null,
                    problem: 'Type minutes or hours, such as 45m or 1h30',
                  ),
                  if (end != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.xs),
                      child: Text('Ends ${formatDay(end)} ${hhmm(end)}',
                          key: const Key('event-edit-ends'),
                          style: text.bodySmall),
                    ),
                ] else
                  _Row(
                      'When',
                      _event.start == null ? '' : '${dateKey(_start)}, all day',
                      'when'),
                if (!_timed && _editable)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(
                      'The time of an all-day event cannot be changed here.',
                      key: const Key('event-edit-allday-note'),
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                gap,
                TextField(
                  key: const Key('event-edit-location'),
                  controller: _location,
                  enabled: _editable && !_busy,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Place'),
                  onChanged: (_) => setState(() {}),
                ),
                gap,
                _descriptionField(text),
                gap,
                const _Row('Type', 'Calendar event', 'type'),
                if (_event.calendarNames.isNotEmpty)
                  _Row(_event.isShared ? 'Calendars' : 'Calendar',
                      calendarsLine(_event)!, 'calendar'),
                if (_event.isShared && _editable)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(
                      'This event is in more than one calendar. A change here '
                      'is made in ${_event.calendar ?? 'the first one'} only.',
                      key: const Key('event-edit-shared'),
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('event-details-close'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(_editable ? 'Cancel' : 'Close'),
          ),
          if (_editable)
            FilledButton(
              key: const Key('event-edit-save'),
              onPressed: _canSave ? _save : null,
              child: Text(_busy ? 'Saving...' : 'Save'),
            ),
        ],
      ),
    );
  }
}
