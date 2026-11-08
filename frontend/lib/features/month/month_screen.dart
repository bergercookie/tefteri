/// Monthly view: goals, events and tasks of one month.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../goals/period_page.dart';
import '../goals/periods.dart';

/// Loads the month view for a `YYYY-MM-DD` key (any day of the month).
final monthViewProvider =
    FutureProvider.family<PeriodView, String>((ref, date) {
  return ref.watch(planningApiProvider).monthView(date);
});

/// Shows one calendar month.
class MonthScreen extends ConsumerStatefulWidget {
  /// Creates the screen; the month holds [initialDate] (default today).
  const MonthScreen({this.initialDate, super.key});

  /// A day in the month to show first.
  final DateTime? initialDate;

  @override
  ConsumerState<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends ConsumerState<MonthScreen> {
  late DateTime _first;

  @override
  void initState() {
    super.initState();
    final d = widget.initialDate ?? DateTime.now();
    _first = DateTime(d.year, d.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final key = dateKey(_first);
    return PeriodPage(
      title: 'Month',
      label: '${monthName(_first.month)} ${_first.year}',
      view: ref.watch(monthViewProvider(key)),
      onReload: () => ref.invalidate(monthViewProvider(key)),
      onShift: (d) =>
          setState(() => _first = DateTime(_first.year, _first.month + d, 1)),
      onToday: () => setState(() {
        final now = DateTime.now();
        _first = DateTime(now.year, now.month, 1);
      }),
    );
  }
}
