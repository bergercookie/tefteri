/// The projects and labels that the new task dialog suggests.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/planning_api.dart';

/// A project of a task app that a new task can go into.
class TaskProject {
  /// Creates a project.
  const TaskProject({
    required this.connectionId,
    required this.connectionName,
    required this.containerId,
    required this.path,
  });

  /// Id of the connection that holds the project.
  final String connectionId;

  /// Name of that connection.
  final String connectionName;

  /// Id of the project in tefteri.
  final String containerId;

  /// Name with the names of the projects around it, such as `Website › Launch`.
  final String path;
}

/// Every project of every task connection, ordered by path. A subproject has
/// the path of its parents in front of its name.
final taskProjectsProvider = FutureProvider<List<TaskProject>>((ref) async {
  final dio = ref.watch(dioProvider);
  final connections = await _list(dio, '/connections');
  final out = <TaskProject>[];
  for (final c in connections) {
    if (c['kind'] != 'tasks') continue;
    final id = '${c['id']}';
    final containers = await _list(dio, '/connections/$id/containers');
    final byRemote = {for (final p in containers) '${p['remote_id']}': p};
    String pathOf(Map<String, dynamic> p) {
      final names = ['${p['name']}'];
      var parent = byRemote['${p['parent_remote_id']}'];
      // The depth limit protects against a loop in bad data.
      for (var i = 0; parent != null && i < 10; i++) {
        names.add('${parent['name']}');
        parent = byRemote['${parent['parent_remote_id']}'];
      }
      return names.reversed.join(' › ');
    }

    for (final p in containers) {
      out.add(TaskProject(
        connectionId: id,
        connectionName: '${c['display_name']}',
        containerId: '${p['id']}',
        path: pathOf(p),
      ));
    }
  }
  out.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
  return out;
});

Future<List<Map<String, dynamic>>> _list(Dio dio, String path) async {
  final r = await dio.get<Object?>(path);
  return [
    for (final e in (r.data as List? ?? const [])) e as Map<String, dynamic>,
  ];
}

/// The labels that exist in the task app of a connection.
final taskLabelsProvider = FutureProvider.family<List<String>, String>(
    (ref, connectionId) => ref.watch(planningApiProvider).labels(connectionId));

/// The project that the last new task went into: the next one starts there.
final lastProjectProvider = StateProvider<String?>((_) => null);
