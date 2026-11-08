import 'package:dio/dio.dart';

import '../../support/fake_api.dart';

/// A far-away week, so that no day of it is in the past.
const weekKey = '2030-03-04';

/// A small stateful stand-in for the `/weekly` endpoints.
class WeeklyServer {
  WeeklyServer({List<Map<String, Object?>>? projects, this.lookBack}) {
    this.projects = projects ??
        [
          project('p1', 'Website', tasks: 2),
          project('p2', 'Garden', tasks: 1),
          project('p3', 'Taxes', tasks: 0),
          project('p4', 'Inbox', tasks: 3),
        ];
  }

  /// Every project of the user, with its open tasks.
  late List<Map<String, Object?>> projects;

  /// The task day by task id (`YYYY-MM-DD`), as the task app has it.
  final Map<String, String> days = {};

  /// Ids of committed tasks that are done by now.
  final Set<String> doneTasks = {};

  /// Ids of the tasks that were set aside.
  final Set<String> parked = {};

  /// Ids of the tasks marked done from the planning page.
  final Set<String> completedHere = {};

  /// Ids of the projects chosen for the week, in order.
  final List<String> chosen = [];

  Map<String, Object?>? lookBack;
  String status = 'draft';
  bool started = false;
  bool skipped = false;
  Map<String, Object?> history = {
    'entries': <Object?>[],
    'totals': _totals(0, 0, 0, 0, 0),
  };

  static Map<String, Object?> _totals(int w, int cp, int dp, int ct, int dt) =>
      {
        'weeks': w,
        'committed_projects': cp,
        'done_projects': dp,
        'committed_tasks': ct,
        'done_tasks': dt,
      };

  static Map<String, Object?> project(String id, String name,
          {int tasks = 0, String? parent}) =>
      {
        'id': id,
        'name': name,
        'parent': parent,
        'tasks': [
          for (var i = 1; i <= tasks; i++)
            {'id': '$id-t$i', 'title': '$name task $i'},
        ],
      };

  Map<String, Object?> _task(Map<String, Object?> t) {
    final day = days[t['id']];
    return {
      'id': t['id'],
      'title': t['title'],
      'due_day': day,
      'planned_day': day,
      'parked': parked.contains(t['id']),
      'url': null,
    };
  }

  Map<String, Object?> _planProject(String id) {
    final p = projects.firstWhere((p) => p['id'] == id);
    final tasks = [
      for (final t in p['tasks']! as List)
        if (!completedHere.contains((t as Map)['id']))
          _task(t as Map<String, Object?>)
    ];
    final active = tasks.where((t) => t['parked'] != true).toList();
    return {
      'id': 'pp-$id',
      'container_id': id,
      'name': p['name'],
      'created_here': p['created_here'] == true,
      'url': 'http://vikunja.test/projects/$id',
      'open_tasks': active.length,
      'done_tasks': (p['tasks']! as List)
          .where((t) => completedHere.contains((t as Map)['id']))
          .length,
      'parked_tasks': tasks.length - active.length,
      'scheduled_tasks': active.where((t) => t['planned_day'] != null).length,
      'tasks': tasks,
      'committed_tasks': status == 'committed'
          ? [
              for (final t in tasks)
                if (t['planned_day'] != null)
                  {...t, 'done': doneTasks.contains(t['id'])},
              for (final done in doneTasks)
                if (done.startsWith('$id-'))
                  {
                    'id': done,
                    'title': 'Finished task',
                    'planned_day': '2030-03-05',
                    'done': true
                  },
            ]
          : <Object?>[],
    };
  }

  Map<String, Object?> state() => {
        'week_start': weekKey,
        'week_end': '2030-03-11',
        'plan': started || chosen.isNotEmpty
            ? {
                'id': 'plan1',
                'status': status,
                'committed_at':
                    status == 'committed' ? '2030-03-03T10:00:00Z' : null,
                'retro_skipped': skipped,
                'max_projects': 3,
                'projects': [for (final id in chosen) _planProject(id)],
              }
            : null,
        'look_back': lookBack,
      };

  Object? _fail(int status, String detail) =>
      ApiFailure(status, detail, 'invalid');

