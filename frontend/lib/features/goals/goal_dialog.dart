/// The pop-up of one goal: its text, its completeness criteria and its child
/// goals. Also the pop-up that adds several goals at once.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import 'goal_providers.dart';
import 'periods.dart';

/// Turns text with one goal on each line into the titles of the goals.
///
/// Blank lines go. A list marker at the start of a line (`-`, `*`, a bullet
/// or `1.`) goes too, so a list pasted from a note works as it is.
List<String> parseGoalLines(String text) {
  final marker = RegExp(r'^\s*(?:[-*•]|\d+[.)])\s+');
  return [
    for (final line in text.split(RegExp(r'\r?\n')))
      if (line.replaceFirst(marker, '').trim().isNotEmpty)
        line.replaceFirst(marker, '').trim(),
  ];
}

/// Opens the pop-up of [goal]. Answers true when something changed, so that
/// the caller reloads its lists.
Future<bool> showGoalDialog(BuildContext context, PlanGoal goal) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => GoalDialog(goal: goal),
    ) ??
    false;

/// Opens the pop-up that adds one goal for each line of text. Answers the
/// titles, or null when the user cancels.
Future<List<String>?> showBulkGoalsDialog(BuildContext context,
        {required String periodLabel}) =>
    showDialog<List<String>>(
      context: context,
      builder: (_) => _BulkGoalsDialog(periodLabel: periodLabel),
    );

const double _dialogWidth = 460;

/// The width of the pop-up: 460 pixels, less on a phone.
double _widthIn(BuildContext context) =>
    _dialogWidth.clamp(0, MediaQuery.sizeOf(context).width - 96).toDouble();

/// Edits the title, the description and (for an annual goal) the criteria of a
/// goal, and lists and adds its child goals.
class GoalDialog extends ConsumerStatefulWidget {
  /// Creates the pop-up for [goal].
  const GoalDialog({required this.goal, super.key});

  /// The goal to show.
  final PlanGoal goal;

