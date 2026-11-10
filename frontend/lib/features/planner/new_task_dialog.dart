/// The pop-up that creates a task: title, project, day and labels.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import 'new_task_providers.dart';
import 'picker_field.dart';
import 'planner_providers.dart';

/// Opens the pop-up that creates a task.
///
/// With [start] the pop-up begins with that day, and with that time unless
/// [allDay] is true: the user clicked an empty slot of the calendar.
Future<void> showNewTaskDialog(BuildContext context,
        {DateTime? start, bool allDay = false}) =>
    showDialog<void>(
      context: context,
      builder: (_) => NewTaskDialog(start: start, allDay: allDay),
    );

const double _dialogWidth = 440;

/// A suggestion for the label field: a label that exists, or the text that the
/// user typed as a new one.
class _LabelOption {
  const _LabelOption(this.name, {this.isNew = false});

  final String name;
  final bool isNew;
}

/// Creates a task in a project of a connected task app.
///
/// The project and the labels are chosen from suggestions that narrow while
/// the user types. A label that does not exist yet is created. A day without
/// a time makes an all-day task; with a time, the task is a block of one hour
/// that starts then, as everywhere in the planner.
class NewTaskDialog extends ConsumerStatefulWidget {
  /// Creates the pop-up. [start] gives the first day and time; with [allDay]
  /// the task has no time.
  const NewTaskDialog({this.start, this.allDay = false, super.key});

  /// The day (and time) to begin with, or null for none.
  final DateTime? start;

  /// The task begins with a day and no time.
  final bool allDay;

  @override
  ConsumerState<NewTaskDialog> createState() => _NewTaskDialogState();
}

