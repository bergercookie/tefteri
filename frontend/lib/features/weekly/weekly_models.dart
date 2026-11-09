/// Models of the weekly planning workflow, as the backend sends them.
library;

import 'package:flutter/foundation.dart';

DateTime? _day(Object? v) => v == null ? null : DateTime.tryParse('$v');

/// A task of a chosen project.
@immutable
class WeeklyTask {
  /// Creates a task.
  const WeeklyTask({
    required this.id,
    required this.title,
    this.dueDay,
    this.plannedDay,
    this.done = false,
    this.parked = false,
    this.url,
  });

  /// Parses a task JSON object.
  factory WeeklyTask.fromJson(Map<String, dynamic> j) => WeeklyTask(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        dueDay: _day(j['due_day']),
        plannedDay: _day(j['planned_day']),
        done: j['done'] == true,
        parked: j['parked'] == true,
        url: j['url'] as String?,
      );

  /// The task is finished.
  final bool done;

  /// The user set the task aside for this plan.
  final bool parked;

  /// Task id.
  final String id;

  /// Task title.
  final String title;

  /// The day of its due date, even when that day is not in the week.
  final DateTime? dueDay;

  /// The day in the planned week, or null when it has no day in that week.
  final DateTime? plannedDay;

  /// Page of the task in the task app.
  final String? url;
}

/// A project chosen for the week.
@immutable
class WeeklyProject {
  /// Creates a project.
  const WeeklyProject({
    required this.id,
    required this.name,
    required this.createdHere,
    required this.openTasks,
    required this.doneTasks,
    required this.scheduledTasks,
    required this.tasks,
    this.parkedTasks = 0,
    this.committedTasks = const [],
    this.containerId,
    this.color,
    this.url,
  });

  /// Parses a project JSON object.
  factory WeeklyProject.fromJson(Map<String, dynamic> j) => WeeklyProject(
        id: '${j['id']}',
        containerId: j['container_id'] == null ? null : '${j['container_id']}',
        name: '${j['name'] ?? ''}',
        color: j['color'] as String?,
        createdHere: j['created_here'] == true,
        url: j['url'] as String?,
        openTasks: (j['open_tasks'] as num? ?? 0).toInt(),
        doneTasks: (j['done_tasks'] as num? ?? 0).toInt(),
        scheduledTasks: (j['scheduled_tasks'] as num? ?? 0).toInt(),
        parkedTasks: (j['parked_tasks'] as num? ?? 0).toInt(),
        tasks: [
          for (final t in (j['tasks'] as List? ?? const []))
            WeeklyTask.fromJson(t as Map<String, dynamic>),
        ],
        committedTasks: [
          for (final t in (j['committed_tasks'] as List? ?? const []))
            WeeklyTask.fromJson(t as Map<String, dynamic>),
        ],
      );

  /// Id of the project in this plan.
  final String id;

  /// Id of the project in tefteri.
  final String? containerId;

  /// Project name.
  final String name;

  /// The color of the project in the task app, as `#rrggbb`, or null.
  final String? color;

  /// True when this planning session created the project.
  final bool createdHere;

  /// Page of the project in the task app.
  final String? url;

  /// Open tasks in the project.
  final int openTasks;

  /// Finished tasks in the project.
  final int doneTasks;

  /// Open tasks that have a day in the week.
  final int scheduledTasks;

  /// How many open tasks the user set aside.
  final int parkedTasks;

  /// The open tasks that are part of the plan (not parked).
  List<WeeklyTask> get activeTasks => [
        for (final t in tasks)
          if (!t.parked) t
      ];

  /// The open tasks.
  final List<WeeklyTask> tasks;

  /// The tasks that were planned at the commit, done or not.
  final List<WeeklyTask> committedTasks;

  /// Open tasks that have no day in the week.
  int get unscheduledTasks => openTasks - scheduledTasks;
}

/// The plan of one week.
@immutable
class WeeklyPlan {
  /// Creates a plan.
  const WeeklyPlan({
    required this.id,
    required this.status,
    required this.retroSkipped,
    required this.maxProjects,
    required this.projects,
    this.committedAt,
  });

  /// Parses a plan JSON object.
  factory WeeklyPlan.fromJson(Map<String, dynamic> j) => WeeklyPlan(
        id: '${j['id']}',
        status: '${j['status']}',
        committedAt: _day(j['committed_at']),
        retroSkipped: j['retro_skipped'] == true,
        maxProjects: (j['max_projects'] as num? ?? 3).toInt(),
        projects: [
          for (final p in (j['projects'] as List? ?? const []))
            WeeklyProject.fromJson(p as Map<String, dynamic>),
        ],
      );

  /// Plan id.
  final String id;

  /// `draft` or `committed`.
  final String status;

  /// When the plan was committed.
  final DateTime? committedAt;

  /// The user chose not to look back at the week before.
  final bool retroSkipped;

  /// How many projects a week can hold.
  final int maxProjects;

