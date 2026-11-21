/// Weekly view: the plan, its progress, the work categories and the tasks.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import '../period/period_page.dart';
import '../../core/periods.dart';
import '../statistics/categories_card.dart';
import '../statistics/open_work_card.dart';
import '../statistics/statistics_providers.dart';
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

  /// Reads the week again, with the numbers and the lists that depend on it:
  /// a task that changed moves between the cards.
  void _reload() {
    ref.invalidate(weekViewProvider(dateKey(_start)));
    ref.invalidate(statisticsProvider);
    ref.invalidate(openTasksProvider);
    ref.invalidate(taskListProvider);
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
          const SizedBox(height: Space.sm),
          OpenWorkCard(day: _start, onChanged: _reload),
        ],
      ),
      onReload: _reload,
      onShift: (d) => setState(() =>
          _start = DateTime(_start.year, _start.month, _start.day + 7 * d)),
      onToday: () => setState(() => _start = weekStartOf(DateTime.now())),
    );
  }
}
