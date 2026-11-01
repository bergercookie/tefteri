/// Dialog that splits a goal into child goals and tasks.
library;

import 'package:flutter/material.dart';

import '../../core/planning_models.dart';
import '../settings/connection_models.dart';
import 'periods.dart';

/// What the user chose in a [BreakdownDialog].
class BreakdownRequest {
  /// Creates a request.
  const BreakdownRequest({required this.goals, required this.tasks});

  /// Child goals to create.
  final List<GoalDraft> goals;

  /// Tasks to create and link to the goal.
  final List<TaskDraft> tasks;
}

class _GoalRow {
  _GoalRow(this.choice);

  final TextEditingController title = TextEditingController();
  PeriodChoice choice;
}

/// Lets the user list child goals and tasks for [goal]. Pops a
/// [BreakdownRequest], or null when the user cancels.
class BreakdownDialog extends StatefulWidget {
  /// Creates the dialog. [connections] are the task apps for new tasks.
  const BreakdownDialog(
      {required this.goal, required this.connections, super.key});

  /// The goal to break down.
  final PlanGoal goal;

  /// Task connections that can own new tasks.
  final List<Connection> connections;

  @override
  State<BreakdownDialog> createState() => _BreakdownDialogState();
}

class _BreakdownDialogState extends State<BreakdownDialog> {
  late final List<PeriodChoice> _choices = childPeriods(widget.goal);
  final List<_GoalRow> _goals = [];
  final List<TextEditingController> _tasks = [];
  late String? _connectionId = widget.connections.firstOrNull?.id;

  @override
  void dispose() {
    for (final g in _goals) {
      g.title.dispose();
    }
    for (final t in _tasks) {
      t.dispose();
    }
    super.dispose();
  }

  void _confirm() {
    final goals = [
      for (final g in _goals)
        if (g.title.text.trim().isNotEmpty)
          GoalDraft(
              title: g.title.text.trim(),
              periodType: g.choice.type,
              periodStart: g.choice.start),
    ];
    final id = _connectionId;
    final tasks = [
      for (final t in _tasks)
        if (id != null && t.text.trim().isNotEmpty)
          TaskDraft(connectionId: id, title: t.text.trim()),
    ];
    Navigator.of(context).pop(BreakdownRequest(goals: goals, tasks: tasks));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Break down: ${widget.goal.title}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Child goals',
                  style: Theme.of(context).textTheme.titleSmall),
              if (_choices.isEmpty)
                const Text('A week goal has no child goals.',
                    key: Key('breakdown-no-child-goals')),
              for (var i = 0; i < _goals.length; i++)
                Row(children: [
                  Expanded(
                    child: TextField(
                      key: Key('breakdown-goal-title-$i'),
                      controller: _goals[i].title,
                      decoration: const InputDecoration(hintText: 'Goal'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<PeriodChoice>(
                    key: Key('breakdown-goal-period-$i'),
                    value: _goals[i].choice,
                    items: [
                      for (final c in _choices)
                        DropdownMenuItem(value: c, child: Text(c.label)),
                    ],
                    onChanged: (v) => setState(
                        () => _goals[i].choice = v ?? _goals[i].choice),
                  ),
                ]),
              if (_choices.isNotEmpty)
                TextButton(
                  key: const Key('breakdown-add-goal'),
                  onPressed: () =>
                      setState(() => _goals.add(_GoalRow(_choices.first))),
                  child: const Text('Add goal'),
                ),
              const SizedBox(height: 8),
              Text('Tasks', style: Theme.of(context).textTheme.titleSmall),
              if (widget.connections.isEmpty)
                const Text('No task app is connected.',
                    key: Key('breakdown-no-connection')),
              if (widget.connections.isNotEmpty && _tasks.isNotEmpty)
                DropdownButton<String>(
                  key: const Key('breakdown-connection'),
                  value: _connectionId,
                  items: [
                    for (final c in widget.connections)
                      DropdownMenuItem(value: c.id, child: Text(c.displayName)),
                  ],
                  onChanged: (v) => setState(() => _connectionId = v),
                ),
              for (var i = 0; i < _tasks.length; i++)
                TextField(
                  key: Key('breakdown-task-title-$i'),
                  controller: _tasks[i],
                  decoration: const InputDecoration(hintText: 'Task'),
                ),
              if (widget.connections.isNotEmpty)
                TextButton(
                  key: const Key('breakdown-add-task'),
                  onPressed: () =>
                      setState(() => _tasks.add(TextEditingController())),
                  child: const Text('Add task'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('breakdown-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('breakdown-confirm'),
          onPressed: _confirm,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
