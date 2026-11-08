/// Widgets for goals and tasks that planning views share.
library;

import 'package:flutter/material.dart';

import '../../core/context_filter.dart';
import '../../core/planning_models.dart';
import 'goal_dialog.dart';

/// Row for one goal with a progress bar.
class GoalTile extends StatelessWidget {
  /// Creates a tile for [goal]; [trailing] is shown at the end.
  const GoalTile(
      {required this.goal,
      this.trailing,
      this.onChanged,
      this.number,
      super.key});

  /// The goal to show.
  final PlanGoal goal;

  /// Optional action widget, such as a menu.
  final Widget? trailing;

  /// The place of the goal in its list, such as `2` or `2.1`. Shown at the
  /// left of the card.
  final String? number;

  /// Called after the pop-up of the goal changed something, so that the
  /// page reloads its lists.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final percent = (goal.progress * 100).round();
    final text = Theme.of(context).textTheme;
    final description = (goal.description ?? '').trim();
    final criteria = (goal.criteria ?? '').trim();
    return ListTile(
      key: Key('goal-${goal.id}'),
      dense: true,
      onTap: () async {
        if (await showGoalDialog(context, goal)) onChanged?.call();
      },
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (number != null)
            SizedBox(
              width: 40,
              child: Text(number!,
                  key: Key('goal-number-${goal.id}'),
                  style: text.labelLarge
                      ?.copyWith(color: Theme.of(context).colorScheme.primary)),
            ),
          Icon(goal.status == 'done'
              ? Icons.check_circle
              : goal.status == 'dropped'
                  ? Icons.cancel_outlined
                  : Icons.flag_outlined),
        ],
      ),
      title: Text(goal.title,
          style: goal.status == 'dropped'
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description.isNotEmpty)
            Text(description,
                key: Key('goal-description-${goal.id}'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall),
          if (goal.periodType == 'year' && criteria.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: 'Complete when: ',
                      style: text.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  TextSpan(text: criteria),
                ]),
                key: Key('goal-criteria-${goal.id}'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall,
              ),
            ),
          const SizedBox(height: 4),
          Row(
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
        ],
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        ContextMarker(itemContext: goal.context),
        if (trailing != null) trailing!,
      ]),
    );
  }
}
