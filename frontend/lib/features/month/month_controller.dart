/// Per-month planning state and review drafts.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'month_api.dart';
import 'month_models.dart';

/// Loads and updates the plan for one month.
class MonthController extends StateNotifier<AsyncValue<MonthPlan>> {
  /// Creates a month controller and starts its initial read.
  MonthController(this._api, this.month) : super(const AsyncLoading()) {
    load();
  }

  final MonthApi _api;

  /// Month key in `YYYY-MM`.
  final String month;

  /// Reloads the month while keeping the current view on read failure.
  Future<void> load() async {
    try {
      final plan = await _api.plan(month);
      if (mounted) state = AsyncData(plan);
    } catch (error, stack) {
      if (mounted && !state.hasValue) state = AsyncError(error, stack);
    }
  }

  /// Saves the selected entries and publishes the returned plan.
  Future<void> saveFocus(List<Map<String, Object?>> entries) async {
    final result = await _api.saveFocus(month, entries);
    final saved = result['focus'];
    if (saved is Map) {
      state = AsyncData(MonthPlan.fromJson(Map<String, dynamic>.from(saved)));
    } else {
      await load();
    }
  }

  /// Applies a confirmed mid-month focus change and returns its effect data.
  Future<Map<String, dynamic>> change({
    required String kind,
    String? outProjectId,
    String? inProjectId,
    Object? target,
  }) async {
    final preview = await _api.change(month,
        kind: kind,
        outProjectId: outProjectId,
        inProjectId: inProjectId,
        target: target,
        dryRun: true);
    final result = await _api.change(month,
        kind: kind,
        outProjectId: outProjectId,
        inProjectId: inProjectId,
        target: target);
    final focus = result['focus'];
    if (focus is Map) {
      state = AsyncData(MonthPlan.fromJson(Map<String, dynamic>.from(focus)));
    } else {
      await load();
    }
    return {
      'batch_id': result['batch_id'],
      'effect': preview['effect'] ?? result['effect'],
    };
  }

  /// Undoes a focus change and updates the plan.
  Future<void> undo(String batchId) async {
    final result = await _api.undo(month, batchId);
    final focus = result['focus'];
    if (focus is Map) {
      state = AsyncData(MonthPlan.fromJson(Map<String, dynamic>.from(focus)));
    } else {
      await load();
    }
  }
}

/// Plan state, isolated by month key.
final monthPlanProvider = StateNotifierProvider.family<MonthController,
    AsyncValue<MonthPlan>, String>(
  (ref, month) => MonthController(ref.watch(monthApiProvider), month),
);

/// Suggestions remain separate from saved plan entries until Save.
final monthSuggestionsProvider =
    FutureProvider.family<MonthSuggestions, String>((ref, month) {
  return ref.watch(monthApiProvider).suggestions(month);
});

/// Reads the available theme choices for the monthly picker.
final monthThemesProvider =
    FutureProvider.family<MonthThemePicker, String>((ref, month) {
  return ref.watch(monthApiProvider).themes(month);
});

/// A review and its unsaved values/decisions for one month.
class MonthReviewController extends StateNotifier<AsyncValue<MonthReview>> {
  /// Creates a review controller and reads its current draft or snapshot.
  MonthReviewController(this._api, this.month) : super(const AsyncLoading()) {
    load();
  }

  final MonthApi _api;

  /// Month key in `YYYY-MM`.
  final String month;

  /// Manual values typed in the review, not yet saved to the series.
  final Map<String, num> values = {};

  /// Decisions edited in the review, including replacement ids.
  final Map<String, Map<String, Object?>> decisions = {};

  /// Loads a live draft or stored review.
  Future<void> load({int? version}) async {
    try {
      final review = await _api.review(month, version: version);
      if (mounted) state = AsyncData(review);
    } catch (error, stack) {
      if (mounted && !state.hasValue) state = AsyncError(error, stack);
    }
  }

  /// Keeps an unsaved value in the per-month review draft.
  void setValue(String keyResultId, num? value) {
    if (value == null) {
      values.remove(keyResultId);
    } else {
      values[keyResultId] = value;
    }
    if (mounted && state.hasValue) state = AsyncData(state.requireValue);
  }

  /// Keeps an unsaved decision in the per-month review draft.
  void setDecision(String projectId, String decision,
      {String? replacementProjectId}) {
    decisions[projectId] = {
      'project_id': projectId,
      'decision': decision,
      'replacement_project_id': replacementProjectId,
    };
    if (mounted && state.hasValue) state = AsyncData(state.requireValue);
  }

  /// Discards an unsaved decision.
  void clearDecision(String projectId) {
    decisions.remove(projectId);
    if (mounted && state.hasValue) state = AsyncData(state.requireValue);
  }

  /// Asks the server to build the review and decision effects without saving.
  Future<Map<String, dynamic>> preview({bool confirmNewVersion = false}) =>
      _api.saveReview(
        month,
        decisions: decisions.values.toList(),
        values: values,
        dryRun: true,
        confirmNewVersion: confirmNewVersion,
      );

  /// Saves the review draft after the caller has shown the appropriate
  /// effect/confirmation. Returns the server response.
  Future<Map<String, dynamic>> save({bool confirmNewVersion = false}) async {
    final result = await _api.saveReview(
      month,
      decisions: decisions.values.toList(),
      values: values,
      confirmNewVersion: confirmNewVersion,
    );
    values.clear();
    decisions.clear();
    await load();
    return result;
  }

  /// Changes the current snapshot version.
  Future<void> makeCurrent(int version) async {
    await _api.makeCurrent(month, version);
    await load();
  }
}

/// Review state and editable draft retained separately for each month.
final monthReviewProvider = StateNotifierProvider.family<MonthReviewController,
    AsyncValue<MonthReview>, String>(
  (ref, month) => MonthReviewController(ref.watch(monthApiProvider), month),
);
