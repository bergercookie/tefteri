import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/projects/projects_screen.dart';
import 'package:tefteri/theme/theme.dart';

import '../../support/fake_api.dart';

/// A small stateful stand-in for the `/projects` endpoints.
class ProjectsServer {
  ProjectsServer({
    List<Map<String, Object?>>? projects,
    this.canRename = true,
    this.canRestore = true,
    this.status = 'ok',
    this.lastSyncOutcome = 'ok',
  }) : projects = projects ?? defaultProjects();

  /// The default tree: two themes, three milestones, one routine-to-be.
  static List<Map<String, Object?>> defaultProjects() => [
        classifiedJson('p1', 'Open source', tasks: 4, subprojects: 2),
        classifiedJson('p2', 'Website', parent: 'p1', tasks: 3),
        classifiedJson('p3', 'Library', parent: 'p1', tasks: 1),
        classifiedJson('p4', 'Home', tasks: 2, subprojects: 1),
        classifiedJson('p5', 'Garden', parent: 'p4'),
        classifiedJson('p6', 'Groceries'),
      ];

  /// The projects, in tree order, as the server holds them.
  final List<Map<String, Object?>> projects;
  bool canRename;
  bool canRestore;

  /// Set to make the next write answer with this failure.
  ApiFailure? renameFailure;
  ApiFailure? saveFailure;

  /// Batches saved so far: id to the previous labels.
  final Map<String, Map<String, String?>> batches = {};
  final List<String> undone = [];
  final List<String> archived = [];
  final List<String> restored = [];
  int _batch = 0;

  Map<String, Object?> _p(String id) =>
      projects.firstWhere((p) => p['id'] == id);

  String _effective(Map<String, Object?> p) =>
      (p['label'] ?? (p['proposal']! as Map)['label']) as String;

  Map<String, Object?> _derived(Map<String, Object?> p) {
    String? theme;
    var cur = p['parent_id'] as String?;
    while (cur != null) {
      final a = _p(cur);
      if (_effective(a) == 'theme') {
        theme = cur;
        break;
      }
      cur = a['parent_id'] as String?;
    }
    return {
      ...p,
      'effective_label': _effective(p),
      'unsorted': p['label'] == null,
      'parent_theme_id': theme,
    };
  }

  /// Connection health at the last sync (`ok`, `needs_attention`, `error`).
  final String status;

  /// Why the last sync failed, or `ok`.
  final String lastSyncOutcome;

  Map<String, Object?> classification() => {
        'connections': [
          {
            'connection_id': 'c1',
            'name': 'Vikunja',
            'status': status,
            'last_sync_outcome': lastSyncOutcome,
            'capabilities': {'rename': canRename, 'restore': canRestore},
            'projects': [for (final p in projects) _derived(p)],
          },
        ],
        'unsorted_count': projects
            .where((p) => p['label'] == null && p['orphaned'] == null)
            .length,
      };

  Map<String, Object?> _effect(List changes) {
    final counts = <String, int>{};
    var plan = 0;
    var changed = 0;
    for (final c in changes) {
      final p = _p((c as Map)['id'] as String);
      final from = p['label'] as String?;
      final to = c['label'] as String?;
      if (from == to) continue;
      changed++;
      if (p['in_committed_plan'] == true) plan++;
      final k = '${from ?? 'none'}>${to ?? 'none'}';
      counts[k] = (counts[k] ?? 0) + 1;
    }
    return {
      'changed': changed,
      'by_change': [
        for (final e in counts.entries)
          {
            'from': e.key.split('>')[0],
            'to': e.key.split('>')[1],
            'count': e.value,
          },
      ],
      'in_committed_plan': plan,
    };
  }

  Map<String, Object> allRoutes() => {
        'GET /projects/classification': (RequestOptions o) => classification(),
        'PUT /projects/labels': (RequestOptions o) {
          if (saveFailure != null) return saveFailure;
          final body = o.data as Map;
          final changes = body['changes'] as List;
          final effect = _effect(changes);
          if (body['dry_run'] == true) {
            return {'batch_id': null, 'effect': effect};
          }
          final id = 'b${++_batch}';
          batches[id] = {
            for (final c in changes)
              (c as Map)['id'] as String:
                  _p(c['id'] as String)['label'] as String?,
          };
          for (final c in changes) {
            _p((c as Map)['id'] as String)['label'] = c['label'];
          }
          return {'batch_id': id, 'effect': effect};
        },
        'POST /projects/labels/undo': (RequestOptions o) {
          final id = (o.data as Map)['batch_id'] as String;
          if (undone.contains(id)) {
            return const ApiFailure.contract(
                409, 'already_undone', 'This change was already undone.');
          }
          undone.add(id);
          batches[id]!.forEach((pid, label) => _p(pid)['label'] = label);
          return {'restored': batches[id]!.length};
        },
        'POST /projects': (RequestOptions o) {
          final b = o.data as Map;
          projects.add(classifiedJson(
              'new${projects.length}', b['name'] as String,
              parent: b['parent_id'] as String?, label: b['label'] as String?));
          return projects.last;
        },
        for (final p in projects) ..._projectRoutes(p['id']! as String),
      };

  Map<String, Object> _projectRoutes(String id) => {
        'PATCH /projects/$id': (RequestOptions o) {
          if (!canRename) {
            return const ApiFailure.contract(
                409, 'not_supported', 'Your task app cannot rename projects.');
          }
          if (renameFailure != null) return renameFailure;
          _p(id)['name'] = (o.data as Map)['name'];
          return _derived(_p(id));
        },
        'POST /projects/$id/archive': (RequestOptions o) {
          archived.add(id);
          _p(id)['orphaned'] = {
            'reason': 'archived',
            'at': '2030-03-04T10:00:00Z'
          };
          return const NoContent();
        },
        'POST /projects/$id/restore': (RequestOptions o) {
          restored.add(id);
          _p(id)['orphaned'] = null;
          return const NoContent();
        },
      };
}

/// Pumps the Projects screen against [server] and answers the fake API.
Future<FakeApi> pumpProjects(
  WidgetTester tester,
  ProjectsServer server, {
  Size size = const Size(1000, 2400),
  Brightness brightness = Brightness.light,
  Map<String, Object?> extra = const {},
}) async {
  SharedPreferences.setMockInitialValues({});
  final api = FakeApi({...server.allRoutes(), ...extra});
  await pumpWithApi(
    tester,
    api,
    const ProjectsScreen(),
    size: size,
    theme: tefteriLight,
    darkTheme: tefteriDark,
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
  );
  return api;
}

/// Taps the widget with [key], scrolling it into view first.
Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pumpAndSettle();
}
