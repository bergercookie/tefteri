/// Widgets for goals and tasks that planning views share.
library;

import 'package:flutter/material.dart';

import '../../core/context_filter.dart';
import '../../core/planning_models.dart';

/// Row for one goal with a progress bar.
class GoalTile extends StatelessWidget {
  /// Creates a tile for [goal]; [trailing] is shown at the end.
  const GoalTile({required this.goal, this.trailing, super.key});

  /// The goal to show.
  final PlanGoal goal;

  /// Optional action widget, such as a menu.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final percent = (goal.progress * 100).round();
    return ListTile(
      key: Key('goal-${goal.id}'),
      dense: true,
      leading: Icon(goal.status == 'done'
          ? Icons.check_circle
          : goal.status == 'dropped'
              ? Icons.cancel_outlined
              : Icons.flag_outlined),
      title: Text(goal.title,
          style: goal.status == 'dropped'
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null),
      subtitle: Row(
        children: [
          Expanded(
            child: LinearProgressIndicator(
              key: Key('goal-progress-${goal.id}'),
              value: goal.progress,
            ),
          ),
          const SizedBox(width: 8),
          Text('$percent%', key: Key('goal-percent-${goal.id}')),
        ],
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        ContextMarker(itemContext: goal.context),
        if (trailing != null) trailing!,
      ]),
    );
  }
}
