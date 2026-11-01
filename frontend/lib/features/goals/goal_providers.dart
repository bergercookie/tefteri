/// State for the goals screen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/context_filter.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';

/// Loads goals of one period. The key is `(periodType, periodStart)`.
/// Reloads when the global context filter changes.
final periodGoalsProvider =
    FutureProvider.family<List<PlanGoal>, (String, String)>((ref, key) {
  final filter = ref.watch(contextFilterProvider);
  return ref
      .watch(planningApiProvider)
      .goals(filter, periodType: key.$1, periodStart: key.$2);
});

/// Loads the child goals of one goal. Reloads with the filter.
final childGoalsProvider =
    FutureProvider.family<List<PlanGoal>, String>((ref, parentId) {
  final filter = ref.watch(contextFilterProvider);
  return ref.watch(planningApiProvider).goals(filter, parentId: parentId);
});