  Map<String, Object?> routes() => {
        'GET /weekly/$weekKey': (RequestOptions o) => state(),
        'POST /weekly/$weekKey/refresh': (RequestOptions o) => state(),
        'POST /weekly/$weekKey/start': (RequestOptions o) {
          started = true;
          return state();
        },
        'GET /weekly/$weekKey/candidates': (RequestOptions o) => [
              for (final p in projects)
                {
                  'container_id': p['id'],
                  'connection_id': 'c1',
                  'connection_name': 'Vikunja',
                  'name': p['name'],
                  'path': p['parent'] == null
                      ? p['name']
                      : '${p['parent']} › ${p['name']}',
                  'open_tasks': (p['tasks']! as List).length,
                  'carried_tasks': p['carried'] ?? 0,
                  'selected': chosen.contains(p['id']),
                },
            ],
        'POST /weekly/$weekKey/projects': (RequestOptions o) {
          final id = (o.data as Map)['container_id'] as String;
          if (chosen.length >= 3) {
            return _fail(422, 'Choose at most 3 projects.');
          }
          if (!chosen.contains(id)) {
            chosen.add(id);
          }
          return state();
        },
        'DELETE /weekly/$weekKey/projects/pp-p1': (RequestOptions o) {
          chosen.remove('p1');
          return state();
        },
        'DELETE /weekly/$weekKey/projects/pp-p2': (RequestOptions o) {
          chosen.remove('p2');
          return state();
        },
        'POST /weekly/$weekKey/subprojects': (RequestOptions o) {
          final body = o.data as Map;
          final parent =
              projects.firstWhere((p) => p['id'] == body['parent_id']);
          final p =
              project('new1', '${body['name']}', parent: '${parent['name']}')
                ..['created_here'] = true;
          projects.add(p);
          chosen.add('new1');
          return state();
        },
        'POST /weekly/$weekKey/spread': (RequestOptions o) {
          var n = 0;
          for (final id in chosen) {
            for (final t in projects.firstWhere((p) => p['id'] == id)['tasks']!
                as List) {
              final tid = (t as Map)['id'] as String;
              if (parked.contains(tid) || completedHere.contains(tid)) continue;
              days.putIfAbsent(tid, () => '2030-03-0${5 + n++ % 5}');
            }
          }
          return state();
        },
        'POST /weekly/$weekKey/commit': (RequestOptions o) {
          status = 'committed';
          return state();
        },
        'POST /weekly/$weekKey/reopen': (RequestOptions o) {
          status = 'draft';
          return state();
        },
        'POST /weekly/$weekKey/skip-look-back': (RequestOptions o) {
          skipped = true;
          started = true;
          return state();
        },
        'PUT /tasks/:id/schedule': null,
        'GET /weekly/history': (RequestOptions o) => history,
      };

  /// Adds the task routes for every task id the server knows.
  Map<String, Object?> allRoutes() {
    final r = routes()..remove('PUT /tasks/:id/schedule');
    for (final p in projects) {
      final pid = p['id'] as String;
      r['POST /connections/c1/containers/$pid/archive'] = (RequestOptions o) {
        projects.removeWhere((x) => x['id'] == pid);
        chosen.remove(pid);
        return const NoContent();
      };
      for (final t in p['tasks']! as List) {
        final id = (t as Map)['id'] as String;
        r['PUT /weekly/$weekKey/tasks/$id/parked'] = (RequestOptions o) {
          if ((o.data as Map)['parked'] == true) {
            parked.add(id);
          } else {
            parked.remove(id);
          }
          return state();
        };
        r['POST /tasks/$id/complete'] = (RequestOptions o) {
          completedHere.add(id);
          return taskJson(id, 'x');
        };
        r['GET /tasks/$id'] =
            (RequestOptions o) => taskJson(id, '${t['title']}');
        r['PUT /tasks/$id/schedule'] = (RequestOptions o) {
          days[id] = (o.data as Map)['date'] as String;
          return taskJson(id, 'x');
        };
        r['DELETE /tasks/$id/schedule'] = (RequestOptions o) {
          days.remove(id);
          return taskJson(id, 'x');
        };
      }
    }
    return r;
  }
}

/// A look-back at the week of 2030-02-25 with two projects.
Map<String, Object?> sampleLookBack({bool reviewed = false}) => {
      'plan_id': 'old1',
      'week_start': '2030-02-25',
      'reviewed': reviewed,
      'reflection': '',
      'projects': [
        {
          'id': 'op1',
          'name': 'Website',
          'committed': 4,
          'done': 4,
          'completed': true,
          'outcome': null,
          'leftover_action': null,
          'leftover': <Object?>[],
        },
        {
          'id': 'op2',
          'name': 'Garden',
          'committed': 3,
          'done': 1,
          'completed': false,
          'outcome': null,
          'leftover_action': null,
          'leftover': [
            {
              'id': 'g1',
              'title': 'Prune roses',
              'due_day': '2030-02-26',
              'planned_day': '2030-02-26'
            },
            {
              'id': 'g2',
              'title': 'Buy soil',
              'due_day': '2030-02-27',
              'planned_day': '2030-02-27'
            },
          ],
        },
      ],
    };
