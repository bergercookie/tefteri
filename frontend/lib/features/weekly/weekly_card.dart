/// The card on the Week page that starts or continues the weekly planning.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/planning_models.dart';
import '../goals/periods.dart';
import '../../theme/theme.dart';
import 'weekly_api.dart';
import 'weekly_models.dart';
import 'weekly_screen.dart';
import 'weekly_widgets.dart';

/// Says where the weekly planning of [week] stands and opens it.
///
/// Shows nothing while the state loads or when it cannot be loaded: the Week
/// page works without it.
class WeeklyPlanningCard extends ConsumerWidget {
  /// Creates the card for the week that starts on [week] (a Monday).
  ///
  /// [today] is for tests; it defaults to now.
  const WeeklyPlanningCard({required this.week, this.today, super.key});

  /// Monday of the week the page shows.
  final DateTime week;

  /// The current day.
  final DateTime? today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = today ?? DateTime.now();
    // From Friday on, the current week is nearly over, so the card is about
    // the coming week, which is the one to plan.
    final isCurrent = dateKey(week) == dateKey(weekStartOf(now));
    final upcoming = isCurrent && now.weekday >= DateTime.friday;
    final target =
        upcoming ? DateTime(week.year, week.month, week.day + 7) : week;
    final s = ref.watch(weeklyStateProvider(dateKey(target))).valueOrNull;
    if (s == null) return const SizedBox.shrink();
    final plan = s.plan;
    final (title, detail, action) = switch (plan) {
      null => (
          upcoming ? 'Plan next week' : 'Plan this week',
          s.lookBack != null && !s.lookBack!.reviewed
              ? 'Look back at the last plan, then choose your milestones.'
              : 'Choose the milestones to finish and give their tasks a day.',
          'Start planning'
        ),
      WeeklyPlan(committed: true) => (
          upcoming ? 'Next week is planned' : 'This week is planned',
          '${plural(plan.projects.length, 'milestone')} and '
              '${plural(plan.committedCount, 'task')} committed, '
              '${plan.committedDone} done.',
          'Open the plan'
        ),
      _ => (
          upcoming
              ? 'Planning next week is in progress'
              : 'Planning is in progress',
          '${plural(plan.projects.length, 'milestone')} chosen, '
              '${plan.plannedTasks} of ${plural(plan.openTasks, 'task')} have a day.',
          'Continue planning'
        ),
    };
    final colors = context.tefteri;
    final text = Theme.of(context).textTheme;
    return Container(
      key: const Key('weekly-card'),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: colors.taskContainer,
        borderRadius: BorderRadius.circular(Corner.lg),
      ),
      child: Row(
        children: [
          Icon(
              plan?.committed ?? false
                  ? Icons.event_available_outlined
                  : Icons.edit_calendar_outlined,
              color: colors.task),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium),
                Text(detail, style: text.bodyMedium),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          FilledButton(
            key: const Key('weekly-card-open'),
            onPressed: () => openWeeklyPlanning(context, week: target),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}
