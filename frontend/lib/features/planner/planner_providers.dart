/// State and actions of the planner screen.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../calendar/calendar_providers.dart';
import 'planner_visibility.dart';

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

/// Open tasks for the active filter or search. Tasks of a hidden task provider
/// are left out.
final plannerTasksProvider = FutureProvider<List<PlanTask>>((ref) async {
  final due = ref.watch(dueFilterProvider);
  final query = ref.watch(taskSearchProvider);
  final visibility = ref.watch(plannerVisibilityProvider);
  final tasks = await ref.watch(planningApiProvider).tasks(
        due: due.apiValue,
        query: query,
        excludeConnections: visibility.hiddenTaskConnectionIds,
      );
  return [
    for (final task in tasks)
      if (visibility.showsTaskConnection(task.connectionId)) task,
  ];
});

/// Task counts for the filter chips. The tasks of a hidden provider are not
/// counted, so the badges match the list.
final taskCountsProvider = FutureProvider<Map<String, int>>((ref) {
  final visibility = ref.watch(plannerVisibilityProvider);
  return ref
      .watch(planningApiProvider)
      .taskCounts(excludeConnections: visibility.hiddenTaskConnectionIds);
});

/// Where a task that the user is dragging would land if dropped now.
@immutable
class DropPreview {
  /// Creates a preview for [title] on [day]. [startMinutes] is the start of
  /// the block in minutes after midnight; null means all day. A task is a block
  /// of one hour. An event keeps its [durationMinutes] and its [color] (the
  /// color of its calendar, `#rrggbb`).
  const DropPreview({
    required this.day,
    required this.title,
    this.startMinutes,
    this.durationMinutes = 60,
    this.event = false,
    this.color,
  });

  /// The same preview at another start.
  DropPreview at(int? startMinutes) => DropPreview(
        day: day,
        title: title,
        startMinutes: startMinutes,
        durationMinutes: durationMinutes,
        event: event,
        color: color,
      );

  /// How long the block is, in minutes.
  final int durationMinutes;

  /// An event is dragged, not a task.
  final bool event;

  /// The color of the calendar of an event (`#rrggbb`), or null.
  final String? color;

  /// The local day under the pointer.
  final DateTime day;

  /// Title of the dragged task.
  final String title;

  /// Start of the block, in minutes after midnight, snapped to the grid.
  final int? startMinutes;

  @override
  bool operator ==(Object other) =>
      other is DropPreview &&
      other.day == day &&
      other.title == title &&
      other.startMinutes == startMinutes &&
      other.durationMinutes == durationMinutes &&
      other.event == event &&
      other.color == color;

  @override
  int get hashCode =>
      Object.hash(day, title, startMinutes, durationMinutes, event, color);
}

/// True while a task is being dragged. The calendar greys out then.
final dragActiveProvider = StateProvider<bool>((_) => false);

/// The slot under the pointer during a drag; null when the pointer is not
/// over a place where the task can be dropped.
final dropPreviewProvider = StateProvider<DropPreview?>((_) => null);

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

  /// Moves the event [item] so that it starts at [start]. It keeps its length.
  /// The calendar app saves the new time; a calendar that is read-only refuses.
  Future<void> moveEntry(CalendarItem item, DateTime start) {
    final length = (item.end ?? item.start!.add(const Duration(hours: 1)))
        .difference(item.start!);
    return _run(
        item.id, (api) => api.moveEntry(item.id, start, start.add(length)));
  }

  /// Marks [taskId] as done in the task app.
  Future<void> complete(String taskId) =>
      _run(taskId, (api) => api.completeTask(taskId));

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
