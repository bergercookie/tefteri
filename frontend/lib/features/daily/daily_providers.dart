/// State for the daily view.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/context_filter.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';

/// Loads the day view for a `YYYY-MM-DD` key; reloads when the global
/// context filter changes.
final dayViewProvider = FutureProvider.family<DayView, String>((ref, date) {
  final filter = ref.watch(contextFilterProvider);
  return ref.watch(planningApiProvider).day(date, filter);
});