  @override
  ConsumerState<GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends ConsumerState<GoalDialog> {
  late final _title = TextEditingController(text: widget.goal.title);
  late final _description =
      TextEditingController(text: widget.goal.description ?? '');
  late final _criteria =
      TextEditingController(text: widget.goal.criteria ?? '');
  final _bulk = TextEditingController();
  late final List<PeriodChoice> _periods = childPeriods(widget.goal);
  late PeriodChoice? _period = _periods.isEmpty ? null : _periods.first;
  bool _changed = false;
  bool _busy = false;
  String? _error;

  bool get _annual => widget.goal.periodType == 'year';

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _description, _criteria, _bulk]) {
      c.addListener(() => setState(() {}));
    }
    // A month that holds today is the likely place for a new child goal.
    final now = DateTime.now();
    final here = _periods
        .where((p) => p.start == dateKey(DateTime(now.year, now.month, 1)));
    if (here.isNotEmpty) _period = here.first;
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _criteria, _bulk]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _dirty =>
      _title.text.trim() != widget.goal.title ||
      _description.text.trim() != (widget.goal.description ?? '') ||
      (_annual && _criteria.text.trim() != (widget.goal.criteria ?? ''));

  bool get _canSave => _dirty && _title.text.trim().isNotEmpty && !_busy;

  Future<bool> _guard(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      return true;
    } on DioException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final ok = await _guard(() => ref.read(planningApiProvider).updateGoal(
          widget.goal.id,
          title: _title.text.trim(),
          description: _description.text.trim(),
          criteria: _annual ? _criteria.text.trim() : null,
        ));
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _addChildren() async {
    final titles = parseGoalLines(_bulk.text);
    final period = _period;
    if (titles.isEmpty || period == null) return;
    final ok = await _guard(() => ref.read(planningApiProvider).createGoals(
          periodType: period.type,
          periodStart: period.start,
          parentId: widget.goal.id,
          titles: titles,
        ));
    if (!ok || !mounted) return;
    _bulk.clear();
    _changed = true;
    ref.invalidate(childGoalsProvider(widget.goal.id));
  }

  Future<void> _setStatus(String status) async {
    final ok = await _guard(() =>
        ref.read(planningApiProvider).setGoalStatus(widget.goal.id, status));
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${widget.goal.title}"?'),
        content: const Text('Child goals are deleted too. '
            'What should happen to the linked tasks?'),
        actions: [
          TextButton(
            key: const Key('delete-cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('delete-keep-tasks'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep tasks'),
          ),
          FilledButton(
            key: const Key('delete-remove-tasks'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete tasks'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    final ok = await _guard(() => ref
        .read(planningApiProvider)
        .deleteGoal(widget.goal.id, deleteTasks: choice));
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _close() async {
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard your changes?'),
          content: const Text('The goal keeps its old text.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Keep editing')),
            FilledButton(
                key: const Key('goal-discard'),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Discard')),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (mounted) Navigator.of(context).pop(_changed);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      key: const Key('goal-dialog'),
      title: Text(_annual ? 'Annual goal' : 'Goal'),
      content: SizedBox(
        width: _widthIn(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Text(_error!,
                      key: const Key('goal-dialog-error'),
                      style: TextStyle(color: scheme.error)),
                ),
              _statusRow(),
              const SizedBox(height: Space.md),
              TextField(
                key: const Key('goal-dialog-title'),
                controller: _title,
                decoration: const InputDecoration(labelText: 'Goal'),
              ),
              const SizedBox(height: Space.md),
              TextField(
                key: const Key('goal-dialog-description'),
                controller: _description,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Why this goal matters, and what it covers.',
                  alignLabelWithHint: true,
                ),
              ),
              if (_annual) ...[
                const SizedBox(height: Space.md),
                TextField(
                  key: const Key('goal-dialog-criteria'),
                  controller: _criteria,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Complete when',
                    hintText: 'How you will know that the goal is complete.',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
              if (_periods.isNotEmpty) ...[
                const SizedBox(height: Space.lg),
                Text(_annual ? 'Monthly goals' : 'Weekly goals',
                    style: text.titleSmall),
                const SizedBox(height: Space.xs),
                _children(),
                const SizedBox(height: Space.sm),
                TextField(
                  key: const Key('goal-dialog-bulk-field'),
                  controller: _bulk,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Add goals, one on each line',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: Space.sm),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DropdownButton<PeriodChoice>(
                      key: const Key('goal-dialog-bulk-period'),
                      value: _period,
                      items: [
                        for (final p in _periods)
                          DropdownMenuItem(value: p, child: Text(p.label)),
                      ],
                      onChanged: (v) => setState(() => _period = v ?? _period),
                    ),
                    OutlinedButton(
                      key: const Key('goal-dialog-bulk-add'),
                      onPressed: _busy || parseGoalLines(_bulk.text).isEmpty
                          ? null
                          : _addChildren,
                      child: Text(_addLabel()),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('goal-dialog-close'),
          onPressed: _busy ? null : _close,
          child: Text(_dirty ? 'Cancel' : 'Close'),
        ),
        FilledButton(
          key: const Key('goal-dialog-save'),
          onPressed: _canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }

  /// The state of the goal and the buttons that change it. A goal is
  /// completed here, not from its card.
  Widget _statusRow() {
    final status = widget.goal.status;
    final text = Theme.of(context).textTheme;
    final label = switch (status) {
      'done' => 'Complete',
      'dropped' => 'Dropped',
      _ => 'In progress',
    };
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(label,
            key: const Key('goal-dialog-status'), style: text.labelLarge),
        if (status == 'active') ...[
          FilledButton.tonal(
            key: const Key('goal-dialog-complete'),
            onPressed: _busy ? null : () => _setStatus('done'),
            child: const Text('Mark complete'),
          ),
          TextButton(
            key: const Key('goal-dialog-drop'),
            onPressed: _busy ? null : () => _setStatus('dropped'),
            child: const Text('Drop'),
          ),
        ] else
          OutlinedButton(
            key: const Key('goal-dialog-reopen'),
            onPressed: _busy ? null : () => _setStatus('active'),
            child: const Text('Reopen'),
          ),
        TextButton(
          key: const Key('goal-dialog-delete'),
          onPressed: _busy ? null : _delete,
          child: Text('Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      ],
    );
  }

  String _addLabel() {
    final n = parseGoalLines(_bulk.text).length;
    return n <= 1 ? 'Add goal' : 'Add $n goals';
  }

  Widget _children() {
    final text = Theme.of(context).textTheme;
    return ref.watch(childGoalsProvider(widget.goal.id)).when(
          loading: () => const SizedBox(
              height: 32, child: Center(child: LinearProgressIndicator())),
          error: (e, _) =>
              Text(apiErrorMessage(e), key: const Key('goal-children-error')),
          data: (kids) {
            if (kids.isEmpty) {
              return Text(
                  _annual
                      ? 'No monthly goals yet. Add them below.'
                      : 'No weekly goals yet. Add them below.',
                  key: const Key('goal-no-children'),
                  style: text.bodySmall);
            }
            final sorted = [...kids]
              ..sort((a, b) => a.periodStart.compareTo(b.periodStart));
            return Column(
              key: const Key('goal-children'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final k in sorted)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                            k.status == 'done'
                                ? Icons.check_circle
                                : Icons.flag_outlined,
                            size: 16),
                        const SizedBox(width: Space.sm),
                        SizedBox(
                          width: 76,
                          child: Text(periodLabel(k.periodType, k.periodStart),
                              style: text.labelMedium),
                        ),
                        Expanded(child: Text(k.title, style: text.bodyMedium)),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
  }
}

class _BulkGoalsDialog extends StatefulWidget {
  const _BulkGoalsDialog({required this.periodLabel});

  final String periodLabel;

  @override
  State<_BulkGoalsDialog> createState() => _BulkGoalsDialogState();
}

class _BulkGoalsDialogState extends State<_BulkGoalsDialog> {
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titles = parseGoalLines(_text.text);
    return AlertDialog(
      key: const Key('goal-bulk-dialog'),
      title: Text('Add goals for ${widget.periodLabel}'),
      content: SizedBox(
        width: _widthIn(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type or paste one goal on each line.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: Space.sm),
            TextField(
              key: const Key('goal-bulk-field'),
              controller: _text,
              autofocus: true,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(
                hintText: 'Run 25 km\nRead 12 books\nLearn to sail',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('goal-bulk-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('goal-bulk-create'),
          onPressed:
              titles.isEmpty ? null : () => Navigator.of(context).pop(titles),
          child: Text(
              titles.length <= 1 ? 'Add goal' : 'Add ${titles.length} goals'),
        ),
      ],
    );
  }
}
