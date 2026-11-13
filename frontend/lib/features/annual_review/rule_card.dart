/// The one rule that decides hit and missed, and the hint rule.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// A short, quiet box that states the rule of the review.
class RuleCard extends StatelessWidget {
  /// Creates the card.
  const RuleCard({super.key, this.state = 'past'});

  /// The year state.
  final String state;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final line = state == 'current'
        ? 'This year is still in progress. The review shows the months so far '
            'and does not claim a final result.'
        : 'Hit means the last value stored in the year reached the target. '
            'Missed means it did not. The line "Reached by deadline" uses the '
            'last value stored on or before the deadline.';
    return Container(
      key: const Key('review-rule'),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
        borderRadius: BorderRadius.circular(Corner.md),
      ),
      child: Text(line, style: text.bodySmall),
    );
  }
}
