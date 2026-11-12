/// A warning on a goal or a key result, with its reason and inline actions.
/// A flag never blocks anything (FR-014).
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'annual_models.dart';

/// The user-facing name of flag [code].
String flagTitle(String code) => switch (code) {
      'no_key_result' => 'No key result',
      'no_usable_theme' => 'No usable theme',
      'overdue' => 'Overdue',
      _ => code.replaceAll('_', ' '),
    };

/// The label of inline action [action].
String flagActionLabel(String action) => switch (action) {
      'add_key_result' => 'Add key result',
      'link_theme' => 'Link a theme',
      'create_theme' => 'Create a theme',
      'update_value' => 'Update value',
      _ => action.replaceAll('_', ' '),
    };

/// The reasons of [flag] in words.
List<String> flagReasons(PlanFlag flag) => switch (flag.code) {
      'no_key_result' => [
          'This goal needs at least one key result to show progress. '
              'You can still save it.'
        ],
      'no_usable_theme' => flag.reasons.isEmpty
          ? ['No theme is linked, so no work serves this key result yet.']
          : [for (final r in flag.reasons) r.sentence],
      'overdue' => [
          'The deadline has passed and the last value did not reach the target.'
        ],
      _ => const [],
    };

/// Shows [flag] of the goal or key result [ownerId].
class FlagChip extends StatelessWidget {
  /// Creates the flag. Only the actions in [allowed] are shown (a past year
  /// allows only `update_value`); null allows all.
  const FlagChip({
    required this.flag,
    required this.ownerId,
    required this.onAction,
    this.allowed,
    super.key,
  });

  /// The flag.
  final PlanFlag flag;

  /// The goal or key result that has it.
  final String ownerId;

  /// Runs an inline action.
  final void Function(String action) onAction;

  /// The actions that may show.
  final Set<String>? allowed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fg = scheme.onSecondaryContainer;
    final id = 'flag-${flag.code}-$ownerId';
    final actions = [
      for (final a in flag.actions)
        if (allowed == null || allowed!.contains(a)) a
    ];
    return Container(
      key: Key(id),
      margin: const EdgeInsets.only(top: Space.xs),
      padding:
          const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.xs, Space.xs),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        border: Border(left: BorderSide(color: context.tefteri.now, width: 3)),
        borderRadius: BorderRadius.circular(Corner.sm),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.sm,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flag_outlined, size: 16, color: fg),
              const SizedBox(width: Space.xs),
              Text(flagTitle(flag.code),
                  key: Key('$id-title'),
                  style: text.labelLarge?.copyWith(color: fg)),
            ],
          ),
          for (final r in flagReasons(flag))
            Text(r, style: text.bodySmall?.copyWith(color: fg)),
          for (final a in actions)
            TextButton(
              key: Key('flag-action-$a-$ownerId'),
              style: TextButton.styleFrom(
                  foregroundColor: fg,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: Space.sm)),
              onPressed: () => onAction(a),
              child: Text(flagActionLabel(a)),
            ),
        ],
      ),
    );
  }
}
