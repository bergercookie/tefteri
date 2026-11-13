/// One key result in a goal card: its numbers, a progress bar, its themes,
/// its flags and its actions.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'annual_models.dart';
import 'flag_chip.dart';

/// What the cards of the annual plan can ask the screen to do.
class AnnualActions {
  /// Creates the actions.
  const AnnualActions({
    required this.editable,
    required this.addKeyResult,
    required this.editGoal,
    required this.retireGoal,
    required this.restoreGoal,
    required this.editKeyResult,
    required this.linkThemes,
    required this.addGoalThemes,
    required this.retireKeyResult,
    required this.restoreKeyResult,
    required this.updateValue,
  });

  /// False in a past year: only values can be entered.
  final bool editable;

  /// Adds a key result; [metric] fills the metric field.
  final void Function(AnnualGoal goal, {String? metric}) addKeyResult;

  /// Changes the sentence of a goal.
  final void Function(AnnualGoal goal) editGoal;

  /// Retires a goal.
  final void Function(AnnualGoal goal) retireGoal;

  /// Restores a goal.
  final void Function(AnnualGoal goal) restoreGoal;

  /// Changes a key result.
  final void Function(KeyResult kr) editKeyResult;

  /// Opens the theme picker; with [create] the create dialog opens first.
  final void Function(KeyResult kr, {bool create}) linkThemes;

  /// Adds themes to every active key result of a goal.
  final void Function(AnnualGoal goal) addGoalThemes;

  /// Retires a key result.
  final void Function(KeyResult kr) retireKeyResult;

  /// Restores a key result.
  final void Function(KeyResult kr) restoreKeyResult;

  /// Opens the value dialog.
  final void Function(KeyResult kr) updateValue;
}

/// An active key result.
class KeyResultTile extends StatelessWidget {
  /// Creates the tile.
  const KeyResultTile({required this.kr, required this.actions, super.key});

  /// The key result.
  final KeyResult kr;

  /// The actions of the screen.
  final AnnualActions actions;

  void _flag(String action) => switch (action) {
        'link_theme' => actions.linkThemes(kr),
        'create_theme' => actions.linkThemes(kr, create: true),
        _ => actions.updateValue(kr),
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final progress = kr.progress;
    final shown = progress.isFinite ? progress : 0.0;
    final links = kr.activeLinks;
    return Container(
      key: Key('kr-${kr.id}'),
      padding:
          const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.xs, Space.sm),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.primary, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: Space.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(kr.metric, style: text.bodyLarge),
                    if (kr.automatic)
                      Container(
                        key: Key('kr-auto-${kr.id}'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: Space.sm, vertical: 1),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(Corner.pill),
                        ),
                        child: Text('Automatic',
                            style: text.labelSmall
                                ?.copyWith(color: scheme.onPrimaryContainer)),
                      ),
                  ],
                ),
              ),
              TextButton(
                key: Key('kr-value-btn-${kr.id}'),
                onPressed: () => actions.updateValue(kr),
                child: const Text('Update value'),
              ),
              if (actions.editable)
                PopupMenuButton<String>(
                  key: Key('kr-menu-${kr.id}'),
                  tooltip: 'Key result actions',
                  onSelected: (v) => switch (v) {
                    'edit' => actions.editKeyResult(kr),
                    'themes' => actions.linkThemes(kr),
                    _ => actions.retireKeyResult(kr),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'themes', child: Text('Link themes')),
                    PopupMenuItem(value: 'retire', child: Text('Retire')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Corner.pill),
                  child: LinearProgressIndicator(
                    key: Key('kr-progress-${kr.id}'),
                    value: shown.clamp(0.0, 1.0),
                    minHeight: 6,
                    color: kr.met ? context.tefteri.done : scheme.primary,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              Text(kr.yesNo ? kr.yesNoAnswer : '${(shown * 100).round()}%',
                  key: Key('kr-percent-${kr.id}'), style: text.labelLarge),
            ],
          ),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.xs,
            children: [
              if (kr.yesNo)
                Text(kr.yesNoAnswer,
                    key: Key('kr-value-${kr.id}'), style: text.bodySmall)
              else ...[
                Text(
                    '${formatNumber(kr.currentValue)} of ${formatNumber(kr.target)}',
                    key: Key('kr-value-${kr.id}'),
                    style: text.bodySmall),
                Text('started at ${formatNumber(kr.startValue)}',
                    style: text.bodySmall),
              ],
              Text('deadline ${kr.deadline}', style: text.bodySmall),
            ],
          ),
          if (links.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final l in links)
                    Container(
                      key: Key('kr-theme-${kr.id}-${l.projectId}'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: Space.sm, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: l.usable
                                ? context.tefteri.rule
                                : scheme.outline),
                        borderRadius: BorderRadius.circular(Corner.pill),
                      ),
                      child: Text(
                        l.usable ? l.name : '${l.name} (not usable)',
                        style: text.labelSmall?.copyWith(
                            color: l.usable
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                            decoration:
                                l.usable ? null : TextDecoration.lineThrough),
                      ),
                    ),
                ],
              ),
            ),
          for (final f in kr.flags)
            FlagChip(
              flag: f,
              ownerId: kr.id,
              onAction: _flag,
              allowed: actions.editable ? null : const {'update_value'},
            ),
        ],
      ),
    );
  }
}

/// A retired key result: quiet, with Restore in an open year.
class RetiredKeyResultRow extends StatelessWidget {
  /// Creates the row.
  const RetiredKeyResultRow(
      {required this.kr, required this.actions, super.key});

  /// The key result.
  final KeyResult kr;

  /// The actions of the screen.
  final AnnualActions actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: Key('retired-kr-${kr.id}'),
      padding: const EdgeInsets.only(left: Space.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Retired: ${kr.metric} (${formatNumber(kr.currentValue)} of '
              '${formatNumber(kr.target)})',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (actions.editable)
            TextButton(
              key: Key('restore-kr-${kr.id}'),
              onPressed: () => actions.restoreKeyResult(kr),
              child: const Text('Restore'),
            ),
        ],
      ),
    );
  }
}
