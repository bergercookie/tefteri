/// How many days the planner calendar shows at once.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The number of days in the planner calendar.
enum PlannerSpan {
  /// Monday to Sunday.
  week(7, 'Week', 'week'),

  /// The chosen day and the two days after it.
  threeDays(3, '3 days', '3 days'),

  /// One day.
  day(1, 'Day', 'day');

  const PlannerSpan(this.days, this.label, this.unit);

  /// The number of day columns.
  final int days;

  /// The name in the menu.
  final String label;

  /// The step of the arrows, in their tooltips: "Next week".
  final String unit;

  /// The first day shown when the user looks at [day].
  DateTime startFor(DateTime day) => this == week
      ? DateTime(day.year, day.month, day.day - (day.weekday - 1))
      : DateTime(day.year, day.month, day.day);
}

/// Keeps the [PlannerSpan] and stores it on this device. The week is the
/// default.
class PlannerSpanController extends StateNotifier<PlannerSpan> {
  /// Creates the controller and loads the saved choice.
  PlannerSpanController() : super(PlannerSpan.week) {
    _load();
  }

  static const _key = 'planner_span';

  bool _userChanged = false;

  Future<void> _load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_key);
      if (!mounted || _userChanged || saved == null) return;
      state = PlannerSpan.values
          .firstWhere((s) => s.name == saved, orElse: () => PlannerSpan.week);
    } on Object {
      // The choice is only a convenience: keep the week.
    }
  }

  /// Shows [span] and keeps it for the next start.
  Future<void> set(PlannerSpan span) async {
    _userChanged = true;
    state = span;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, span.name);
    } on Object {
      // A store that does not work: the choice lasts until the app closes.
    }
  }
}

/// The number of days that the planner calendar shows.
final plannerSpanProvider =
    StateNotifierProvider<PlannerSpanController, PlannerSpan>(
        (_) => PlannerSpanController());
