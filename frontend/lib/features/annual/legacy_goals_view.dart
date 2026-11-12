/// The old goals, read only (FR-023): the goals of months and weeks from
/// before annual planning, and the old year goals that were dropped or
/// marked complete. Nothing here can be changed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/periods.dart';
import '../../theme/theme.dart';
import 'annual_controller.dart';
import 'annual_models.dart';

/// Opens the list of old goals.
Future<void> showLegacyGoals(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const LegacyGoalsView());

String _status(String s) => switch (s) {
      'done' => 'completed',
      'dropped' => 'dropped',
      'retired' => 'retired',
      _ => 'open',
    };

/// The read-only list.
class LegacyGoalsView extends ConsumerWidget {
  /// Creates the view.
  const LegacyGoalsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(legacyGoalsProvider);
    return AlertDialog(
      key: const Key('legacy-goals'),
      title: const Text('Old goals (history)'),
      content: SizedBox(
        width: 560,
        child: goals.when(
          loading: () => const SizedBox(height: 120, child: Loading()),
          error: (e, _) => EmptyState(
            message: apiErrorMessage(e),
            action: TextButton(
              onPressed: () => ref.invalidate(legacyGoalsProvider),
              child: const Text('Try again'),
            ),
          ),
          data: (list) => list.isEmpty
              ? const EmptyState(
                  messageKey: Key('legacy-goals-empty'),
                  message: 'There are no old goals.',
                  icon: Icons.history)
              : SingleChildScrollView(child: _list(context, list)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _list(BuildContext context, List<LegacyGoal> list) {
    final text = Theme.of(context).textTheme;
    final byId = {for (final g in list) g.id: g};
    final sorted = [...list]..sort((a, b) {
        const order = {'year': 0, 'month': 1, 'week': 2};
        final s = b.periodStart.compareTo(a.periodStart);
        return s != 0
            ? s
            : (order[a.periodType] ?? 3).compareTo(order[b.periodType] ?? 3);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'These goals are kept as history. Goals now belong to the annual '
          'plan only, so these cannot change and new tasks cannot link to them.',
          style: text.bodySmall,
        ),
        const SizedBox(height: Space.sm),
        for (final g in sorted)
          Container(
            key: Key('legacy-goal-${g.id}'),
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: context.tefteri.rule))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.title, style: text.bodyMedium),
                Text(
                  [
                    g.periodStart.isEmpty
                        ? g.periodType
                        : periodLabel(g.periodType, g.periodStart),
                    _status(g.status),
                    '${g.linkedTasks} ${g.linkedTasks == 1 ? 'task' : 'tasks'}',
                    if (g.parentId != null && byId[g.parentId] != null)
                      'part of "${byId[g.parentId]!.title}"',
                  ].join(' · '),
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
