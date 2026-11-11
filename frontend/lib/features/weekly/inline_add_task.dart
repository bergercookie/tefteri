/// A one-line field that adds a task under a milestone in the task app.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'weekly_models.dart';
import 'weekly_widgets.dart';

/// Adds a task to [project]. The task is created in the task app and is not
/// part of the plan until it has a day. The text stays when the call fails.
class InlineAddTask extends StatefulWidget {
  /// Creates the field.
  const InlineAddTask(
      {required this.project, required this.actions, super.key});

  /// The milestone that gets the task.
  final WeeklyProject project;

  /// What the field can ask the screen to do.
  final WeeklyActions actions;

  @override
  State<InlineAddTask> createState() => _InlineAddTaskState();
}

class _InlineAddTaskState extends State<InlineAddTask> {
  final _title = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final title = _title.text.trim();
    if (title.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final message = await widget.actions.tryRun(
        (api) => api.addTask(widget.actions.week, widget.project.id, title));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
      if (message == null) _title.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.project.id;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: Key('add-task-field-$id'),
                controller: _title,
                enabled: !_busy,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Add a task to "${widget.project.name}"',
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            FilledButton.tonal(
              key: Key('add-task-$id'),
              onPressed: _busy ? null : _add,
              child: const Text('Add task'),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(_error!,
                key: Key('add-task-error-$id'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.error)),
          ),
      ],
    );
  }
}
