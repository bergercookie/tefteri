/// The DONE and TODO marks of a task.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'category_style.dart';
import 'statistics_models.dart';

/// A small button that says whether a task is done: DONE or TODO.
///
/// The border is solid and has the color of the work category of the task:
/// blue for goal-aligned, gray for maintenance, orange for off-plan. A task
/// with no known category gets the quiet gray of the hidden style. DONE is
/// filled with that color. TODO is an empty frame with the color on its text,
/// and a tap on it marks the task done ([onPressed]). A DONE button does
/// nothing.
class TaskStatusButton extends StatelessWidget {
  /// Creates the button.
  const TaskStatusButton({
    required this.done,
    this.category,
    this.onPressed,
    super.key,
  });

  /// The task is done. Otherwise it is still to do.
  final bool done;

  /// The work category of the task, or null when it is not known.
  final Category? category;

  /// Called when the user taps TODO. Ignored when [done].
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final style = categoryStyle(context, category ?? Category.hidden);
    final accent = style.accent;
    final scheme = Theme.of(context).colorScheme;
    final tap = done ? null : onPressed;
    final label = done ? 'DONE' : 'TODO';
    return Semantics(
      button: tap != null,
      label: '${style.name}: ${done ? 'done' : 'to do'}',
      excludeSemantics: true,
      onTap: tap,
      child: Tooltip(
        message: done ? 'Done' : 'Mark done',
        child: Material(
          color: done ? accent : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Corner.md),
            side: BorderSide(color: accent, width: 2),
          ),
          child: InkWell(
            onTap: tap,
            customBorder: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Corner.md)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm, vertical: Space.xs),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: done ? scheme.surface : accent,
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
