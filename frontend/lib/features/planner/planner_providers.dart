/// State and actions of the planner screen.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/context_filter.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../calendar/calendar_providers.dart';

/// The filters at the top of the task column.
enum DueFilter {
  /// Open tasks due today.
  today('today', 'Today'),

  /// Open tasks due tomorrow.
  tomorrow('tomorrow', 'Tomorrow'),

  /// Open tasks due this week (Monday to Sunday).
  week('week', 'This week'),

  /// All open tasks.
  all('all', 'All'),

  /// Open tasks without a due date.
  none('none', 'No due date'),

  /// Open tasks whose due date has passed.
  overdue('overdue', 'Overdue');

  const DueFilter(this.apiValue, this.label);

  /// Value of the `due` query parameter.
  final String apiValue;

  /// Text on the chip.
  final String label;
}

/// The active task filter. "Today" is the default.
final dueFilterProvider = StateProvider<DueFilter>((_) => DueFilter.today);

/// The applied search text. A non-empty text searches all open tasks.
final taskSearchProvider = StateProvider<String>((_) => '');

/// Open tasks for the active filter or search.
final plannerTasksProvider = FutureProvider<List<PlanTask>>((ref) {
  final filter = ref.watch(contextFilterProvider);
  final due = ref.watch(dueFilterProvider);
  final query = ref.watch(taskSearchProvider);
  return ref
      .watch(planningApiProvider)
      .tasks(filter, due: due.apiValue, query: query);
});

/// Task counts for the filter chips.
final taskCountsProvider = FutureProvider<Map<String, int>>((ref) {
  final filter = ref.watch(contextFilterProvider);
  return ref.watch(planningApiProvider).taskCounts(filter);
});

/// Message of the last failed schedule action; null when there is none.
final plannerErrorProvider = StateProvider<String?>((_) => null);

/// Id of the task whose schedule change is being saved, if any.
final pendingTaskProvider = StateProvider<String?>((_) => null);

/// Schedule actions. The UI shows a change only after the server has saved
/// it: nothing is optimistic and nothing is queued (spec FR-012).
class PlannerActions {
  /// Creates the actions.
  PlannerActions(this._ref);

  final Ref _ref;

  /// Plans [taskId] so that its block starts at [start].
  Future<void> scheduleAt(String taskId, DateTime start) =>
      _run(taskId, (api) => api.scheduleTaskAt(taskId, start));

  /// Plans [taskId] for [day] only, with no time of day.
  Future<void> scheduleOnDate(String taskId, DateTime day) =>
      _run(taskId, (api) => api.scheduleTaskOnDate(taskId, day));

  /// Removes the due date and time of [taskId].
  Future<void> unschedule(String taskId) =>
      _run(taskId, (api) => api.unscheduleTask(taskId));

  /// Reloads the task list, the counts and the calendar from the server.
  void refresh() {
    _ref.invalidate(calendarItemsProvider);
    _ref.invalidate(plannerTasksProvider);
    _ref.invalidate(taskCountsProvider);
  }

  Future<void> _run(
      String taskId, Future<void> Function(PlanningApi api) action) async {
    _ref.read(pendingTaskProvider.notifier).state = taskId;
    try {
      await action(_ref.read(planningApiProvider));
      _ref.read(plannerErrorProvider.notifier).state = null;
    } on DioException catch (e) {
      _ref.read(plannerErrorProvider.notifier).state = apiErrorMessage(e);
    } finally {
      _ref.read(pendingTaskProvider.notifier).state = null;
      refresh();
    }
  }
}

/// Provides the schedule actions.
final plannerActionsProvider =
    Provider<PlannerActions>((ref) => PlannerActions(ref));
