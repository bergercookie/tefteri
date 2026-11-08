/// Typed calls to the weekly planning endpoints, and the state they feed.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/api_error.dart';
import '../../core/context_filter.dart';
import '../../core/planning_api.dart';
import 'weekly_models.dart';

/// Wraps the `/weekly` endpoints. Failed calls throw [DioException].
class WeeklyApi {
  /// Creates the API using [_dio].
  WeeklyApi(this._dio);

  final Dio _dio;

  WeeklyState _state(Response<Object?> r) =>
      WeeklyState.fromJson(r.data! as Map<String, dynamic>);

  /// `GET /weekly/{week}`.
  Future<WeeklyState> state(String week) async =>
      _state(await _dio.get<Object?>('/weekly/$week'));

  /// `POST /weekly/{week}/refresh`: reads the chosen projects again.
  Future<WeeklyState> refresh(String week) async =>
      _state(await _dio.post<Object?>('/weekly/$week/refresh'));

  /// `GET /weekly/{week}/candidates`.
  Future<List<WeeklyCandidate>> candidates(
      String week, ContextFilter filter) async {
    final r = await _dio.get<Object?>('/weekly/$week/candidates',
        queryParameters: filter.queryParameters);
    return [
      for (final c in (r.data as List? ?? const []))
        WeeklyCandidate.fromJson(c as Map<String, dynamic>),
    ];
  }

  /// `POST /weekly/{week}/projects`.
  Future<WeeklyState> addProject(String week, String containerId) async =>
      _state(await _dio.post<Object?>('/weekly/$week/projects',
          data: {'container_id': containerId}));

  /// `DELETE /weekly/{week}/projects/{id}`.
  Future<WeeklyState> removeProject(String week, String projectId) async =>
      _state(await _dio.delete<Object?>('/weekly/$week/projects/$projectId'));

  /// `POST /weekly/{week}/subprojects`.
  Future<WeeklyState> createSubproject(
          String week, String parentId, String name) async =>
      _state(await _dio.post<Object?>('/weekly/$week/subprojects',
          data: {'parent_id': parentId, 'name': name}));

  /// `POST /connections/{connectionId}/containers/{containerId}/archive`:
  /// archives the project in the task app. The task app can restore it.
  Future<void> archiveProject(String connectionId, String containerId) =>
      _dio.post<Object?>(
          '/connections/$connectionId/containers/$containerId/archive');

  /// `PUT /weekly/{week}/tasks/{id}/parked`: sets a task aside, or puts it back.
  Future<WeeklyState> parkTask(String week, String taskId, bool parked) async =>
      _state(await _dio.put<Object?>('/weekly/$week/tasks/$taskId/parked',
          data: {'parked': parked}));

  /// Marks a task done in the task app, then reads the week again.
  Future<WeeklyState> completeTask(String week, String taskId) async {
    await _dio.post<Object?>('/tasks/$taskId/complete');
    return state(week);
  }

  /// `POST /weekly/{week}/spread`.
  Future<WeeklyState> spread(String week) async =>
      _state(await _dio.post<Object?>('/weekly/$week/spread'));

  /// `POST /weekly/{week}/commit`.
  Future<WeeklyState> commit(String week) async =>
      _state(await _dio.post<Object?>('/weekly/$week/commit'));

  /// `POST /weekly/{week}/reopen`.
  Future<WeeklyState> reopen(String week) async =>
      _state(await _dio.post<Object?>('/weekly/$week/reopen'));

  /// `POST /weekly/{week}/skip-look-back`.
  Future<WeeklyState> skipLookBack(String week) async =>
      _state(await _dio.post<Object?>('/weekly/$week/skip-look-back'));

  /// `GET /weekly/history`.
  Future<WeeklyHistory> history() async =>
      WeeklyHistory.fromJson((await _dio.get<Object?>('/weekly/history')).data!
          as Map<String, dynamic>);

  /// `POST /weekly/reviews/{planId}`; answers with the new history.
  Future<WeeklyHistory> review(String planId, List<LookBackAnswer> answers,
          String reflection) async =>
      WeeklyHistory.fromJson(
          (await _dio.post<Object?>('/weekly/reviews/$planId', data: {
        'projects': [for (final a in answers) a.toJson()],
        'reflection': reflection,
      }))
              .data! as Map<String, dynamic>);
}

/// Provides the weekly API; override [dioProvider] in tests.
final weeklyApiProvider =
    Provider<WeeklyApi>((ref) => WeeklyApi(ref.watch(dioProvider)));

/// How often the open planning page reads the chosen projects again from
/// the task app. Null turns the polling off (tests).
final weeklyPollIntervalProvider =
    Provider<Duration?>((_) => const Duration(seconds: 5));

/// The state of one week, keyed by its Monday (`YYYY-MM-DD`). Every change
/// answers with the new state, which replaces the old one at once.
class WeeklyController extends StateNotifier<AsyncValue<WeeklyState>> {
  /// Creates the controller and loads the week.
  WeeklyController(this._api, this._planning, this.week)
      : super(const AsyncLoading()) {
    load();
  }

  final WeeklyApi _api;
  final PlanningApi _planning;

  /// Monday of the week, `YYYY-MM-DD`.
  final String week;

  /// When the chosen projects were last read from the task app.
  DateTime? refreshedAt;

  /// Loads the state; keeps the old one on a failed reload.
  Future<void> load() async {
    try {
      final s = await _api.state(week);
      if (mounted) state = AsyncData(s);
    } on DioException catch (e, st) {
      if (mounted && !state.hasValue) state = AsyncError(e, st);
    }
  }

  /// Runs [call] and shows the state it answers with. Returns the error
  /// message when it failed, else null.
  Future<String?> apply(
      Future<WeeklyState> Function(WeeklyApi api) call) async {
    try {
      final s = await call(_api);
      if (mounted) state = AsyncData(s);
      return null;
    } on DioException catch (e) {
      // A failed write may have happened in part (a spread gives some tasks a
      // day before one fails), so read the state again.
      load();
      return apiErrorMessage(e);
    }
  }

  /// Gives [taskId] the day [day], or no day when [day] is null.
  Future<String?> setDay(String taskId, DateTime? day) => apply((api) async {
        if (day == null) {
          await _planning.unscheduleTask(taskId);
        } else {
          await _planning.scheduleTaskOnDate(taskId, day);
        }
        return api.state(week);
      });

  /// Reads the chosen projects again from the task app. A failure is
  /// ignored: the next poll tries again, and the old state stays.
  Future<void> poll() async {
    try {
      final s = await _api.refresh(week);
      if (!mounted) return;
      refreshedAt = DateTime.now();
      state = AsyncData(s);
    } on DioException {
      // Keep what is shown.
    }
  }
}

/// The controller of the week with the given Monday.
final weeklyStateProvider = StateNotifierProvider.autoDispose
    .family<WeeklyController, AsyncValue<WeeklyState>, String>(
  (ref, week) => WeeklyController(
      ref.watch(weeklyApiProvider), ref.watch(planningApiProvider), week),
);

/// Projects the user can pick for a week, for the context filter.
final weeklyCandidatesProvider = FutureProvider.autoDispose
    .family<List<WeeklyCandidate>, String>((ref, week) {
  final filter = ref.watch(contextFilterProvider);
  return ref.watch(weeklyApiProvider).candidates(week, filter);
});

/// The reviewed weeks.
final weeklyHistoryProvider = FutureProvider.autoDispose<WeeklyHistory>(
    (ref) => ref.watch(weeklyApiProvider).history());
