/// Typed calls to the plan and review endpoints, and their providers.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'review_models.dart';

/// Wraps the plan, review and retrospective endpoints. Failed calls throw
/// [DioException]; nothing is queued.
class ReviewApi {
  /// Creates the API using [_dio].
  ReviewApi(this._dio);

  final Dio _dio;

  /// `GET /reviews/history`: every plan, newest period first.
  Future<List<PlanHistoryEntry>> history() async {
    final r = await _dio.get<Object?>('/reviews/history');
    return [
      for (final p in (r.data as List? ?? const []))
        PlanHistoryEntry.fromJson(p as Map<String, dynamic>),
    ];
  }

  /// `POST /plans`.
  Future<void> createPlan({
    required String periodType,
    required String periodStart,
    required String title,
  }) =>
      _dio.post<Object?>('/plans', data: {
        'period_type': periodType,
        'period_start': periodStart,
        'title': title,
      });

  /// `GET /plans/{id}/review`; [refresh] computes it again.
  Future<PlanReview> review(String planId, {bool refresh = false}) async {
    final r = await _dio.get<Object?>('/plans/$planId/review',
        queryParameters: {if (refresh) 'refresh': 'true'});
    return PlanReview.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `PUT /plans/{id}/review/retrospective`: saves it to the note app.
  Future<PlanReview> saveRetrospective(String planId, String body) async {
    final r = await _dio.put<Object?>('/plans/$planId/review/retrospective',
        data: {'body': body});
    return PlanReview.fromJson(r.data! as Map<String, dynamic>);
  }
}

/// Provides the review API; override [dioProvider] in tests.
final reviewApiProvider =
    Provider<ReviewApi>((ref) => ReviewApi(ref.watch(dioProvider)));

/// Loads the plan history.
final planHistoryProvider = FutureProvider<List<PlanHistoryEntry>>(
    (ref) => ref.watch(reviewApiProvider).history());

/// Loads the stored review of one plan (generated the first time).
final planReviewProvider = FutureProvider.family<PlanReview, String>(
    (ref, planId) => ref.watch(reviewApiProvider).review(planId));