class _NewTaskDialogState extends ConsumerState<NewTaskDialog> {
  final _title = TextEditingController();
  final _projectField = TextEditingController();
  final _projectFocus = FocusNode();
  final _labelField = TextEditingController();
  final _labelFocus = FocusNode();
  TaskProject? _project;
  bool _projectChosen = false;
  // The suggestion that Enter takes, in the list under each field.
  int _projectHighlight = 0;
  int _labelHighlight = 0;
  DateTime? _date;
  TimeOfDay? _time;
  final List<String> _labels = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final start = widget.start;
    if (start != null) {
      _date = DateTime(start.year, start.month, start.day);
      if (!widget.allDay) _time = TimeOfDay.fromDateTime(start);
    }
    // The lists show while a field has the focus.
    _projectFocus.addListener(() => setState(() {}));
    _labelFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _projectField.dispose();
    _projectFocus.dispose();
    _labelField.dispose();
    _labelFocus.dispose();
    super.dispose();
  }

  bool get _canCreate =>
      !_busy && _title.text.trim().isNotEmpty && _project != null;

  /// The project that the field starts with: the last one used, else the first.
  TaskProject? _defaultProject(List<TaskProject> all) {
    final last = ref.read(lastProjectProvider);
    for (final p in all) {
      if (p.containerId == last) return p;
    }
    return all.firstOrNull;
  }

  String _label(TaskProject p, List<TaskProject> all) =>
      all.map((x) => x.connectionId).toSet().length > 1
          ? '${p.path} (${p.connectionName})'
          : p.path;

  void _addLabel(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return;
    if (_labels.any((l) => l.toLowerCase() == clean.toLowerCase())) return;
    setState(() => _labels.add(clean));
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

  Future<void> _create() async {
    if (!_canCreate) return;
    // Text left in the label field counts as a label: it would be lost.
    _addLabel(_labelField.text);
    final project = _project!;
    final title = _title.text.trim();
    final date = _date;
    final time = _time;
    final labels = [..._labels];
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final api = ref.read(planningApiProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    PlanTask task;
    try {
      task = await api.createTask(
        connectionId: project.connectionId,
        containerId: project.containerId,
        title: title,
        labels: labels,
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
    // The task exists now. A day that cannot be set is reported, not retried
    // here: the dialog closes, and the task can be planned like any other.
    String? dayProblem;
    if (date != null) {
      try {
        if (time == null) {
          await api.scheduleTaskOnDate(task.id, date);
        } else {
          await api.scheduleTaskAt(
              task.id,
              DateTime(
                  date.year, date.month, date.day, time.hour, time.minute));
        }
      } on Object catch (e) {
        dayProblem = apiErrorMessage(e);
      }
    }
    ref.read(lastProjectProvider.notifier).state = project.containerId;
    ref.read(plannerActionsProvider).refresh();
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      key: const Key('new-task-created'),
      content: Text(dayProblem == null
          ? 'Created "$title" in ${project.path}.'
          : 'Created "$title", but its day could not be set: $dayProblem'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(taskProjectsProvider);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _create,
      },
      child: AlertDialog(
        key: const Key('new-task-dialog'),
        title: const Text('New task'),
        content: SizedBox(
          width: _dialogWidth,
          child: projects.when(
            loading: () => const SizedBox(
                height: 80, child: Center(child: CircularProgressIndicator())),
            error: (e, _) =>
                Text(apiErrorMessage(e), key: const Key('new-task-load-error')),
            data: (all) => all.isEmpty ? _noApp() : _form(all),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('new-task-cancel'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('new-task-create'),
            onPressed: _canCreate ? _create : null,
            child: const Text('Create task'),
          ),
        ],
      ),
    );
  }

  Widget _noApp() => Text(
        'No project to put a task in. Connect your task app in Settings, '
        'and sync.',
        key: const Key('new-task-no-projects'),
        style: Theme.of(context).textTheme.bodyMedium,
      );

  Widget _form(List<TaskProject> all) {
    final text = Theme.of(context).textTheme;
    if (!_projectChosen) {
      // The first time: start with the last project used.
      _projectChosen = true;
      _project = _defaultProject(all);
      _projectField.text = _project == null ? '' : _label(_project!, all);
    }
    final labels = ref.watch(
        taskLabelsProvider(_project?.connectionId ?? all.first.connectionId));
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Text(_error!,
                  key: const Key('new-task-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          TextField(
            key: const Key('new-task-title'),
            controller: _title,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Title'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.md),
          _projectPicker(all),
          const SizedBox(height: Space.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: PickerField(
                  fieldKey: const ValueKey('new-task-date'),
                  clearKey: const Key('new-task-date-clear'),
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
                  fieldKey: const ValueKey('new-task-time'),
                  clearKey: const Key('new-task-time-clear'),
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
          const SizedBox(height: Space.md),
          Text('Labels', style: text.labelMedium),
          const SizedBox(height: Space.xs),
          if (_labels.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: Wrap(
                key: const Key('new-task-labels'),
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final l in _labels)
                    InputChip(
                      key: Key('new-task-label-$l'),
                      label: Text(l),
                      visualDensity: VisualDensity.compact,
                      onDeleted: _busy
                          ? null
                          : () => setState(() => _labels.remove(l)),
                    ),
                ],
              ),
            ),
          _labelPicker(labels.valueOrNull ?? const []),
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              'Pick a label from the list, or type a new one. A new label is '
              'created in your task app.',
              style: text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  /// The projects that match what is typed. After a choice, the field holds the
  /// project's name, and then the list shows every project again.
  List<TaskProject> _projectMatches(List<TaskProject> all) {
    final text = _projectField.text.trim().toLowerCase();
    final showAll = text.isEmpty ||
        (_project != null && _projectField.text == _label(_project!, all));
    return showAll
        ? all
        : [
            for (final p in all)
              if (_label(p, all).toLowerCase().contains(text)) p,
          ];
  }

  void _chooseProject(TaskProject p, List<TaskProject> all) {
    setState(() {
      _project = p;
      _projectField.text = _label(p, all);
      _projectHighlight = 0;
    });
    _projectFocus.unfocus();
  }

  /// Arrow keys move through a list of suggestions, Esc closes it.
  KeyEventResult _listKeys(KeyEvent e,
      {required int count,
      required int Function() current,
      required void Function(int) move,
      VoidCallback? close}) {
    if (e is! KeyDownEvent || count == 0) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => move((current() + 1) % count));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => move((current() - 1 + count) % count));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape && close != null) {
      close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _projectPicker(List<TaskProject> all) {
    final matches = _projectMatches(all);
    final bad = _project == null && _projectField.text.trim().isNotEmpty;
    final open = _projectFocus.hasFocus && matches.isNotEmpty;
    final highlight =
        _projectHighlight.clamp(0, matches.isEmpty ? 0 : matches.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          onKeyEvent: (_, e) => _listKeys(e,
              count: matches.length,
              current: () => _projectHighlight,
              move: (i) => _projectHighlight = i,
              close: _projectFocus.unfocus),
          child: TextField(
            key: const Key('new-task-project'),
            controller: _projectField,
            focusNode: _projectFocus,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Project',
              errorText: bad ? 'Choose a project from the list.' : null,
              suffixIcon: const Icon(Icons.arrow_drop_down),
            ),
            onChanged: (_) => setState(() {
              // Typing again takes the choice back, until a project is picked.
              _project = null;
              _projectHighlight = 0;
            }),
            onSubmitted: (_) {
              if (matches.isNotEmpty) _chooseProject(matches[highlight], all);
            },
          ),
        ),
        if (open)
          _Suggestions<TaskProject>(
            options: matches,
            highlighted: highlight,
            keyFor: (p) => Key('project-option-${p.containerId}'),
            textFor: (p) => _label(p, all),
            onSelected: (p) => _chooseProject(p, all),
          ),
      ],
    );
  }

  /// The labels that match what is typed, then the typed text as a new label.
  List<_LabelOption> _labelMatches(List<String> existing) {
    final q = _labelField.text.trim();
    if (q.isEmpty) return const [];
    final taken = _labels.map((l) => l.toLowerCase()).toSet();
    final matches = [
      for (final l in existing)
        if (l.toLowerCase().contains(q.toLowerCase()) &&
            !taken.contains(l.toLowerCase()))
          _LabelOption(l),
    ];
    final exact = existing.any((l) => l.toLowerCase() == q.toLowerCase()) ||
        taken.contains(q.toLowerCase());
    // The typed text comes last, as a new label, so that Enter takes the first
    // label that matches what was typed.
    return [...matches, if (!exact) _LabelOption(q, isNew: true)];
  }

  void _chooseLabel(_LabelOption o) {
    _addLabel(o.name);
    setState(() => _labelHighlight = 0);
    _labelField.clear();
    _labelFocus.requestFocus();
  }

  Widget _labelPicker(List<String> existing) {
    final matches = _labelMatches(existing);
    final highlight =
        _labelHighlight.clamp(0, matches.isEmpty ? 0 : matches.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          onKeyEvent: (_, e) => _listKeys(e,
              count: matches.length,
              current: () => _labelHighlight,
              move: (i) => _labelHighlight = i,
              close: _labelField.clear),
          child: TextField(
            key: const Key('new-task-label-field'),
            controller: _labelField,
            focusNode: _labelFocus,
            enabled: !_busy,
            decoration: const InputDecoration(
              hintText: 'Add a label',
              prefixIcon: Icon(Icons.sell_outlined),
            ),
            onChanged: (_) => setState(() => _labelHighlight = 0),
            onSubmitted: (_) {
              if (matches.isNotEmpty) _chooseLabel(matches[highlight]);
            },
          ),
        ),
        if (_labelFocus.hasFocus && matches.isNotEmpty)
          _Suggestions<_LabelOption>(
            options: matches,
            highlighted: highlight,
            keyFor: (o) => Key('label-option-${o.name}'),
            textFor: (o) => o.isNew ? 'Create "${o.name}"' : o.name,
            onSelected: _chooseLabel,
          ),
      ],
    );
  }
}

/// A list of suggestions right under a field, in the style of the app. It is
/// part of the layout and not an overlay, so it works the same in a dialog on a
/// phone and in a browser.
class _Suggestions<T extends Object> extends StatelessWidget {
  const _Suggestions({
    required this.options,
    required this.highlighted,
    required this.keyFor,
    required this.textFor,
    required this.onSelected,
  });

  final List<T> options;
  final int highlighted;
  final Key Function(T) keyFor;
  final String Function(T) textFor;
  final void Function(T) onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: Space.xs),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(Corner.md),
        border: Border.all(color: context.tefteri.rule),
      ),
      constraints: const BoxConstraints(maxHeight: 180),
      child: ListView(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        children: [
          for (final (i, o) in options.indexed)
            InkWell(
              key: keyFor(o),
              onTap: () => onSelected(o),
              child: Container(
                color: i == highlighted ? scheme.surfaceContainer : null,
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.md, vertical: Space.sm),
                child: Text(textFor(o),
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            ),
        ],
      ),
    );
  }
}
