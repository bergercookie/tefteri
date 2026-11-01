/// Typed calls to the documentation and process note endpoints.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/context_filter.dart';
import '../../core/planning_models.dart';

/// A note with the ids of the tasks it is linked to (`GET /notes/{id}`).
@immutable
class NoteDetail {
  /// Creates a detail.
  const NoteDetail({required this.note, required this.taskIds});

  /// Parses the note detail JSON.
  factory NoteDetail.fromJson(Map<String, dynamic> j) => NoteDetail(
        note: PlanNote.fromJson(j),
        taskIds: [for (final t in (j['task_ids'] as List? ?? const [])) '$t'],
      );

  /// The note.
  final PlanNote note;

  /// Linked task ids.
  final List<String> taskIds;
}

/// Wraps the note endpoints. Writes go to the note app first; failed calls
/// throw [DioException] and nothing is queued.
class NotesApi {
  /// Creates the API using [_dio].
  NotesApi(this._dio);

  final Dio _dio;

  /// `GET /notes` for one [kind] (all kinds when null).
  Future<List<PlanNote>> list(ContextFilter filter, {String? kind}) async {
    final r = await _dio.get<Object?>('/notes', queryParameters: {
      if (kind != null) 'kind': kind,
      ...filter.queryParameters,
    });
    return [
      for (final n in (r.data as List? ?? const []))
        PlanNote.fromJson(n as Map<String, dynamic>),
    ];
  }

  /// `GET /notes/{id}`.
  Future<NoteDetail> get(String id) async {
    final r = await _dio.get<Object?>('/notes/$id');
    return NoteDetail.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `POST /notes`; [kind] is `custom` (documentation) or `process`.
  Future<NoteDetail> create({
    required String title,
    required String body,
    required String kind,
    List<String> taskIds = const [],
  }) async {
    final r = await _dio.post<Object?>('/notes', data: {
      'title': title,
      'body': body,
      'kind': kind,
      'task_ids': taskIds,
    });
    return NoteDetail.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `PATCH /notes/{id}` with a new title and body.
  Future<NoteDetail> update(String id,
      {required String title, required String body}) async {
    final r = await _dio
        .patch<Object?>('/notes/$id', data: {'title': title, 'body': body});
    return NoteDetail.fromJson(r.data! as Map<String, dynamic>);
  }

  /// `DELETE /notes/{id}`.
  Future<void> delete(String id) => _dio.delete<Object?>('/notes/$id');

  /// `GET /tasks/{id}/notes`.
  Future<List<PlanNote>> forTask(String taskId) async {
    final r = await _dio.get<Object?>('/tasks/$taskId/notes');
    return [
      for (final n in (r.data as List? ?? const []))
        PlanNote.fromJson(n as Map<String, dynamic>),
    ];
  }

  /// `DELETE /tasks/{id}/notes/{noteId}`: removes the link only.
  Future<void> unlink(String taskId, String noteId) =>
      _dio.delete<Object?>('/tasks/$taskId/notes/$noteId');
}

/// Provides the notes API; override [dioProvider] in tests.
final notesApiProvider =
    Provider<NotesApi>((ref) => NotesApi(ref.watch(dioProvider)));

/// Loads notes of one kind (`null` for documentation and process notes
/// together). Reloads when the context filter changes.
final notesProvider =
    FutureProvider.family<List<PlanNote>, String?>((ref, kind) async {
  final filter = ref.watch(contextFilterProvider);
  final api = ref.watch(notesApiProvider);
  if (kind != null) return api.list(filter, kind: kind);
  final docs = await api.list(filter, kind: 'custom');
  final processes = await api.list(filter, kind: 'process');
  return [...docs, ...processes]..sort((a, b) => a.title.compareTo(b.title));
});

/// Loads one note with its linked tasks.
final noteDetailProvider = FutureProvider.family<NoteDetail, String>(
    (ref, id) => ref.watch(notesApiProvider).get(id));

/// Loads the notes linked to one task.
final taskNotesProvider = FutureProvider.family<List<PlanNote>, String>(
    (ref, taskId) => ref.watch(notesApiProvider).forTask(taskId));

/// User-facing name of a note kind.
String noteKindLabel(String kind) => switch (kind) {
      'process' => 'Process',
      'custom' => 'Documentation',
      'daily' => 'Daily note',
      'retrospective' => 'Retrospective',
      _ => kind,
    };
