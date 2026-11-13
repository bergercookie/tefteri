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
  const GoalCard({
    required this.goal,
    required this.actions,
    required this.collapsed,
    required this.onToggleCollapsed,
    super.key,
  });

  /// The goal.
  final AnnualGoal goal;

  /// The actions of the screen.
  final AnnualActions actions;

  /// True when the key results are hidden.
  final bool collapsed;

  /// Shows or hides the key results.
  final VoidCallback onToggleCollapsed;

  @override
  State<GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends State<GoalCard> {
  void _add() {
    if (widget.goal.activeKeyResults.length >= 3) return;
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
              IconButton(
                key: Key('goal-toggle-${g.id}'),
                tooltip: widget.collapsed
                    ? 'Expand key results'
                    : 'Collapse key results',
                icon: Icon(widget.collapsed
                    ? Icons.keyboard_arrow_right
                    : Icons.keyboard_arrow_down),
                onPressed: widget.onToggleCollapsed,
              ),
              if (a.editable)
                PopupMenuButton<String>(
                  key: Key('goal-menu-${g.id}'),
                  tooltip: 'Goal actions',
                  onSelected: (v) => switch (v) {
                    'edit' => a.editGoal(g),
                    'themes' => a.addGoalThemes(g),
                    _ => a.retireGoal(g),
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'edit', child: Text('Edit goal')),
                    if (active.isNotEmpty)
                      const PopupMenuItem(
                        value: 'themes',
                        child: Text('Link a theme to all key results'),
                      ),
                    const PopupMenuItem(
                        value: 'retire', child: Text('Retire goal')),
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
          if (widget.collapsed)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                active.isEmpty
                    ? 'No key results'
                    : '${active.length} key ${active.length == 1 ? 'result' : 'results'} hidden',
                key: Key('goal-collapsed-${g.id}'),
                style: quiet,
              ),
            )
          else ...[
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
                child: Tooltip(
                  message: active.length >= 3
                      ? keyResultLimitMessage
                      : 'Add a key result',
                  child: TextButton.icon(
                    key: Key('add-kr-${g.id}'),
                    onPressed: active.length >= 3 ? null : _add,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(active.isEmpty
                        ? 'Add key result'
                        : 'Add key result (${active.length} of 3)'),
                  ),
                ),
              ),
            ],
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
