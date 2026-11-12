/// The goal picker of a task (FR-026): it offers only the active goals of
/// this year's annual plan.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../theme/theme.dart';
import '../annual/annual_controller.dart';
import '../annual/annual_models.dart';

/// Opens the picker for the goals of [year]. Answers the chosen goal, or null.
Future<AnnualGoal?> showTaskGoalPicker(BuildContext context,
        {required int year}) =>
    showDialog<AnnualGoal>(
        context: context, builder: (_) => TaskGoalPicker(year: year));

/// The picker dialog.
class TaskGoalPicker extends ConsumerWidget {
  /// Creates the picker for [year].
  const TaskGoalPicker({required this.year, super.key});

  /// The current planning year.
  final int year;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(annualPlanReadProvider(year));
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      key: const Key('task-goal-picker'),
      title: const Text('Link to a goal'),
      content: SizedBox(
        width: 420,
        child: plan.when(
          loading: () => const SizedBox(height: 96, child: Loading()),
          error: (e, _) => EmptyState(message: apiErrorMessage(e)),
          data: (p) {
            final goals = [
              for (final g in p.goals)
                if (g.status != 'retired') g
            ];
            if (goals.isEmpty) {
              return EmptyState(
                messageKey: const Key('task-goal-empty'),
                message: 'The annual plan of $year has no goals yet.',
                icon: Icons.flag_outlined,
                action: TextButton(
                  key: const Key('open-annual-plan'),
                  onPressed: () {
                    final router = GoRouter.maybeOf(context);
                    Navigator.of(context).pop();
                    router?.go('/annual?year=$year');
                  },
                  child: const Text('Open the annual plan'),
                ),
              );
            }
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Goals of the annual plan of $year',
                      style: text.bodySmall),
                  const SizedBox(height: Space.xs),
                  for (final g in goals)
                    InkWell(
                      key: Key('link-goal-${g.id}'),
                      borderRadius: BorderRadius.circular(Corner.md),
                      onTap: () => Navigator.of(context).pop(g),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: Space.sm, horizontal: Space.sm),
                        child: Row(
                          children: [
                            const Icon(Icons.flag_outlined, size: 18),
                            const SizedBox(width: Space.sm),
                            Expanded(child: Text(g.title)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
