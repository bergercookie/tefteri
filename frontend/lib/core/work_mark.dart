/// The mark for work: a briefcase, the same on every page.
///
/// Work is a property of a theme that the user marks in the Projects tab. A
/// theme shows it as a pill with the word "Work". A project or a task under
/// the theme shows the small briefcase. It is a shape and a word, not a color:
/// colors already say which work category a task is in.
library;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// A small briefcase that says "Work" to a screen reader and in a tip.
class WorkIcon extends StatelessWidget {
  /// Creates the icon. [size] is in logical pixels.
  const WorkIcon({this.size = 14, super.key});

  /// Size of the briefcase.
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Work',
        child: Icon(
          Icons.work_outline,
          size: size,
          semanticLabel: 'Work',
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
}

/// A quiet outlined pill: a briefcase and the word "Work".
class WorkPill extends StatelessWidget {
  /// Creates the pill.
  const WorkPill({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: 'Work',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.onSurfaceVariant),
          borderRadius: BorderRadius.circular(Corner.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.work_outline, size: 12, color: scheme.onSurfaceVariant),
            const SizedBox(width: Space.xs),
            Text('Work',
                style:
                    text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
