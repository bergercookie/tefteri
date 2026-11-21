/// The look-back week against the weeks before it, inside the weekly review.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/planning_models.dart' show dateKey;
import '../../theme/theme.dart';
import 'trend_lines_card.dart';
import 'trends_api.dart';
import 'trends_models.dart';

/// How many weeks the comparison reads. Enough for the four weeks that the
/// average uses, with room for weeks that have no numbers.
const int _weeksRead = 12;

/// Shows how the week that is reviewed went against the weeks before it, with a
/// link to the Trends page. It shows nothing while the numbers load, when they
/// cannot be loaded, and when the week has no numbers: the review must not show
/// a problem of its own because of this.
class RecentComparison extends ConsumerWidget {
  /// Creates the block for the week that starts on [week].
  const RecentComparison({required this.week, super.key});

  /// Monday of the week that is reviewed.
  final DateTime week;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weeks = ref.watch(trendsProvider(_weeksRead)).valueOrNull;
    if (weeks == null) return const SizedBox.shrink();
    final comparison = compareWeek(weeks, week);
    if (comparison == null) return const SizedBox.shrink();
    return Padding(
      key: Key('recent-comparison-${dateKey(week)}'),
      padding: const EdgeInsets.only(top: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TrendLinesCard(
              comparison: comparison, title: 'Compared with your recent weeks'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('see-trends'),
              onPressed: () => GoRouter.maybeOf(context)?.go('/week/trends'),
              icon: const Icon(Icons.show_chart, size: 18),
              label: const Text('See all weeks'),
            ),
          ),
        ],
      ),
    );
  }
}
