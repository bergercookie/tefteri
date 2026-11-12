/// Weekly view: goals, events and tasks of one week.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import '../period/period_page.dart';
import '../../core/periods.dart';
import '../statistics/categories_card.dart';
import '../statistics/completed_by_category.dart';
import '../weekly/week_progress_card.dart';
import '../weekly/weekly_card.dart';

/// Loads the week view for a `YYYY-MM-DD` key (any day of the week).
final weekViewProvider = FutureProvider.family<PeriodView, String>((ref, date) {
  return ref.watch(planningApiProvider).weekView(date);
});

/// Shows one week (Monday to Sunday).
class WeekScreen extends ConsumerStatefulWidget {
  /// Creates the screen; the week holds [initialDate] (default today).
  const WeekScreen({this.initialDate, this.today, super.key});

  /// A day in the week to show first.
  final DateTime? initialDate;

  /// The current day, for tests; defaults to now.
  final DateTime? today;

  @override
  ConsumerState<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends ConsumerState<WeekScreen> {
  late DateTime _start;

  @override
  void initState() {
    super.initState();
    _start = weekStartOf(widget.initialDate ?? DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final key = dateKey(_start);
    return PeriodPage(
      title: 'Week',
      label: 'Week of $key',
      view: ref.watch(weekViewProvider(key)),
      banner: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeeklyPlanningCard(week: _start, today: widget.today),
          const SizedBox(height: Space.sm),
          WeekProgressCard(week: _start, today: widget.today),
          const SizedBox(height: Space.sm),
          CategoriesCard(period: 'week', day: _start),
        ],
      ),
      footer: CompletedByCategory(day: _start),
      onReload: () => ref.invalidate(weekViewProvider(key)),
      onShift: (d) => setState(() =>
          _start = DateTime(_start.year, _start.month, _start.day + 7 * d)),
      onToday: () => setState(() => _start = weekStartOf(DateTime.now())),
    );
  }
}
