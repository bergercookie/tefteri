/// Typed calls to the annual review endpoints (`/annual-review/...`).
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'annual_review_models.dart';

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Wraps the annual review endpoints. Failed calls throw [DioException].
class AnnualReviewApi {
  /// Creates the API using [_dio].
  const AnnualReviewApi(this._dio);

  final Dio _dio;

  /// `GET /annual-review/{year}`.
  Future<AnnualReview> review(int year) async => AnnualReview.fromJson(
      _map((await _dio.get<Object?>('/annual-review/$year')).data));

  /// `PUT /annual-review/{year}/notes`.
  Future<ReviewNote> putNote(int year,
      {String? goalId, required String body}) async {
    final note = _map((await _dio.put<Object?>('/annual-review/$year/notes',
            data: {'goal_id': goalId, 'body': body}))
        .data);
    return ReviewNote.fromJson(note);
  }

  /// `DELETE /annual-review/{year}/notes`: the text that was lost.
  Future<ReviewNote> deleteNote(int year, {String? goalId}) async {
    final body = _map((await _dio.delete<Object?>('/annual-review/$year/notes',
            queryParameters: {if (goalId != null) 'goal_id': goalId}))
        .data);
    return ReviewNote.fromJson(_map(body['deleted']));
  }
}

/// The annual review API.
final annualReviewApiProvider =
    Provider<AnnualReviewApi>((ref) => AnnualReviewApi(ref.watch(dioProvider)));
