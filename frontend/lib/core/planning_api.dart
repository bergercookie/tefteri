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

  /// `GET /views/year/{year}`.
  Future<PeriodView> yearView(int year) => _period('/views/year/$year');

  Future<PeriodView> _period(String path) async {
    final r = await _dio.get<Object?>(path);
    return PeriodView.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `PATCH /tasks/{id}` with a goal id; null removes the link. Only an
  /// active goal of this year's annual plan can be linked.
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
  ///
  /// Sends only the settings that are given.
  Future<UserSettings> updateSettings({
    bool? randomTimeOnDateDrop,
    int? defaultReminderMinutes,
    Map<ChecklistKind, List<String>>? checklists,
  }) async {
    final r = await _dio.patch<Object?>('/me/settings', data: {
      if (checklists != null)
        'checklists': {for (final e in checklists.entries) e.key.name: e.value},
      if (randomTimeOnDateDrop != null)
        'random_time_on_date_drop': randomTimeOnDateDrop,
      if (defaultReminderMinutes != null)
        'default_reminder_minutes': defaultReminderMinutes,
    });
    return UserSettings.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `GET /checklists/{kind}/{day}`: the checklist of the week, month or
  /// year that holds [day].
  Future<PeriodChecklist> checklist(ChecklistKind kind, DateTime day) async {
    final r =
        await _dio.get<Object?>('/checklists/${kind.name}/${dateKey(day)}');
    return PeriodChecklist.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `PUT /checklists/{kind}/{day}/items`: ticks or unticks one item.
  Future<PeriodChecklist> tickChecklistItem(
      ChecklistKind kind, DateTime day, String text, bool checked) async {
    final r = await _dio.put<Object?>(
        '/checklists/${kind.name}/${dateKey(day)}/items',
        data: {'text': text, 'checked': checked});
    return PeriodChecklist.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `GET /tasks/{id}/reminder`: the reminder in the task app.
  Future<TaskReminder> taskReminder(String id) async {
    final r = await _dio.get<Object?>('/tasks/$id/reminder');
    return TaskReminder.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `PUT /tasks/{id}/reminder`: remind [minutesBefore] minutes before the
  /// due time, or by the user's default when it is null.
  Future<TaskReminder> setTaskReminder(String id, {int? minutesBefore}) async {
    final r = await _dio.put<Object?>('/tasks/$id/reminder',
        data: {if (minutesBefore != null) 'minutes_before': minutesBefore});
    return TaskReminder.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `DELETE /tasks/{id}/reminder`.
  Future<void> clearTaskReminder(String id) =>
      _dio.delete<Object?>('/tasks/$id/reminder');

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

  /// `PATCH /calendar/entries/{id}` with a new time. The event keeps its title.
  Future<void> moveEntry(String id, DateTime start, DateTime end) =>
      _dio.patch<Object?>('/calendar/entries/$id', data: {
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
      });

  /// `POST /calendar/entries`: a new event in a calendar of a connection.
  /// An all-day event covers the days from [start] to [end] (exclusive).
  Future<void> createEntry({
    required String connectionId,
    required String containerId,
    required String title,
    required DateTime start,
    required DateTime end,
    bool allDay = false,
    String location = '',
  }) =>
      _dio.post<Object?>('/calendar/entries', data: {
        'connection_id': connectionId,
        'container_id': containerId,
        'title': title,
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
        'all_day': allDay,
        if (location.isNotEmpty) 'location': location,
      });

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
