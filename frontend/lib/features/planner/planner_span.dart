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

/// Calendar widths from which the planner shows three days and the week.
const double threeDaysMinWidth = 420;

/// Calendar width from which the planner shows the whole week.
const double weekMinWidth = 540;

/// The span that fits a calendar that is [width] wide: a phone shows a day, a
/// tablet or a narrow window three days, and a wide screen the week.
PlannerSpan spanForWidth(double width) => width >= weekMinWidth
    ? PlannerSpan.week
    : width >= threeDaysMinWidth
        ? PlannerSpan.threeDays
        : PlannerSpan.day;

/// What the user chose: a span, or null for automatic (the span follows the
/// width of the calendar). Stored on this device. Automatic is the default.
class PlannerSpanController extends StateNotifier<PlannerSpan?> {
  /// Creates the controller and loads the saved choice.
  PlannerSpanController() : super(null) {
    _load();
  }

  static const _key = 'planner_span';

  bool _userChanged = false;

  Future<void> _load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_key);
      if (!mounted || _userChanged || saved == null) return;
      state = PlannerSpan.values.where((s) => s.name == saved).firstOrNull;
    } on Object {
      // The choice is only a convenience: stay automatic.
    }
  }

  /// Shows [span], or follows the width again when [span] is null, and keeps
  /// the choice for the next start.
  Future<void> set(PlannerSpan? span) async {
    _userChanged = true;
    state = span;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (span == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, span.name);
      }
    } on Object {
      // A store that does not work: the choice lasts until the app closes.
    }
  }
}

/// The span that the user chose, or null for automatic.
final plannerSpanProvider =
    StateNotifierProvider<PlannerSpanController, PlannerSpan?>(
        (_) => PlannerSpanController());