  /// The chosen projects.
  final List<WeeklyProject> projects;

  /// True after the commit.
  bool get committed => status == 'committed';

  /// Open tasks with a day in the week, over all projects.
  int get plannedTasks => projects.fold(0, (a, p) => a + p.scheduledTasks);

  /// Open tasks without a day in the week, over all projects.
  int get unscheduledTasks =>
      projects.fold(0, (a, p) => a + p.unscheduledTasks);

  /// Open tasks over all projects.
  int get openTasks => projects.fold(0, (a, p) => a + p.openTasks);

  /// Tasks that were planned at the commit.
  int get committedCount =>
      projects.fold(0, (a, p) => a + p.committedTasks.length);

  /// Committed tasks that are done now.
  int get committedDone => projects.fold(
      0, (a, p) => a + p.committedTasks.where((t) => t.done).length);
}

/// How a project of the earlier week went.
@immutable
class LookBackProject {
  /// Creates a project.
  const LookBackProject({
    required this.id,
    required this.name,
    required this.committed,
    required this.done,
    required this.completed,
    required this.leftover,
    this.outcome,
    this.leftoverAction,
    this.color,
  });

  /// Parses a project JSON object.
  factory LookBackProject.fromJson(Map<String, dynamic> j) => LookBackProject(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        color: j['color'] as String?,
        committed: (j['committed'] as num? ?? 0).toInt(),
        done: (j['done'] as num? ?? 0).toInt(),
        completed: j['completed'] == true,
        outcome: j['outcome'] as String?,
        leftoverAction: j['leftover_action'] as String?,
        leftover: [
          for (final t in (j['leftover'] as List? ?? const []))
            WeeklyTask.fromJson(t as Map<String, dynamic>),
        ],
      );

  /// Id of the project in its plan.
  final String id;

  /// Project name.
  final String name;

  /// The color of the project in the task app, as `#rrggbb`, or null.
  final String? color;

  /// Tasks that were planned for the week.
  final int committed;

  /// Planned tasks that are done.
  final int done;

  /// All planned tasks are done, or the user said the project is done.
  final bool completed;

  /// `done` or `not_done` once reviewed.
  final String? outcome;

  /// `carry` or `backlog` once reviewed.
  final String? leftoverAction;

  /// Planned tasks that are still open.
  final List<WeeklyTask> leftover;
}

/// The earlier week that the user looks back at.
@immutable
class LookBack {
  /// Creates a look-back.
  const LookBack({
    required this.planId,
    required this.weekStart,
    required this.reviewed,
    required this.reflection,
    required this.projects,
  });

  /// Parses a look-back JSON object.
  factory LookBack.fromJson(Map<String, dynamic> j) => LookBack(
        planId: '${j['plan_id']}',
        weekStart: DateTime.parse('${j['week_start']}'),
        reviewed: j['reviewed'] == true,
        reflection: '${j['reflection'] ?? ''}',
        projects: [
          for (final p in (j['projects'] as List? ?? const []))
            LookBackProject.fromJson(p as Map<String, dynamic>),
        ],
      );

  /// Id of the plan of the earlier week.
  final String planId;

  /// Monday of the earlier week.
  final DateTime weekStart;

  /// The user already looked back at it.
  final bool reviewed;

  /// What the user wrote when looking back.
  final String reflection;

  /// Its projects.
  final List<LookBackProject> projects;
}

/// Everything the planning page shows for one week.
@immutable
class WeeklyState {
  /// Creates a state.
  const WeeklyState({
    required this.weekStart,
    required this.weekEnd,
    this.plan,
    this.lookBack,
  });

  /// Parses the state JSON object.
  factory WeeklyState.fromJson(Map<String, dynamic> j) => WeeklyState(
        weekStart: DateTime.parse('${j['week_start']}'),
        weekEnd: DateTime.parse('${j['week_end']}'),
        plan: j['plan'] == null
            ? null
            : WeeklyPlan.fromJson(j['plan'] as Map<String, dynamic>),
        lookBack: j['look_back'] == null
            ? null
            : LookBack.fromJson(j['look_back'] as Map<String, dynamic>),
      );

  /// Monday of the week.
  final DateTime weekStart;

  /// Monday after the week.
  final DateTime weekEnd;

  /// The plan, once started.
  final WeeklyPlan? plan;

  /// The earlier committed week, if there is one.
  final LookBack? lookBack;

  /// The look-back is settled: nothing to review, done, or skipped.
  bool get lookBackSettled =>
      lookBack == null || lookBack!.reviewed || (plan?.retroSkipped ?? false);
}

/// A project the user can pick.
@immutable
class WeeklyCandidate {
  /// Creates a candidate.
  const WeeklyCandidate({
    required this.containerId,
    this.connectionId = '',
    required this.connectionName,
    required this.name,
    required this.path,
    required this.openTasks,
    required this.carriedTasks,
    required this.selected,
  });

