/// The quiet warning about more milestones than the usual cap, and the tag
/// for a milestone outside the month's focus. Neither one blocks anything.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// "You chose N milestones. A week usually holds up to 3." Shows nothing while
/// the count is at or under the cap. It never blocks the commit.
class CapNotice extends StatelessWidget {
  /// Creates the notice for [count] milestones and the cap [cap].
  const CapNotice({required this.count, required this.cap, super.key});

  /// Milestones in the week.
  final int count;

  /// The usual number of milestones for a week.
  final int cap;

  @override
  Widget build(BuildContext context) {
    if (count <= cap) return const SizedBox.shrink();
    final colors = context.tefteri;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      key: const Key('cap-notice'),
      margin: const EdgeInsets.only(top: Space.sm),
      padding:
          const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.rule, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              'You chose $count milestones. A week usually holds up to $cap, '
              'so this may be a lot. You can still commit it.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Outside focus": the theme of the milestone is not in this month's focus.
/// Shows nothing when [show] is false (also when no focus data exists).
class OutsideFocusTag extends StatelessWidget {
  /// Creates the tag.
  const OutsideFocusTag({required this.show, super.key});

  /// The server says the milestone is outside the focus.
  final bool show;

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    final colors = context.tefteri;
    final text = Theme.of(context).textTheme;
    return Container(
      key: const Key('outside-focus'),
      padding:
          const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
      decoration: BoxDecoration(
        border: Border.all(color: colors.rule),
        borderRadius: BorderRadius.circular(Corner.pill),
      ),
      child: Text('Outside focus', style: text.labelSmall),
    );
  }
}
