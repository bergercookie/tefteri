/// Typed calls to the annual plan endpoints (`/annual/...`, `/goals/history`).
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'annual_models.dart';

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// The answer of a write that can be undone: the batch and its effect.
typedef Batch = ({String? batchId, Map<String, dynamic> body});

/// Wraps the annual plan endpoints. Failed calls throw [DioException]; nothing
/// is queued or retried.
class AnnualApi {
  /// Creates the API using [_dio].
  const AnnualApi(this._dio);

  final Dio _dio;

  Batch _batch(Response<Object?> r) {
    final body = _map(r.data);
    final id = body['batch_id'];
    return (batchId: id == null ? null : '$id', body: body);
  }

  /// `GET /annual/{year}`.
  Future<AnnualPlan> plan(int year) async => AnnualPlan.fromJson(
      _map((await _dio.get<Object?>('/annual/$year')).data));

  /// `GET /annual/{year}/history`, oldest first.
  Future<List<PlanChange>> history(int year,
      {String? goalId, String? keyResultId}) async {
    final r =
        await _dio.get<Object?>('/annual/$year/history', queryParameters: {
      if (goalId != null) 'goal_id': goalId,
      if (keyResultId != null) 'key_result_id': keyResultId,
    });
    final data = r.data;
    final list = data is Map ? data['changes'] : data;
    return [
      for (final c in (list as List? ?? const []))
        if (c is Map) PlanChange.fromJson(Map<String, dynamic>.from(c)),
    ];
  }

  /// `GET /annual/{year}/suggestions`; [fromYear] defaults to the year before.
  Future<PlanSuggestions> suggestions(int year, {int? fromYear}) async =>
      PlanSuggestions.fromJson(_map((await _dio.get<Object?>(
              '/annual/$year/suggestions',
              queryParameters: {if (fromYear != null) 'from_year': fromYear}))
          .data));

  /// `POST /annual/{year}/goals/bulk`: all goals in one batch, all or none.
  Future<Batch> createGoals(int year, List<GoalDraft> goals,
          {int? seededFrom}) async =>
      _batch(await _dio.post<Object?>('/annual/$year/goals/bulk', data: {
        if (seededFrom != null) 'seeded_from': seededFrom,
        'goals': [for (final g in goals) g.toJson()],
      }));

  /// `PATCH /annual/goals/{id}`.
  Future<void> editGoal(String goalId, String title) =>
      _dio.patch<Object?>('/annual/goals/$goalId', data: {'title': title});

  /// `POST /annual/goals/{id}/key-results`.
  Future<KeyResult> addKeyResult(String goalId, KeyResultDraft draft) async =>
      KeyResult.fromJson(_map((await _dio.post<Object?>(
              '/annual/goals/$goalId/key-results',
              data: draft.toJson()))
          .data));

  /// `PATCH /annual/key-results/{id}` with the changed fields only.
  Future<KeyResult> editKeyResult(String id,
          {String? metric,
          double? target,
          String? deadline,
          String? updateSource}) async =>
      KeyResult.fromJson(
          _map((await _dio.patch<Object?>('/annual/key-results/$id', data: {
        if (metric != null) 'metric': metric,
        if (target != null) 'target': target,
        if (deadline != null) 'deadline': deadline,
        if (updateSource != null) 'update_source': updateSource,
      }))
              .data));

  /// `POST /annual/goals/{id}/retire`. With [dryRun] nothing is written.
  Future<(RetireEffect, String?)> retireGoal(String goalId,
      {String? reason, bool dryRun = false}) async {
    final b = _batch(await _dio.post<Object?>('/annual/goals/$goalId/retire',
        data: {'reason': reason, 'dry_run': dryRun}));
    return (RetireEffect.fromJson(b.body['effect']), b.batchId);
  }

  /// `POST /annual/key-results/{id}/retire`. With [dryRun] nothing is written.
  Future<(RetireEffect, String?)> retireKeyResult(String id,
      {String? reason, bool dryRun = false}) async {
    final b = _batch(await _dio.post<Object?>('/annual/key-results/$id/retire',
        data: {'reason': reason, 'dry_run': dryRun}));
    return (RetireEffect.fromJson(b.body['effect']), b.batchId);
  }

