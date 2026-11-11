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

  /// Whether the server knows the monthly focus.
  bool focusKnown = false;

  /// The themes of the picker. Empty: derived from the projects.
  List<Map<String, Object?>> themes = [];

  /// Projects without a label, as the picker counts them.
  int unsortedCount = 0;

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

  /// A theme of the picker.
  static Map<String, Object?> theme(String id, String name,
          {bool? inFocus, int milestones = 0}) =>
      {
        'id': 'th-$id',
        'container_id': id,
        'connection_id': 'c1',
        'name': name,
        'in_focus': inFocus,
        'milestones': milestones,
        'open_milestones': milestones,
      };

  /// A milestone project. [theme] is the id of a theme made with [theme].
  /// [kind] `unsorted` is a project without a label.
  static Map<String, Object?> project(String id, String name,
          {int tasks = 0,
          String? parent,
          String? theme,
          String? themeName,
          String? doneState,
          String kind = 'milestone',
          String state = 'active',
          int rollover = 0,
          bool needsRescope = false,
          bool decisionOpen = false,
          bool? inFocus}) =>
      {
        'id': id,
        'name': name,
        'parent': parent,
        'theme': theme,
        'theme_name': themeName,
        'done_state': doneState,
        'kind': kind,
        'state': state,
        'rollover': rollover,
        'needs_rescope': needsRescope,
        'decision_open': decisionOpen,
        'in_focus': inFocus,
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
    final themeId = p['theme'] as String?;
    final inFocus = p['in_focus'] as bool?;
    return {
      'id': 'pp-$id',
      'container_id': id,
      'milestone_id': 'm-$id',
      'milestone_state': p['state'],
      'done_state': p['done_state'],
      'theme': themeId == null
          ? null
          : {'id': 'th-$themeId', 'name': p['theme_name']},
      'outside_focus': focusKnown && themeId != null && inFocus == false,
      'rollover_count': p['rollover'],
      'needs_rescope': p['needs_rescope'],
      'orphaned': false,
      'notice': null,
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
                'milestone_count': chosen.length,
                'milestone_cap': 3,
                'over_cap': chosen.length > 3,
                'month': '2030-03-01',
                'focus_known': focusKnown,
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
                if (p['kind'] != 'theme')
                  {
                    'container_id': p['id'],
                    'connection_id': 'c1',
                    'connection_name': 'Vikunja',
                    'name': p['name'],
                    'path': p['parent'] == null
                        ? p['name']
                        : '${p['parent']} › ${p['name']}',
                    'kind': p['kind'],
                    'milestone_id':
                        p['kind'] == 'unsorted' ? null : 'm-${p['id']}',
                    'done_state': p['done_state'],
                    'state': p['state'],
                    'theme': p['theme'] == null
                        ? null
                        : {'id': 'th-${p['theme']}', 'name': p['theme_name']},
                    'in_focus': focusKnown ? p['in_focus'] : null,
                    'rollover_count': p['rollover'],
                    'needs_rescope': p['needs_rescope'],
                    'decision_open': p['decision_open'],
                    'open_tasks': (p['tasks']! as List).length,
                    'carried_tasks': p['carried'] ?? 0,
                    'selected': chosen.contains(p['id']),
                    'unsorted': p['kind'] == 'unsorted',
                  },
            ],
        'GET /weekly/$weekKey/themes': (RequestOptions o) => {
              'focus_known': focusKnown,
              'themes': themes,
              'unsorted_count': unsortedCount,
            },
        'POST /weekly/$weekKey/projects': (RequestOptions o) {
          final id = (o.data as Map)['container_id'] as String;
          // The cap only warns: a fourth milestone is accepted.
          if (!chosen.contains(id)) {
            chosen.add(id);
          }
          return state();
        },
        'POST /weekly/$weekKey/milestones': (RequestOptions o) {
          final body = o.data as Map;
          final done = '${body['done_state'] ?? ''}'.trim();
          if (done.isEmpty) {
            return const ApiFailure(
                422,
                'A milestone needs a done-state, for example "ship the login '
                    'flow".',
                'done_state_required');
          }
          final parent =
              projects.firstWhere((p) => p['id'] == body['parent_id']);
          final p = project('new1', '${body['name']}',
              parent: '${parent['name']}',
              theme: parent['id'] as String,
              themeName: '${parent['name']}',
              doneState: done)
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
    for (final p in [
      ...projects,
      // A project that a test creates later (the routes are fixed now).
      {'id': 'new1'},
    ]) {
      final pid = p['id'] as String;
      r['DELETE /weekly/$weekKey/projects/pp-$pid'] = (RequestOptions o) {
        chosen.remove(pid);
        return state();
      };
      r['POST /weekly/$weekKey/projects/pp-$pid/tasks'] = (RequestOptions o) {
        final title = '${(o.data as Map)['title']}'.trim();
        if (title.isEmpty) return _fail(422, 'Write a title for the task.');
        final tasks =
            projects.firstWhere((x) => x['id'] == pid)['tasks']! as List;
        tasks.add({'id': '$pid-t${tasks.length + 1}', 'title': title});
        return state();
      };
      if (p['tasks'] == null) continue;
      r['POST /connections/c1/containers/$pid/archive'] = (RequestOptions o) {
        projects.removeWhere((x) => x['id'] == pid);
        chosen.remove(pid);
        return const NoContent();
      };
      // Tasks that a test adds later have no route yet, so the first ids of
      // every project are ready.
      final ids = {
        for (final t in p['tasks']! as List) (t as Map)['id'] as String,
        for (var i = 1; i <= 8; i++) '$pid-t$i',
      };
      for (final id in ids) {
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
        r['GET /tasks/$id'] = (RequestOptions o) => taskJson(id, 'Task $id');
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

/// One milestone of a look-back. Defaults: unfinished, under the theme
/// Work, close allowed.
Map<String, Object?> lookBackProject(String id, String name,
        {int committed = 3,
        int done = 1,
        bool completed = false,
        String? doneState,
        Map<String, Object?>? theme = const {'id': 'th-work', 'name': 'Work'},
        String state = 'active',
        String? decision,
        bool legacy = false,
        bool noMilestone = false,
        int rollover = 0,
        bool needsRescope = false,
        Map<String, Object?>? close,
        List<Map<String, Object?>>? leftover}) =>
    {
      'id': id,
      'milestone_id': noMilestone ? null : 'm-$id',
      'name': name,
      'done_state': doneState,
      'theme': theme,
      'milestone_state': noMilestone ? null : state,
      'committed': committed,
      'done': done,
      'completed': completed,
      'outcome': null,
      'decision': decision,
      'expected_rollover': false,
      'legacy': legacy || noMilestone,
      'rollover_count': rollover,
      'needs_rescope': needsRescope,
      'outside_focus': false,
      'close': close ??
          {
            'available': theme != null,
            'reason': theme == null ? 'no_theme' : null,
            'open_tasks': committed - done,
            'theme_name': theme?['name'],
          },
      'leftover': leftover ??
          [
            for (var i = 1; i <= committed - done; i++)
              {
                'id': '$id-l$i',
                'title': '$name left $i',
                'due_day': '2030-02-26',
                'planned_day': '2030-02-26'
              },
          ],
    };

/// The numbers of a review.
Map<String, Object?> sampleSummary(
        {int committed = 7,
        int done = 5,
        int milestones = 2,
        int milestonesDone = 1,
        double? focusShare,
        String? note}) =>
    {
      'committed_tasks': committed,
      'done_tasks': done,
      'milestones_committed': milestones,
      'milestones_done': milestonesDone,
      'pace': [
        {'day': '2030-02-25', 'done': 1},
        {'day': '2030-02-26', 'done': 2},
        {'day': '2030-02-27', 'done': 0},
        {'day': '2030-02-28', 'done': 2},
      ],
      'focus_share': focusShare,
      'note': note,
    };

/// A look-back at the week of 2030-02-25 with two milestones: Website is done,
/// Garden has two tasks left.
Map<String, Object?> sampleLookBack(
        {bool reviewed = false,
        Map<String, Object?>? summary,
        List<Map<String, Object?>>? projects}) =>
    {
      'plan_id': 'old1',
      'week_start': '2030-02-25',
      'reviewed': reviewed,
      'reflection': '',
      'summary': summary ?? sampleSummary(),
      'projects': projects ??
          [
            lookBackProject('op1', 'Website',
                committed: 4,
                done: 4,
                completed: true,
                state: 'done',
                doneState: 'The new site is live'),
            lookBackProject('op2', 'Garden',
                doneState: 'The beds are planted',
                leftover: [
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
                ]),
          ],
    };

/// The answer of a saved review: the history plus what the save changed.
Map<String, Object?> reviewAnswer(
        {List<Object?> notices = const [],
        List<Object?> nudges = const [],
        List<Object?> entries = const []}) =>
    {
      'entries': entries,
      'totals': {
        'weeks': entries.length,
        'committed_projects': 0,
        'done_projects': 0,
        'committed_tasks': 0,
        'done_tasks': 0,
      },
      'notices': notices,
      'nudges': nudges,
    };
