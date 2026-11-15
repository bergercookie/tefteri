/// State for the calendar view.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/planning_api.dart';
import '../../core/planning_models.dart';

/// Number of days shown at one time.
const calendarDays = 7;

/// Loads calendar items for the 7 days from the given local day. The planner
/// shows all of them, or the first three or the first one.
final calendarItemsProvider =
    FutureProvider.family<List<CalendarItem>, DateTime>((ref, from) {
  final to = DateTime(from.year, from.month, from.day + calendarDays);
  return ref.watch(planningApiProvider).calendar(from, to);
});
