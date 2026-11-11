/// The dialog that shows what a bulk change does before it is saved, and the
/// snackbar that offers Undo afterwards.
library;

import 'package:flutter/material.dart';

import 'projects_models.dart';

/// How long the Undo snackbar stays. Undo stays on the screen's history
/// after that.
const Duration undoSnackBarDuration = Duration(seconds: 10);

/// Shows [effect] and asks the user to save. Answers true when they do.
Future<bool> showEffectDialog(
  BuildContext context, {
  required String title,
  required LabelEffect effect,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => EffectDialog(title: title, effect: effect),
  );
  return ok == true;
}

/// The numbers of a change: how many projects, from which label to which,
/// and how many are in a committed plan.
class EffectDialog extends StatelessWidget {
  /// Creates the dialog.
  const EffectDialog({required this.title, required this.effect, super.key});

  /// What the user is about to do.
  final String title;

  /// The effect, from a dry run.
  final LabelEffect effect;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final n = effect.changed;
    return AlertDialog(
      key: const Key('effect-dialog'),
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                n == 1 ? '1 project changes.' : '$n projects change.',
                key: const Key('effect-total'),
                style: text.titleSmall,
              ),
              const SizedBox(height: 8),
              for (final c in effect.byChange)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${c.count} from ${labelWord(c.from)} to ${labelWord(c.to)}',
                    key: Key('effect-${c.from}-${c.to}'),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                effect.inCommittedPlan == 0
                    ? 'None of them is in a committed weekly plan.'
                    : '${effect.inCommittedPlan} of them '
                        '${effect.inCommittedPlan == 1 ? 'is' : 'are'} in a '
                        'committed weekly plan. The plan keeps its projects.',
                key: const Key('effect-plan'),
              ),
              const SizedBox(height: 8),
              Text(
                'Nothing changes in your task app. You can undo this for a '
                'few seconds after you save, and later from the recent '
                'changes on this screen.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('effect-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('effect-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(n == 1 ? 'Save 1 change' : 'Save $n changes'),
        ),
      ],
    );
  }
}

/// Shows [message] with an Undo button for ten seconds.
void showUndoSnackBar(BuildContext context, String message,
    {required VoidCallback onUndo}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(SnackBar(
    key: const Key('undo-snackbar'),
    duration: undoSnackBarDuration,
    // A snackbar with an action would otherwise stay until it is closed.
    persist: false,
    content: Text(message),
    action: SnackBarAction(
      label: 'Undo',
      onPressed: onUndo,
    ),
  ));
}
