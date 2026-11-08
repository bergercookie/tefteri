/// State for the daily view.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/planning_api.dart';
import '../../core/planning_models.dart';

/// Loads the day view for a `YYYY-MM-DD` key.
final dayViewProvider = FutureProvider.family<DayView, String>((ref, date) {
  return ref.watch(planningApiProvider).day(date);
});
