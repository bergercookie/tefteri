/// Typed calls to monthly planning, change history and review routes.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'month_models.dart';

/// Wraps `/monthly` routes. Failed calls throw [DioException].
class MonthApi {
  /// Creates the client using [_dio].
  const MonthApi(this._dio);

  final Dio _dio;

  /// `GET /monthly/{month}`.
  Future<MonthPlan> plan(String month) async =>
      MonthPlan.fromJson((await _dio.get<Object?>('/monthly/$month')).data!
          as Map<String, dynamic>);

  /// `GET /monthly/{month}/themes`, optionally narrowed by search.
  Future<MonthThemePicker> themes(String month,
      {String? query, String? connectionId}) async {
    final response =
        await _dio.get<Object?>('/monthly/$month/themes', queryParameters: {
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      if (connectionId != null) 'connection_id': connectionId,
    });
    return MonthThemePicker.fromJson(response.data! as Map<String, dynamic>);
  }

  /// `GET /monthly/{month}/suggestions`.
  Future<MonthSuggestions> suggestions(String month) async =>
      MonthSuggestions.fromJson(
          (await _dio.get<Object?>('/monthly/$month/suggestions')).data!
              as Map<String, dynamic>);

  /// Saves the whole focus; null targets remain "no target".
  Future<Map<String, dynamic>> saveFocus(
          String month, List<Map<String, Object?>> entries,
          {bool dryRun = false}) async =>
      (await _dio.put<Object?>('/monthly/$month/focus', data: {
        'entries': entries,
        'dry_run': dryRun,
      }))
          .data! as Map<String, dynamic>;

  /// Previews or applies one focus change.
  Future<Map<String, dynamic>> change(String month,
          {required String kind,
          String? outProjectId,
          String? inProjectId,
          Object? target,
          bool dryRun = false}) async =>
      (await _dio.post<Object?>('/monthly/$month/changes', data: {
        'kind': kind,
        'out_project_id': outProjectId,
        'in_project_id': inProjectId,
        'target': target,
        'dry_run': dryRun,
      }))
          .data! as Map<String, dynamic>;

  /// Undoes one focus-change batch.
  Future<Map<String, dynamic>> undo(String month, String batchId) async =>
      (await _dio.post<Object?>('/monthly/$month/changes/undo',
              data: {'batch_id': batchId}))
          .data! as Map<String, dynamic>;

  /// `GET /monthly/{month}/history`.
  Future<List<MonthFocusChange>> history(String month) async =>
      monthFocusChanges(
          (await _dio.get<Object?>('/monthly/$month/history')).data);

  /// Reads a stored review version or an unsaved live draft.
  Future<MonthReview> review(String month, {int? version}) async {
    final response = await _dio.get<Object?>('/monthly/$month/review',
        queryParameters: {if (version != null) 'version': version});
    return MonthReview.fromJson(response.data! as Map<String, dynamic>);
  }

  /// Previews or stores a review and its decisions.
  Future<Map<String, dynamic>> saveReview(
    String month, {
    required List<Map<String, Object?>> decisions,
    required Map<String, num> values,
    bool dryRun = false,
    bool confirmNewVersion = false,
  }) async =>
      (await _dio.post<Object?>('/monthly/$month/review', data: {
        'key_result_values': [
          for (final entry in values.entries)
            {'key_result_id': entry.key, 'value': entry.value},
        ],
        'decisions': decisions,
        'dry_run': dryRun,
        'confirm_new_version': confirmNewVersion,
      }))
          .data! as Map<String, dynamic>;

  /// Previews or selects an earlier stored snapshot version.
  Future<Map<String, dynamic>> makeCurrent(String month, int version,
          {bool dryRun = false}) async =>
      (await _dio.post<Object?>('/monthly/$month/review/current', data: {
        'version': version,
        'dry_run': dryRun,
      }))
          .data! as Map<String, dynamic>;

  /// Reads old monthly goals for the read-only earlier-format screen.
  Future<List<Map<String, dynamic>>> earlierGoals(String month) async =>
      monthLegacyGoals(
          (await _dio.get<Object?>('/goals/history', queryParameters: {
        'period_type': 'month',
        'period_start': '$month-01',
      }))
              .data);

  /// Creates a theme through the annual-planning route. The server creates
  /// the project in the task app before recording its theme label.
  Future<void> createTheme(String connectionId, String name) =>
      _dio.post<Object?>('/annual/themes',
          data: {'connection_id': connectionId, 'name': name});
}

/// The monthly API; tests can override the shared Dio provider.
final monthApiProvider =
    Provider<MonthApi>((ref) => MonthApi(ref.watch(dioProvider)));
