/// Step 4: see the whole week grouped by project, then commit the plan.
library;

import 'package:flutter/material.dart';

import '../../core/project_chip.dart';
import 'package:go_router/go_router.dart';

import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import 'cap_notice.dart';
import 'rescope_nudge.dart';
import 'weekly_models.dart';
import 'weekly_widgets.dart';

/// Shows every task planned for the week, grouped by project, with totals.
class FinishStep extends StatelessWidget {
  /// Creates the step.
  const FinishStep({
    required this.state,
    required this.actions,
    required this.onBack,
    super.key,
  });

  /// The loaded week.
  final WeeklyState state;

  /// What the step can ask the screen to do.
  final WeeklyActions actions;

  /// Goes back to giving tasks a day.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final plan = state.plan;
    final text = Theme.of(context).textTheme;
    final colors = context.tefteri;
    final committed = plan?.committed ?? false;
    final projects = plan?.projects ?? const <WeeklyProject>[];
    final plannedTasks = plan?.plannedTasks ?? 0;
    final unscheduled = plan?.unscheduledTasks ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepHeading(
          title: committed ? 'Plan committed' : 'Your week',
          subtitle: committed
              ? 'When you plan the following week, you look back at this '
                  'plan and see how much of it you finished.'
              : 'Check the plan. When it looks right, commit it. A week with '
                  'no milestone is fine too.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Row(
              children: [
                Counter(
                    key: const Key('total-projects'),
                    label: noun(projects.length, 'milestone'),
                    value: projects.length),
                const SizedBox(width: Space.xl),
                Counter(
                    key: const Key('total-tasks'),
                    label: committed
                        ? (plan!.committedCount == 1
                            ? 'task committed'
                            : 'tasks committed')
                        : (plannedTasks == 1 ? 'task' : 'tasks'),
                    value: committed ? plan!.committedCount : plannedTasks,
                    accent: colors.task),
                if (committed) ...[
                  const SizedBox(width: Space.xl),
                  Counter(
                      key: const Key('total-done'),
                      label: 'done so far',
                      value: plan!.committedDone,
                      accent: colors.done),
                ],
              ],
            ),
          ),
        ),
        CapNotice(count: projects.length, cap: plan?.milestoneCap ?? 3),
        const SizedBox(height: Space.sm),
        if (projects.isEmpty)
          const EmptyState(
            icon: Icons.folder_open_outlined,
            messageKey: Key('finish-no-projects'),
            message: 'No milestones this week. You can commit it like this.',
          ),
        for (final p in projects) _group(context, p, committed: committed),
        if (unscheduled > 0 && !committed)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Notice(
              key: const Key('unscheduled-warning'),
              icon: Icons.info_outline,
              message: '${plural(unscheduled, 'open task')} in these '
                  'milestones ${unscheduled == 1 ? 'has' : 'have'} no '
                  'day. ${unscheduled == 1 ? 'It is' : 'They are'} '
                  'not part of this week\'s plan.',
              actions: [
                OutlinedButton(
                  key: const Key('give-days'),
                  onPressed: onBack,
                  child: const Text('Give them a day'),
                ),
              ],
            ),
          ),
        const SizedBox(height: Space.lg),
        if (committed) ...[
          Row(
            children: [
              Icon(Icons.check_circle, color: colors.done, size: 20),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text('Committed. Have a good week.',
                    key: const Key('committed-note'), style: text.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          SpreadRow(
            children: [
              TextButton(
                key: const Key('change-plan'),
                onPressed: actions.changePlan,
                child: const Text('Change the plan'),
              ),
              FilledButton.tonal(
                key: const Key('open-week'),
                onPressed: () =>
                    context.go('/week?date=${dateKey(state.weekStart)}'),
                child: const Text('Open the week'),
              ),
            ],
          ),
        ] else
          SpreadRow(
            children: [
              TextButton.icon(
                key: const Key('step-back'),
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back'),
              ),
              FilledButton(
                key: const Key('commit'),
                onPressed: () => actions.run((api) async {
                  // A week with no milestone has no plan yet. It can still be
                  // committed, so the plan is started first.
                  if (plan == null) await api.start(actions.week);
                  return api.commit(actions.week);
                }),
                child: const Text('Commit the plan'),
              ),
            ],
          ),
        if (!committed && projects.isNotEmpty && plannedTasks == 0)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                  'No task has a day yet. You can commit anyway, but then '
                  'the week has no committed tasks.',
                  key: const Key('commit-hint'),
                  style: text.bodySmall),
            ),
          ),
      ],
    );
  }

  Widget _group(BuildContext context, WeeklyProject p,
      {required bool committed}) {
    final text = Theme.of(context).textTheme;
    final colors = context.tefteri;
    // Once committed, the plan is what was promised, with what is done now.
    final planned = [
      for (final t in (committed ? p.committedTasks : p.tasks))
        if (t.plannedDay != null) t,
    ]..sort((a, b) => a.plannedDay!.compareTo(b.plannedDay!));
    return ProjectCard(
      name: p.name,
      color: p.color,
      key: Key('summary-${p.id}'),
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(p.name, style: text.titleMedium)),
                Text(plural(planned.length, 'task'),
                    key: Key('summary-count-${p.id}'), style: text.titleSmall),
              ],
            ),
            if (p.doneState != null)
              Text('Done when: ${p.doneState}',
                  key: Key('summary-done-state-${p.id}'),
                  style: text.bodyMedium),
            if (p.outsideFocus)
              const Padding(
                padding: EdgeInsets.only(top: Space.xs),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutsideFocusTag(show: true)),
              ),
            RescopeNudge(
                show: p.needsRescope,
                name: p.name,
                nudgeKey: Key('summary-rescope-${p.id}')),
            const SizedBox(height: Space.xs),
            if (planned.isEmpty)
              Text('No task has a day yet.', style: text.bodySmall),
            for (final t in planned)
              Container(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: colors.rule))),
                child: Row(
                  children: [
                    SizedBox(
                      width: 88,
                      child: Text(dayLong(t.plannedDay!),
                          style:
                              text.labelMedium?.copyWith(color: colors.task)),
                    ),
                    Expanded(
                      child: Text(
                        t.title,
                        style: text.bodyMedium?.copyWith(
                            decoration:
                                t.done ? TextDecoration.lineThrough : null),
                      ),
                    ),
                    if (t.done)
                      Icon(Icons.check_circle,
                          size: 16, color: colors.done, semanticLabel: 'Done'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
