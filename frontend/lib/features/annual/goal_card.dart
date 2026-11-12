/// One goal of the annual plan: its sentence, flags, notes and up to three
/// key results.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'annual_models.dart';
import 'flag_chip.dart';
import 'key_result_tile.dart';

/// The limit message of FR-003.
const keyResultLimitMessage =
    'A goal can have three key results. Retire one first.';

/// The card of an active goal.
class GoalCard extends StatefulWidget {
  /// Creates the card.
  const GoalCard({required this.goal, required this.actions, super.key});

  /// The goal.
  final AnnualGoal goal;

  /// The actions of the screen.
  final AnnualActions actions;

  @override
  State<GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends State<GoalCard> {
  bool _limit = false;

  void _add() {
    if (widget.goal.activeKeyResults.length >= 3) {
      setState(() => _limit = true);
      return;
    }
    widget.actions.addKeyResult(widget.goal);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.goal;
    final a = widget.actions;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final quiet = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final active = g.activeKeyResults;
    return Container(
      key: Key('goal-${g.id}'),
      margin: const EdgeInsets.only(bottom: Space.md),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(g.title, style: text.titleLarge)),
              if (a.editable)
                PopupMenuButton<String>(
                  key: Key('goal-menu-${g.id}'),
                  tooltip: 'Goal actions',
                  onSelected: (v) =>
                      v == 'edit' ? a.editGoal(g) : a.retireGoal(g),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit goal')),
                    PopupMenuItem(value: 'retire', child: Text('Retire goal')),
                  ],
                ),
            ],
          ),
          if (g.legacyDone)
            Text('Marked complete before annual planning.',
                key: Key('legacy-done-${g.id}'), style: quiet),
          for (final f in g.flags)
            FlagChip(
              flag: f,
              ownerId: g.id,
              onAction: (_) => _add(),
              allowed: a.editable ? null : const {},
            ),
          if (g.criteriaSuggestion != null && active.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Space.sm,
                children: [
                  Text('Old criteria: "${g.criteriaSuggestion}"',
                      key: Key('criteria-${g.id}'), style: quiet),
                  if (a.editable)
                    TextButton(
                      key: Key('use-criteria-${g.id}'),
                      onPressed: () =>
                          a.addKeyResult(g, metric: g.criteriaSuggestion),
                      child: const Text('Use as key result'),
                    ),
                ],
              ),
            ),
          if (g.notes.contains('duplicate_metric'))
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                  'Two key results measure the same thing. You can merge them.',
                  key: Key('duplicate-metric-${g.id}'),
                  style: quiet),
            ),
          for (final kr in active) ...[
            const SizedBox(height: Space.sm),
            KeyResultTile(kr: kr, actions: a),
          ],
          for (final kr in g.retiredKeyResults) ...[
            const SizedBox(height: Space.xs),
            RetiredKeyResultRow(kr: kr, actions: a),
          ],
          if (a.editable) ...[
            const SizedBox(height: Space.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('add-kr-${g.id}'),
                onPressed: _add,
                icon: const Icon(Icons.add, size: 18),
                label: Text(active.isEmpty
                    ? 'Add key result'
                    : 'Add key result (${active.length} of 3)'),
              ),
            ),
            if (_limit)
              Text(keyResultLimitMessage,
                  key: Key('kr-limit-${g.id}'),
                  style: text.bodySmall?.copyWith(color: scheme.error)),
          ],
        ],
      ),
    );
  }
}

/// A retired goal, in the history part of the screen.
class RetiredGoalRow extends StatelessWidget {
  /// Creates the row.
  const RetiredGoalRow({required this.goal, required this.actions, super.key});

  /// The goal.
  final AnnualGoal goal;

  /// The actions of the screen.
  final AnnualActions actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final n = goal.keyResults.length;
    return Container(
      key: Key('retired-goal-${goal.id}'),
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${goal.title} · $n key ${n == 1 ? 'result' : 'results'}',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (actions.editable)
            TextButton(
              key: Key('restore-goal-${goal.id}'),
              onPressed: () => actions.restoreGoal(goal),
              child: const Text('Restore'),
            ),
        ],
      ),
    );
  }
}
