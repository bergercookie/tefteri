/// Goals screen: browse goals by period, add, finish, drop, delete and
/// break down goals.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../core/shell.dart';
import '../settings/connection_models.dart';
import '../settings/sync_controller.dart';
import 'breakdown_dialog.dart';
import 'goal_providers.dart';
import 'goal_widgets.dart';
import 'periods.dart';

/// Lists goals of one year, month or week, with their child goals.
class GoalsScreen extends ConsumerStatefulWidget {
  /// Creates the screen; the period holds [initialDate] (default today).
  const GoalsScreen({this.initialDate, super.key});

  /// A day in the period to show first.
  final DateTime? initialDate;

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  late DateTime _anchor;
  String _type = 'year';
  String? _error;
  final _titleCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _anchor = widget.initialDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    super.dispose();
  }

  DateTime get _start => switch (_type) {
        'year' => DateTime(_anchor.year, 1, 1),
        'month' => DateTime(_anchor.year, _anchor.month, 1),
        _ => weekStartOf(_anchor),
      };

  (String, String) get _key => (_type, dateKey(_start));

  void _shift(int d) => setState(() {
        final s = _start;
        _anchor = switch (_type) {
          'year' => DateTime(s.year + d, 1, 1),
          'month' => DateTime(s.year, s.month + d, 1),
          _ => DateTime(s.year, s.month, s.day + 7 * d),
        };
      });

  void _reload() {
    ref.invalidate(periodGoalsProvider(_key));
    ref.invalidate(childGoalsProvider);
  }

  Future<bool> _run(Future<void> Function() action) async {
    try {
      await action();
    } on DioException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
      return false;
    }
    if (!mounted) return false;
    setState(() => _error = null);
    _reload();
    return true;
  }

  Future<void> _add() async {
    final title = _titleCtl.text.trim();
    if (title.isEmpty) return;
    final ok = await _run(() => ref.read(planningApiProvider).createGoal(
        periodType: _type, periodStart: dateKey(_start), title: title));
    if (ok) _titleCtl.clear();
  }

  Future<void> _breakdown(PlanGoal goal) async {
    final List<Connection> all;
    try {
      all = await ref.read(connectionsProvider.future);
    } on DioException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
      return;
    }
    if (!mounted) return;
    final conns = all.where((c) => c.kind == 'tasks').toList();
    final req = await showDialog<BreakdownRequest>(
      context: context,
      builder: (_) => BreakdownDialog(goal: goal, connections: conns),
    );
    if (req == null || (req.goals.isEmpty && req.tasks.isEmpty)) return;
    await _run(() => ref
        .read(planningApiProvider)
        .breakdownGoal(goal.id, req.goals, req.tasks));
  }

  Future<void> _delete(PlanGoal goal) async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${goal.title}"?'),
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
    await _run(() =>
        ref.read(planningApiProvider).deleteGoal(goal.id, deleteTasks: choice));
  }

  Widget _menu(PlanGoal g) => PopupMenuButton<String>(
        key: Key('goal-menu-${g.id}'),
        onSelected: (v) {
          switch (v) {
            case 'breakdown':
              _breakdown(g);
            case 'done':
              _run(() =>
                  ref.read(planningApiProvider).setGoalStatus(g.id, 'done'));
            case 'active':
              _run(() =>
                  ref.read(planningApiProvider).setGoalStatus(g.id, 'active'));
            case 'drop':
              _run(() =>
                  ref.read(planningApiProvider).setGoalStatus(g.id, 'dropped'));
            case 'delete':
              _delete(g);
          }
        },
        itemBuilder: (_) => [
          if (g.periodType != 'week')
            const PopupMenuItem(value: 'breakdown', child: Text('Break down')),
          if (g.status != 'done')
            const PopupMenuItem(value: 'done', child: Text('Mark done')),
          if (g.status != 'active')
            const PopupMenuItem(value: 'active', child: Text('Reopen')),
          if (g.status != 'dropped')
            const PopupMenuItem(value: 'drop', child: Text('Drop')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      );

  Widget _node(PlanGoal g, int depth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 16.0 * depth),
          child: GoalTile(goal: g, trailing: _menu(g)),
        ),
        if (g.periodType != 'week')
          ref.watch(childGoalsProvider(g.id)).maybeWhen(
                data: (kids) => Column(
                    children: [for (final k in kids) _node(k, depth + 1)]),
                orElse: () => const SizedBox.shrink(),
              ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final goals = ref.watch(periodGoalsProvider(_key));
    return AppShell(
      title: 'Goals',
      body: Column(
        children: [
          if (_error != null)
            ErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<String>(
              key: const Key('goal-period-type'),
              segments: const [
                ButtonSegment(value: 'year', label: Text('Year')),
                ButtonSegment(value: 'month', label: Text('Month')),
                ButtonSegment(value: 'week', label: Text('Week')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const Key('prev-period'),
                tooltip: 'Previous',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shift(-1),
              ),
              Text(periodLabel(_type, dateKey(_start)),
                  key: const Key('period-label')),
              IconButton(
                key: const Key('next-period'),
                tooltip: 'Next',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _shift(1),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('goal-title-field'),
                  controller: _titleCtl,
                  decoration: const InputDecoration(hintText: 'New goal'),
                  onSubmitted: (_) => _add(),
                ),
              ),
              IconButton(
                key: const Key('goal-add-button'),
                tooltip: 'Add goal',
                icon: const Icon(Icons.add),
                onPressed: _add,
              ),
            ]),
          ),
          Expanded(
            child: goals.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(apiErrorMessage(e), key: const Key('load-error')),
                    TextButton(
                      key: const Key('reload-button'),
                      onPressed: _reload,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
              data: (list) => ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  if (list.isEmpty)
                    const Text('No goals for this period.',
                        key: Key('no-goals')),
                  for (final g in list) _node(g, 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
