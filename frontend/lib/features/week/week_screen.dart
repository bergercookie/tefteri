/// Weekly view: goals, events and tasks of one week.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/context_filter.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../goals/period_page.dart';
import '../goals/periods.dart';

/// Loads the week view for a `YYYY-MM-DD` key (any day of the week);
/// reloads when the global context filter changes.
final weekViewProvider = FutureProvider.family<PeriodView, String>((ref, date) {
  final filter = ref.watch(contextFilterProvider);
  return ref.watch(planningApiProvider).weekView(date, filter);
});

/// Shows one week (Monday to Sunday).
class WeekScreen extends ConsumerStatefulWidget {
  /// Creates the screen; the week holds [initialDate] (default today).
  const WeekScreen({this.initialDate, super.key});

  /// A day in the week to show first.
  final DateTime? initialDate;

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
      onReload: () => ref.invalidate(weekViewProvider(key)),
      onShift: (d) => setState(() =>
          _start = DateTime(_start.year, _start.month, _start.day + 7 * d)),
      onToday: () => setState(() => _start = weekStartOf(DateTime.now())),
    );
  }
}
