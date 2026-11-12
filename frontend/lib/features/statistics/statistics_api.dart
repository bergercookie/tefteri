/// Typed calls to the statistics endpoints.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'statistics_models.dart';

/// Wraps `GET /statistics` and `GET /statistics/tasks`. Failed calls throw
/// [DioException]. Nothing here writes.
class StatisticsApi {
  /// Creates the API using [_dio].
  const StatisticsApi(this._dio);

  final Dio _dio;

  /// `GET /statistics`: the counts of the [period] (`week`, `month` or
  /// `year`) that holds [day] (`YYYY-MM-DD`).
  Future<StatisticsSummary> summary(String period, String day) async {
    final r = await _dio.get<Object?>('/statistics',
        queryParameters: {'period': period, 'day': day});
    return StatisticsSummary.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `GET /statistics/tasks`: one page of the completed tasks behind a count.
  /// Without [category] the page holds the three work categories.
  Future<StatTasksPage> tasks({
    required String period,
    required String day,
    Category? category,
    String order = 'newest',
    int? limit,
    String? cursor,
  }) async {
    final r = await _dio.get<Object?>('/statistics/tasks', queryParameters: {
      'period': period,
      'day': day,
      if (category != null) 'category': category.json,
      'order': order,
      if (limit != null) 'limit': limit,
      if (cursor != null) 'cursor': cursor,
    });
    return StatTasksPage.fromJson(r.data! as Map<String, dynamic>);
  }
}

/// Provides the statistics API; override [dioProvider] in tests.
final statisticsApiProvider =
    Provider<StatisticsApi>((ref) => StatisticsApi(ref.watch(dioProvider)));
