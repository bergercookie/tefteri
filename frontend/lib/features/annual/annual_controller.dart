/// State of the annual plan screen and the read-only lists around it.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'annual_api.dart';
import 'annual_models.dart';

/// Loads the plan of one year and makes its changes. A write that fails
/// throws [DioException]; the screen shows the message and nothing changes.
class AnnualPlanController extends StateNotifier<AsyncValue<AnnualPlan>> {
  /// Creates the controller and loads [year].
  AnnualPlanController(this._api, this.year) : super(const AsyncLoading()) {
    load();
  }

  final AnnualApi _api;

  /// The planning year.
  final int year;

  /// Loads the plan; keeps what is shown when a reload fails.
  Future<void> load() async {
    try {
      final plan = await _api.plan(year);
      if (mounted) state = AsyncData(plan);
    } on DioException catch (e, st) {
      if (mounted && !state.hasValue) state = AsyncError(e, st);
    }
  }

  /// Shows the loading state and loads again (the "Try again" button).
  Future<void> retry() async {
    state = const AsyncLoading();
    await load();
  }

  Future<T> _then<T>(Future<T> call) async {
    final r = await call;
    await load();
    return r;
  }

  /// Creates [goals] in one batch.
  Future<String?> addGoals(List<GoalDraft> goals, {int? seededFrom}) async =>
      (await _then(_api.createGoals(year, goals, seededFrom: seededFrom)))
          .batchId;

  /// Changes the sentence of goal [goalId].
  Future<void> editGoal(String goalId, String title) =>
      _then(_api.editGoal(goalId, title));

  /// Adds a key result to goal [goalId].
  Future<KeyResult> addKeyResult(String goalId, KeyResultDraft draft) =>
      _then(_api.addKeyResult(goalId, draft));

  /// Changes the fields of key result [id] that are not null.
  Future<KeyResult> editKeyResult(String id,
          {String? metric,
          double? target,
          String? deadline,
          String? updateSource}) =>
      _then(_api.editKeyResult(id,
          metric: metric,
          target: target,
          deadline: deadline,
          updateSource: updateSource));

  /// Retires goal [goalId]; answers the batch to undo.
  Future<String?> retireGoal(String goalId, {String? reason}) async =>
      (await _then(_api.retireGoal(goalId, reason: reason))).$2;

  /// Retires key result [id]; answers the batch to undo.
  Future<String?> retireKeyResult(String id, {String? reason}) async =>
      (await _then(_api.retireKeyResult(id, reason: reason))).$2;

  /// Restores goal [goalId] with the key results it retired.
  Future<void> restoreGoal(String goalId) => _then(_api.restoreGoal(goalId));

  /// Restores key result [id].
  Future<void> restoreKeyResult(String id) => _then(_api.restoreKeyResult(id));

  /// Sets the linked themes of key result [id]; answers the batch to undo.
  Future<String?> setThemes(String id, List<String> themeIds) async =>
      (await _then(_api.setThemes(id, themeIds))).batchId;

  /// Adds themes to every active key result of goal [goalId]; answers the
  /// batch to undo.
  Future<String?> addGoalThemes(String goalId, List<String> themeIds) async =>
      (await _then(_api.addGoalThemes(goalId, themeIds))).batchId;

  /// Undoes one batch.
  Future<void> undo(String batchId) => _then(_api.undo(batchId));

  /// Stores a value for key result [id].
  Future<void> addValue(String id, double value, {String? date}) =>
      _then(_api.addValue(id, value, date: date));
}

/// The plan of one year.
final annualPlanProvider = StateNotifierProvider.autoDispose
    .family<AnnualPlanController, AsyncValue<AnnualPlan>, int>(
  (ref, year) => AnnualPlanController(ref.watch(annualApiProvider), year),
);

/// The themes the picker offers.
final themeChoicesProvider = FutureProvider.autoDispose<ThemeChoices>(
    (ref) => ref.watch(annualApiProvider).themes());

/// The history of one year, oldest first.
final planHistoryProvider = FutureProvider.autoDispose
    .family<List<PlanChange>, int>(
        (ref, year) => ref.watch(annualApiProvider).history(year));

/// The suggestions for a year from year N; the key is `(year, N)`.
final planSuggestionsProvider = FutureProvider.autoDispose
    .family<PlanSuggestions, (int, int)>((ref, key) =>
        ref.watch(annualApiProvider).suggestions(key.$1, fromYear: key.$2));

/// The old goal rows, read only.
final legacyGoalsProvider = FutureProvider.autoDispose<List<LegacyGoal>>(
    (ref) => ref.watch(annualApiProvider).legacyGoals());

/// The state of the push token.
final pushTokenProvider = FutureProvider.autoDispose<PushTokenInfo>(
    (ref) => ref.watch(annualApiProvider).pushToken());

/// The plan of one year, read only (the year view and the task goal picker).
final annualPlanReadProvider = FutureProvider.autoDispose
    .family<AnnualPlan, int>(
        (ref, year) => ref.watch(annualApiProvider).plan(year));