  /// Parses a candidate JSON object.
  factory WeeklyCandidate.fromJson(Map<String, dynamic> j) => WeeklyCandidate(
        containerId: '${j['container_id']}',
        connectionId: '${j['connection_id'] ?? ''}',
        connectionName: '${j['connection_name'] ?? ''}',
        name: '${j['name'] ?? ''}',
        path: '${j['path'] ?? j['name'] ?? ''}',
        openTasks: (j['open_tasks'] as num? ?? 0).toInt(),
        carriedTasks: (j['carried_tasks'] as num? ?? 0).toInt(),
        selected: j['selected'] == true,
      );

  /// Id of the project in tefteri.
  final String containerId;

  /// Id of the connection that holds the project.
  final String connectionId;

  /// Name of the task app connection.
  final String connectionName;

  /// Project name.
  final String name;

  /// Name with its parents, such as `Website › Launch`.
  final String path;

  /// Open tasks in the project.
  final int openTasks;

  /// Open tasks the last look-back said to carry over.
  final int carriedTasks;

  /// Already chosen for the week.
  final bool selected;
}

/// One reviewed week.
@immutable
class WeeklyHistoryEntry {
  /// Creates an entry.
  const WeeklyHistoryEntry({
    required this.planId,
    required this.weekStart,
    required this.committedProjects,
    required this.doneProjects,
    required this.committedTasks,
    required this.doneTasks,
    required this.reflection,
    required this.projects,
  });

  /// Parses an entry JSON object.
  factory WeeklyHistoryEntry.fromJson(Map<String, dynamic> j) =>
      WeeklyHistoryEntry(
        planId: '${j['plan_id']}',
        weekStart: DateTime.parse('${j['week_start']}'),
        committedProjects: (j['committed_projects'] as num? ?? 0).toInt(),
        doneProjects: (j['done_projects'] as num? ?? 0).toInt(),
        committedTasks: (j['committed_tasks'] as num? ?? 0).toInt(),
        doneTasks: (j['done_tasks'] as num? ?? 0).toInt(),
        reflection: '${j['reflection'] ?? ''}',
        projects: [
          for (final p in (j['projects'] as List? ?? const []))
            (
              name: '${(p as Map<String, dynamic>)['name']}',
              done: p['done'] == true,
            ),
        ],
      );

  /// Plan id.
  final String planId;

  /// Monday of the week.
  final DateTime weekStart;

  /// Projects the user chose.
  final int committedProjects;

  /// Projects that were done.
  final int doneProjects;

  /// Tasks that were planned.
  final int committedTasks;

  /// Planned tasks that were done.
  final int doneTasks;

  /// What the user wrote when looking back.
  final String reflection;

  /// The projects and whether each was done.
  final List<({String name, bool done})> projects;
}

/// The reviewed weeks and their totals.
@immutable
class WeeklyHistory {
  /// Creates a history.
  const WeeklyHistory({
    required this.entries,
    required this.weeks,
    required this.committedProjects,
    required this.doneProjects,
    required this.committedTasks,
    required this.doneTasks,
  });

  /// Parses the history JSON object.
  factory WeeklyHistory.fromJson(Map<String, dynamic> j) {
    final t = j['totals'] as Map<String, dynamic>? ?? const {};
    int n(String k) => (t[k] as num? ?? 0).toInt();
    return WeeklyHistory(
      entries: [
        for (final e in (j['entries'] as List? ?? const []))
          WeeklyHistoryEntry.fromJson(e as Map<String, dynamic>),
      ],
      weeks: n('weeks'),
      committedProjects: n('committed_projects'),
      doneProjects: n('done_projects'),
      committedTasks: n('committed_tasks'),
      doneTasks: n('done_tasks'),
    );
  }

  /// Reviewed weeks, newest first.
  final List<WeeklyHistoryEntry> entries;

  /// Number of reviewed weeks.
  final int weeks;

  /// Projects committed to, over all weeks.
  final int committedProjects;

  /// Projects done, over all weeks.
  final int doneProjects;

  /// Tasks planned, over all weeks.
  final int committedTasks;

  /// Planned tasks done, over all weeks.
  final int doneTasks;

  /// Share of committed projects that were done (0 to 1), or null with none.
  double? get projectRate =>
      committedProjects == 0 ? null : doneProjects / committedProjects;
}

/// What the user decided about one project while looking back.
@immutable
class LookBackAnswer {
  /// Creates an answer.
  const LookBackAnswer({
    required this.projectId,
    this.finishedAnyway = false,
    this.leftover = 'carry',
    this.archive = false,
  });

  /// Id of the project in its plan.
  final String projectId;

  /// Count the project as done although tasks are open.
  final bool finishedAnyway;

  /// `carry` or `backlog`.
  final String leftover;

  /// Archive the project in the task app when the look-back is saved.
  final bool archive;

  /// The JSON body of the review request.
  Map<String, Object?> toJson() => {
        'plan_project_id': projectId,
        'finished_anyway': finishedAnyway,
        'leftover': leftover,
        'archive': archive,
      };
}
