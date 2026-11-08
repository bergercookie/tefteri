/// Typed calls to the planning endpoints of the backend.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'planning_models.dart';

/// Wraps the planning endpoints. Failed calls throw [DioException]; nothing
/// is queued or retried here.
class PlanningApi {
  /// Creates the API using [_dio].
  PlanningApi(this._dio);

  final Dio _dio;

  /// `GET /views/day/{date}`.
  Future<DayView> day(String date) async {
    final r = await _dio.get<Object?>('/views/day/$date');
    return DayView.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `GET /views/week/{date}` (the week that holds [date]).
  Future<PeriodView> weekView(String date) => _period('/views/week/$date');

  /// `GET /views/month/{date}` (the month that holds [date]).
  Future<PeriodView> monthView(String date) => _period('/views/month/$date');

  /// `GET /views/year/{year}`.
  Future<PeriodView> yearView(int year) => _period('/views/year/$year');

  Future<PeriodView> _period(String path) async {
    final r = await _dio.get<Object?>(path);
    return PeriodView.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `GET /goals` for one period, or for the children of [parentId].
  Future<List<PlanGoal>> goals(
      {String? periodType, String? periodStart, String? parentId}) async {
    final r = await _dio.get<Object?>('/goals', queryParameters: {
      if (periodType != null) 'period_type': periodType,
      if (periodStart != null) 'period_start': periodStart,
      if (parentId != null) 'parent_id': parentId,
    });
    return [
      for (final g in (r.data as List? ?? const []))
        PlanGoal.fromJson(g as Map<String, dynamic>),
    ];
  }

  /// `POST /goals`.
  Future<void> createGoal({
    required String periodType,
    required String periodStart,
    required String title,
    String? parentId,
  }) =>
      _dio.post<Object?>('/goals', data: {
        if (parentId != null) 'parent_id': parentId,
        'period_type': periodType,
        'period_start': periodStart,
        'title': title,
      });

  /// `POST /goals/bulk`: one goal for each of [titles], all in one period.
  Future<void> createGoals({
    required String periodType,
    required String periodStart,
    required List<String> titles,
    String? parentId,
  }) =>
      _dio.post<Object?>('/goals/bulk', data: {
        if (parentId != null) 'parent_id': parentId,
        'period_type': periodType,
        'period_start': periodStart,
        'titles': titles,
      });

  /// `PATCH /goals/{id}` with new text. A null field stays as it is.
  Future<void> updateGoal(String id,
          {String? title, String? description, String? criteria}) =>
      _dio.patch<Object?>('/goals/$id', data: {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (criteria != null) 'criteria': criteria,
      });

  /// `PATCH /goals/{id}` with a new [status] (`active`, `done`, `dropped`).
  Future<void> setGoalStatus(String id, String status) =>
      _dio.patch<Object?>('/goals/$id', data: {'status': status});

  /// `DELETE /goals/{id}`; child goals are deleted too. [deleteTasks]
  /// decides what happens to linked tasks.
  Future<void> deleteGoal(String id, {required bool deleteTasks}) =>
      _dio.delete<Object?>('/goals/$id',
          queryParameters: {'linked_tasks': deleteTasks ? 'delete' : 'keep'});

  /// `POST /goals/{id}/breakdown`.
  Future<void> breakdownGoal(
          String id, List<GoalDraft> goals, List<TaskDraft> tasks) =>
      _dio.post<Object?>('/goals/$id/breakdown', data: {
        'goals': [for (final g in goals) g.toJson()],
        'tasks': [for (final t in tasks) t.toJson()],
      });

  /// `PATCH /tasks/{id}` with a goal id; null removes the link.
  Future<void> linkTaskToGoal(String id, String? goalId) =>
      _dio.patch<Object?>('/tasks/$id', data: {'goal_id': goalId});

  /// `GET /calendar` for `[from, to)`.
  Future<List<CalendarItem>> calendar(DateTime from, DateTime to) async {
    final r = await _dio.get<Object?>('/calendar', queryParameters: {
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
    });
    return [
      for (final i in (r.data as List? ?? const []))
        CalendarItem.fromJson(i as Map<String, dynamic>),
    ];
  }

  /// `GET /tasks` for the planner: open tasks by [due] filter or by title
  /// search [query]. A non-empty [query] searches all open tasks and the
  /// server ignores [due].
  Future<List<PlanTask>> tasks({String? due, String? query}) async {
    final r = await _dio.get<Object?>('/tasks', queryParameters: {
      if (due != null) 'due': due,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    });
    return [
      for (final t in (r.data as List? ?? const []))
        PlanTask.fromJson(t as Map<String, dynamic>),
    ];
  }

  /// `GET /tasks/{id}`: one task with all its fields.
  Future<PlanTask> task(String id) async {
    final r = await _dio.get<Object?>('/tasks/$id');
    return PlanTask.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `GET /tasks/counts`: open tasks per planner filter, keyed by the
  /// filter's API value.
  Future<Map<String, int>> taskCounts() async {
    final r = await _dio.get<Object?>('/tasks/counts');
    final data = r.data as Map<String, dynamic>? ?? const {};
    return {for (final e in data.entries) e.key: (e.value as num).toInt()};
  }

  /// `GET /me/settings`.
  Future<UserSettings> settings() async {
    final r = await _dio.get<Object?>('/me/settings');
    return UserSettings.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `PATCH /me/settings`.
  Future<UserSettings> updateSettings(
      {required bool randomTimeOnDateDrop}) async {
    final r = await _dio.patch<Object?>('/me/settings',
        data: {'random_time_on_date_drop': randomTimeOnDateDrop});
    return UserSettings.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `POST /tasks`. With a [containerId] the task goes into that project,
  /// else into the first one; unknown [labels] are created in the task app.
  /// Answers the new task.
  Future<PlanTask> createTask({
    required String connectionId,
    required String title,
    String? containerId,
    List<String> labels = const [],
  }) async {
    final r = await _dio.post<Object?>('/tasks', data: {
      'connection_id': connectionId,
      'title': title,
      if (containerId != null) 'container_id': containerId,
      if (labels.isNotEmpty) 'labels': labels,
    });
    return PlanTask.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `GET /connections/{id}/labels`: the labels that exist in the task app.
  Future<List<String>> labels(String connectionId) async {
    final r = await _dio.get<Object?>('/connections/$connectionId/labels');
    return [for (final l in (r.data as List? ?? const [])) '$l'];
  }

  /// `PATCH /tasks/{id}` with a new [title] and [description]. The server
  /// writes them to the task app first; a failure changes nothing.
  Future<void> updateTask(String id,
          {required String title, required String description}) =>
      _dio.patch<Object?>('/tasks/$id',
          data: {'title': title, 'description': description});

  /// `POST /tasks/{id}/complete`.
  Future<void> completeTask(String id) =>
      _dio.post<Object?>('/tasks/$id/complete');

  /// `POST /tasks/{id}/reopen`: marks a done task open again.
  Future<void> reopenTask(String id) => _dio.post<Object?>('/tasks/$id/reopen');

  /// `DELETE /tasks/{id}`.
  Future<void> deleteTask(String id) => _dio.delete<Object?>('/tasks/$id');

  /// `PUT /tasks/{id}/schedule` with a block [start]. The server stores the
  /// due date one hour later. Never creates a calendar event.
  Future<void> scheduleTaskAt(String id, DateTime start) =>
      _dio.put<Object?>('/tasks/$id/schedule',
          data: {'start': start.toUtc().toIso8601String()});

  /// `PUT /tasks/{id}/schedule` for a date only. The server stores an
  /// all-day due date, or a random time if the user's setting is on.
  Future<void> scheduleTaskOnDate(String id, DateTime day) =>
      _dio.put<Object?>('/tasks/$id/schedule', data: {'date': dateKey(day)});

  /// `DELETE /tasks/{id}/schedule`.
  Future<void> unscheduleTask(String id) =>
      _dio.delete<Object?>('/tasks/$id/schedule');

  /// `POST /notes/daily/{date}/append`.
  Future<void> appendToDailyNote(String date, String text) =>
      _dio.post<Object?>('/notes/daily/$date/append', data: {'text': text});

  /// `GET /conflicts`.
  Future<List<SyncConflict>> conflicts() async {
    final r = await _dio.get<Object?>('/conflicts');
    return [
      for (final c in (r.data as List? ?? const []))
        SyncConflict.fromJson(c as Map<String, dynamic>),
    ];
  }

  /// `POST /conflicts/{id}/resolve` with `keep_local` or `keep_remote`.
  Future<void> resolveConflict(String id, {required bool keepLocal}) =>
      _dio.post<Object?>('/conflicts/$id/resolve', data: {
        'resolution': keepLocal ? 'keep_local' : 'keep_remote',
      });
}

/// Provides the planning API; override [dioProvider] in tests.
final planningApiProvider =
    Provider<PlanningApi>((ref) => PlanningApi(ref.watch(dioProvider)));
