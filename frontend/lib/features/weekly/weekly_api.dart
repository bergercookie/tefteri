/// Typed calls to the weekly planning endpoints, and the state they feed.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/api_error.dart';
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
  Future<List<MilestoneCandidate>> candidates(String week) async {
    final r = await _dio.get<Object?>('/weekly/$week/candidates');
    // The list may come inside an object that also holds `unsorted_count`.
    final data = r.data;
    final list = data is Map ? data['candidates'] ?? data['items'] : data;
    return [
      for (final c in (list as List? ?? const []))
        MilestoneCandidate.fromJson(c as Map<String, dynamic>),
    ];
  }

  /// `GET /weekly/{week}/themes`: the groups of the picker.
  Future<WeeklyThemes> themes(String week) async => WeeklyThemes.fromJson(
      (await _dio.get<Object?>('/weekly/$week/themes')).data!
          as Map<String, dynamic>);

  /// `POST /weekly/{week}/projects`: adds a milestone to the week. An
  /// unsorted project is labelled milestone by the same call. The cap does
  /// not apply.
  Future<WeeklyState> addProject(String week, String containerId) async =>
      _state(await _dio.post<Object?>('/weekly/$week/projects',
          data: {'container_id': containerId}));

  /// `DELETE /weekly/{week}/projects/{id}`.
  Future<WeeklyState> removeProject(String week, String projectId) async =>
      _state(await _dio.delete<Object?>('/weekly/$week/projects/$projectId'));

  /// `POST /weekly/{week}/milestones`: creates the sub-project under the theme
  /// [parentId] in the task app, labels it milestone and adds it to the week.
  Future<WeeklyState> createMilestone(
          String week, String parentId, String name, String doneState) async =>
      _state(await _dio.post<Object?>('/weekly/$week/milestones', data: {
        'parent_id': parentId,
        'name': name,
        'done_state': doneState,
      }));

  /// `POST /weekly/{week}/projects/{planProjectId}/tasks`: creates a task
  /// under the milestone in the task app. It is not committed until it has a
  /// day.
  Future<WeeklyState> addTask(
          String week, String planProjectId, String title) async =>
      _state(await _dio.post<Object?>(
          '/weekly/$week/projects/$planProjectId/tasks',
          data: {'title': title}));

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

  /// `POST /weekly/{week}/start`: starts the plan of the week (does nothing
  /// when it exists). A week with no milestone needs it before the commit.
  Future<WeeklyState> start(String week) async =>
      _state(await _dio.post<Object?>('/weekly/$week/start'));

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

  /// `POST /weekly/reviews/{planId}`; answers with the new history and what
  /// the save changed.
  Future<ReviewResult> review(String planId, List<LookBackAnswer> answers,
          String reflection) async =>
      ReviewResult.fromJson(
          (await _dio.post<Object?>('/weekly/reviews/$planId', data: {
        'projects': [for (final a in answers) a.toJson()],
        'reflection': reflection,
      }))
              .data! as Map<String, dynamic>);

  /// `POST /milestones/{id}/close` as a dry run: what the close would move.
  Future<ClosePreview> closePreview(String milestoneId) async =>
      ClosePreview.fromJson((await _dio.post<Object?>(
              '/milestones/$milestoneId/close',
              data: {'dry_run': true, 'confirm': false}))
          .data! as Map<String, dynamic>);

  /// `POST /milestones/{id}/close` with `confirm`: moves the open tasks to the
  /// theme, then closes. A failure part way throws [DioException]; read it with
  /// [CloseFailure.fromBody].
  Future<CloseResult> closeMilestone(String milestoneId) async =>
      CloseResult.fromJson((await _dio.post<Object?>(
              '/milestones/$milestoneId/close',
              data: {'dry_run': false, 'confirm': true}))
          .data! as Map<String, dynamic>);

  /// `POST /milestones/{id}/reopen`: undoes a close.
  Future<ReopenResult> reopenMilestone(String milestoneId) async =>
      ReopenResult.fromJson(
          (await _dio.post<Object?>('/milestones/$milestoneId/reopen')).data!
              as Map<String, dynamic>);

  /// `POST /milestones/{id}/done` as a dry run: what marking it done does.
  Future<DonePreview> doneEffect(String milestoneId) async =>
      DonePreview.fromJson((await _dio.post<Object?>(
              '/milestones/$milestoneId/done',
              data: {'dry_run': true}))
          .data! as Map<String, dynamic>);

  /// `POST /milestones/{id}/done`: marks the milestone done by hand.
  Future<void> markDone(String milestoneId) => _dio
      .post<Object?>('/milestones/$milestoneId/done', data: {'dry_run': false});
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

/// Milestones the user can pick for a week.
final weeklyCandidatesProvider = FutureProvider.autoDispose
    .family<List<MilestoneCandidate>, String>((ref, week) {
  return ref.watch(weeklyApiProvider).candidates(week);
});

/// The themes of the picker for a week, and whether focus data exists.
final weeklyThemesProvider =
    FutureProvider.autoDispose.family<WeeklyThemes, String>((ref, week) {
  return ref.watch(weeklyApiProvider).themes(week);
});

/// The reviewed weeks.
final weeklyHistoryProvider = FutureProvider.autoDispose<WeeklyHistory>(
    (ref) => ref.watch(weeklyApiProvider).history());
