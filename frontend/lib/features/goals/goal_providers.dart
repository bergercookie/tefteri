/// State for the goals screen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/planning_api.dart';
import '../../core/planning_models.dart';

/// Loads goals of one period. The key is `(periodType, periodStart)`.
final periodGoalsProvider =
    FutureProvider.family<List<PlanGoal>, (String, String)>((ref, key) {
  return ref
      .watch(planningApiProvider)
      .goals(periodType: key.$1, periodStart: key.$2);
});

/// Loads the child goals of one goal.
final childGoalsProvider =
    FutureProvider.family<List<PlanGoal>, String>((ref, parentId) {
  return ref.watch(planningApiProvider).goals(parentId: parentId);
});