  /// `POST /annual/goals/{id}/restore`.
  Future<Map<String, dynamic>> restoreGoal(String goalId) async =>
      _map((await _dio.post<Object?>('/annual/goals/$goalId/restore')).data);

  /// `POST /annual/key-results/{id}/restore`.
  Future<Map<String, dynamic>> restoreKeyResult(String id) async =>
      _map((await _dio.post<Object?>('/annual/key-results/$id/restore')).data);

  /// `PUT /annual/key-results/{id}/themes` with a dry run: what would change.
  Future<LinkEffect> previewThemes(String id, List<String> themeIds) async {
    final r = await _dio.put<Object?>('/annual/key-results/$id/themes',
        data: {'theme_ids': themeIds, 'dry_run': true});
    return LinkEffect.fromJson(_map(r.data)['effect']);
  }

  /// `PUT /annual/key-results/{id}/themes`: sets the active links.
  Future<Batch> setThemes(String id, List<String> themeIds) async =>
      _batch(await _dio.put<Object?>('/annual/key-results/$id/themes',
          data: {'theme_ids': themeIds, 'dry_run': false}));

  /// `PUT /annual/goals/{id}/themes`: adds the themes to every active key
  /// result of the goal. Existing links stay.
  Future<Batch> addGoalThemes(String goalId, List<String> themeIds) async =>
      _batch(await _dio.put<Object?>('/annual/goals/$goalId/themes',
          data: {'theme_ids': themeIds}));

  /// `POST /annual/undo`.
  Future<int> undo(String batchId) async {
    final r =
        await _dio.post<Object?>('/annual/undo', data: {'batch_id': batchId});
    return (_map(r.data)['restored'] as num?)?.toInt() ?? 0;
  }

  /// `GET /annual/themes`.
  Future<ThemeChoices> themes() async => ThemeChoices.fromJson(
      _map((await _dio.get<Object?>('/annual/themes')).data));

  /// `POST /annual/themes`: creates a top-level project labelled theme.
  Future<ThemeOption> createTheme(String connectionId, String name) async =>
      ThemeOption.fromJson(_map((await _dio.post<Object?>('/annual/themes',
              data: {'connection_id': connectionId, 'name': name}))
          .data));

  /// `POST /annual/key-results/{id}/values`. [date] defaults to today.
  Future<KeyResult?> addValue(String id, double value, {String? date}) async {
    final r = await _dio.post<Object?>('/annual/key-results/$id/values',
        data: {'value': value, if (date != null) 'date': date});
    final kr = _map(r.data)['key_result'];
    return kr is Map ? KeyResult.fromJson(Map<String, dynamic>.from(kr)) : null;
  }

  /// `GET /annual/push-token`.
  Future<PushTokenInfo> pushToken() async => PushTokenInfo.fromJson(
      _map((await _dio.get<Object?>('/annual/push-token')).data));

  /// `POST /annual/push-token`: a new token, shown once. Answers the token
  /// and its hint.
  Future<({String token, String hint})> createPushToken() async {
    final j = _map((await _dio.post<Object?>('/annual/push-token')).data);
    return (token: '${j['token'] ?? ''}', hint: '${j['hint'] ?? ''}');
  }

  /// `DELETE /annual/push-token`.
  Future<void> deletePushToken() => _dio.delete<Object?>('/annual/push-token');

  /// `GET /goals/history`: the old goal rows, read only.
  Future<List<LegacyGoal>> legacyGoals() async {
    final r = await _dio.get<Object?>('/goals/history');
    return [
      for (final g in (r.data as List? ?? const []))
        if (g is Map) LegacyGoal.fromJson(Map<String, dynamic>.from(g)),
    ];
  }
}

/// Provides the annual API; override [dioProvider] in tests.
final annualApiProvider =
    Provider<AnnualApi>((ref) => AnnualApi(ref.watch(dioProvider)));
