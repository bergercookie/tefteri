/// The gentle suggestion to shrink, split or close a milestone that keeps
/// rolling over. It is a line of text and never blocks anything.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// "This milestone rolled over twice without being expected. Shrink it, split
/// it or close it." Shows nothing unless [show] is true.
class RescopeNudge extends StatelessWidget {
  /// Creates the nudge for the milestone called [name].
  const RescopeNudge(
      {required this.show, required this.name, this.nudgeKey, super.key});

  /// The server says the milestone needs re-scoping.
  final bool show;

  /// The milestone name.
  final String name;

  /// Key of the nudge, for tests.
  final Key? nudgeKey;

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      key: nudgeKey,
      padding: const EdgeInsets.only(top: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.call_split, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              '"$name" has rolled over twice in a row. Try to shrink it, split '
              'it or close it. You can still commit it as it is.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
