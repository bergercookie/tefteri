/// Annual view: goals and tasks of one year.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../checklists/checklist_panel.dart';
import '../goals/period_page.dart';

/// Loads the year view.
final yearViewProvider = FutureProvider.family<PeriodView, int>((ref, year) {
  return ref.watch(planningApiProvider).yearView(year);
});

/// Shows one year. The server sends no events for a year.
class YearScreen extends ConsumerStatefulWidget {
  /// Creates the screen; [initialYear] defaults to this year.
  const YearScreen({this.initialYear, super.key});

  /// Year to show first.
  final int? initialYear;

  @override
  ConsumerState<YearScreen> createState() => _YearScreenState();
}

class _YearScreenState extends ConsumerState<YearScreen> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear ?? DateTime.now().year;
  }

  @override
  Widget build(BuildContext context) {
    return PeriodPage(
      title: 'Year',
      label: '$_year',
      view: ref.watch(yearViewProvider(_year)),
      banner: PlanningChecklist(
          kind: ChecklistKind.year, day: DateTime(_year), card: true),
      onReload: () => ref.invalidate(yearViewProvider(_year)),
      onShift: (d) => setState(() => _year += d),
      onToday: () => setState(() => _year = DateTime.now().year),
    );
  }
}
