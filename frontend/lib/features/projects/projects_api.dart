/// Typed calls to the project classification endpoints, and their providers.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/api_error.dart';
import 'projects_models.dart';

/// Wraps the `/projects` endpoints. Failed calls throw [DioException].
class ProjectsApi {
  /// Creates the API using [_dio].
  const ProjectsApi(this._dio);

  final Dio _dio;

  /// `GET /projects/classification`.
  Future<Classification> classification({String? connectionId}) async {
    final r = await _dio.get<Object?>('/projects/classification',
        queryParameters: {
          if (connectionId != null) 'connection_id': connectionId
        });
    return Classification.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `PUT /projects/labels`. With [dryRun] nothing is written and the answer
  /// holds only the effect.
  Future<SaveResult> saveLabels(List<LabelChange> changes,
      {bool dryRun = false, String source = 'user'}) async {
    final r = await _dio.put<Object?>('/projects/labels', data: {
      'changes': [for (final c in changes) c.toJson()],
      'dry_run': dryRun,
      'source': source,
    });
    return SaveResult.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `POST /projects/labels/undo`; answers how many labels came back.
  Future<int> undo(String batchId) async {
    final r = await _dio
        .post<Object?>('/projects/labels/undo', data: {'batch_id': batchId});
    final data = r.data;
    return data is Map ? (data['restored'] as num? ?? 0).toInt() : 0;
  }

  /// `PATCH /projects/{id}`: renames in the task app first.
  Future<void> rename(String id, String name) =>
      _dio.patch<Object?>('/projects/$id', data: {'name': name});

  /// `POST /projects`: creates the project in the task app, then labels it.
  Future<void> create(
          {required String connectionId,
          required String name,
          String? parentId,
          required ProjectLabel label}) =>
      _dio.post<Object?>('/projects', data: {
        'connection_id': connectionId,
        'name': name,
        'parent_id': parentId,
        'label': label.api,
      });

  /// `POST /projects/{id}/archive`.
  Future<void> archive(String id) =>
      _dio.post<Object?>('/projects/$id/archive');

  /// `POST /projects/{id}/restore`.
  Future<void> restore(String id) =>
      _dio.post<Object?>('/projects/$id/restore');
}

/// Provides the projects API; override [dioProvider] in tests.
final projectsApiProvider =
    Provider<ProjectsApi>((ref) => ProjectsApi(ref.watch(dioProvider)));

/// How many projects have no label yet. A failed call counts as none, so a
/// reminder never shows a problem of its own.
final unsortedCountProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    return (await ref.watch(projectsApiProvider).classification())
        .unsortedCount;
  } on DioException {
    return 0;
  }
});

/// A message for a failed project action: what happened and what to do.
/// [what] finishes the sentence "Tefteri could not ...".
String projectsError(Object error, String what) {
  if (error is DioException && error.response == null) {
    return 'Tefteri could not $what because it cannot reach the server. '
        'Nothing was changed. Check your connection and try again.';
  }
  final code = apiErrorCode(error);
  final status = error is DioException ? error.response?.statusCode : null;
  final text = apiErrorMessage(error);
  final fallback = text == 'Cannot reach the server.' || text.isEmpty;
  if (code == 'not_supported') {
    return fallback
        ? 'Your task app does not support this. Nothing was changed.'
        : text;
  }
  if (status == 404) {
    return fallback
        ? 'That project is not in Tefteri any more, so Tefteri could not '
            '$what. Sync, then try again.'
        : text;
  }
  if (!fallback) return text;
  return 'Tefteri could not $what. Nothing was changed. Try again in a '
      'moment, and sync if it keeps failing.';
}
