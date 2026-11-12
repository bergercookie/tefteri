/// The dialogs that show the effect of a destructive choice before it is
/// made (FR-032): retire a key result, retire a goal, end or move links.
/// After the change the screen offers Undo for ten seconds
/// ([showUndoSnackBar] of the Projects screen).
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'annual_models.dart';
import 'annual_term_hint.dart';

/// The answer of the retire dialog: the optional reason.
typedef RetireAnswer = ({String? reason});

/// Shows [effect] of retiring [name] and asks for a reason. Answers null when
/// the user cancels.
Future<RetireAnswer?> showRetireDialog(
  BuildContext context, {
  required String name,
  required RetireEffect effect,
  required bool goal,
}) =>
    showDialog<RetireAnswer>(
      context: context,
      builder: (_) => RetireDialog(name: name, effect: effect, goal: goal),
    );

/// The effect of a retire in words.
String retireEffectText(RetireEffect e, {required bool goal}) {
  final links = e.linksEnded == 1
      ? '1 theme link ends'
      : '${e.linksEnded} theme links end';
  if (goal) {
    final krs = e.keyResultsRetired == 1
        ? '1 key result retires with this goal'
        : '${e.keyResultsRetired} key results retire with this goal';
    return '$krs. $links. Its flags go away. The history stays, and you can '
        'restore the goal later.';
  }
  return 'This key result stops counting as active. $links. Its flags go '
      'away. Its history stays, and you can restore it later.';
}

/// The retire dialog.
class RetireDialog extends StatefulWidget {
  /// Creates the dialog.
  const RetireDialog(
      {required this.name,
      required this.effect,
      required this.goal,
      super.key});

  /// The goal or key result.
  final String name;

  /// The effect, from a dry run.
  final RetireEffect effect;

  /// True for a goal.
  final bool goal;

  @override
  State<RetireDialog> createState() => _RetireDialogState();
}

class _RetireDialogState extends State<RetireDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('retire-dialog'),
      title:
          Text(widget.goal ? 'Retire this goal?' : 'Retire this key result?'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AnnualTermHint(AnnualTerm.retire),
            Text('"${widget.name}"',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: Space.sm),
            Text(retireEffectText(widget.effect, goal: widget.goal),
                key: const Key('retire-effect')),
            const SizedBox(height: Space.md),
            TextField(
              key: const Key('retire-reason'),
              controller: _reason,
              decoration: const InputDecoration(
                  labelText: 'Reason (optional)', hintText: 'Too ambitious'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('retire-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('retire-confirm'),
          onPressed: () {
            final r = _reason.text.trim();
            Navigator.of(context).pop((reason: r.isEmpty ? null : r));
          },
          child: const Text('Retire'),
        ),
      ],
    );
  }
}

/// Shows which links end and which start. Answers true when the user
/// confirms.
Future<bool> showLinkEffectDialog(
        BuildContext context, LinkEffect effect) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('link-effect-dialog'),
        title: Text(effect.added.isEmpty
            ? 'Remove the theme link?'
            : 'Change the theme links?'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in effect.ended)
                Text('Ends: ${p.name}', key: Key('link-ended-${p.projectId}')),
              for (final p in effect.added)
                Text('Starts: ${p.name}',
                    key: Key('link-added-${p.projectId}')),
              const SizedBox(height: Space.sm),
              Text(
                'An ended link stays in the history of the year. Nothing '
                'changes in your task app. You can undo this.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('link-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('link-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save links'),
          ),
        ],
      ),
    ) ==
    true;
