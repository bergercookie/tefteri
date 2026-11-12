/// Models of the weekly planning workflow, as the backend sends them.
library;

import 'package:flutter/foundation.dart';

DateTime? _day(Object? v) => v == null ? null : DateTime.tryParse('$v');

int _int(Object? v) => (v as num? ?? 0).toInt();

String? _text(Object? v) {
  final t = v == null ? '' : '$v'.trim();
  return t.isEmpty ? null : t;
}

/// A theme as a milestone card shows it: an id and a name.
@immutable
class ThemeRef {
  /// Creates a theme reference.
  const ThemeRef({required this.id, required this.name});

  /// Parses `{"id", "name"}`, or null for no theme.
  static ThemeRef? fromJson(Object? j) =>
      j is Map ? ThemeRef(id: '${j['id']}', name: '${j['name'] ?? ''}') : null;

  /// Project id of the theme.
  final String id;

  /// Theme name.
  final String name;
}

/// A task of a chosen project.
@immutable
class WeeklyTask {
  /// Creates a task.
  const WeeklyTask({
    required this.id,
    required this.title,
    this.dueDay,
    this.plannedDay,
    this.completedDay,
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
        completedDay: _day(j['completed_day']),
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

  /// The day the task was completed, or null while open or when the task app
  /// does not say.
  final DateTime? completedDay;

  /// Page of the task in the task app.
  final String? url;
}

/// A milestone project chosen for the week.
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
    this.milestoneId,
    this.doneState,
    this.milestoneState,
    this.theme,
    this.outsideFocus = false,
    this.rolloverCount = 0,
    this.needsRescope = false,
    this.orphaned = false,
    this.notice,
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
        milestoneId: j['milestone_id'] == null ? null : '${j['milestone_id']}',
        doneState: _text(j['done_state']),
        milestoneState: j['milestone_state'] as String?,
        theme: ThemeRef.fromJson(j['theme']),
        outsideFocus: j['outside_focus'] == true,
        rolloverCount: _int(j['rollover_count']),
        needsRescope: j['needs_rescope'] == true,
        orphaned: j['orphaned'] == true,
        notice: j['notice'] as String?,
      );

  /// Id of the milestone, or null for an entry from before milestones.
  final String? milestoneId;

  /// One sentence that says when the milestone is finished.
  final String? doneState;

  /// `active`, `parked`, `closed` or `done`, or null for an old entry.
  final String? milestoneState;

  /// The theme it belongs to, or null for "no theme".
  final ThemeRef? theme;

  /// The theme is not in the month's focus. Computed by the server.
  final bool outsideFocus;

  /// How often the milestone was recommitted.
  final int rolloverCount;

  /// Two unmarked rollovers in a row: the milestone is too big.
  final bool needsRescope;

  /// The project is gone from the task app. The stored name stays.
  final bool orphaned;

  /// `relabelled` when the project got another label after the commit.
  final String? notice;

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
    required this.projects,
    this.committedAt,
    this.milestoneCap = 3,
    this.focusKnown = false,
    this.month,
  });

  /// Parses a plan JSON object.
  factory WeeklyPlan.fromJson(Map<String, dynamic> j) => WeeklyPlan(
        id: '${j['id']}',
        status: '${j['status']}',
        committedAt: _day(j['committed_at']),
        retroSkipped: j['retro_skipped'] == true,
        milestoneCap: _int(j['milestone_cap'] ?? 3),
        focusKnown: j['focus_known'] == true,
        month: _day(j['month']),
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

  /// How many milestones a week usually holds. A warning, never a limit.
  final int milestoneCap;

  /// The monthly focus is known, so "outside focus" can be shown.
  final bool focusKnown;

  /// The month of the Monday of the week.
  final DateTime? month;

  /// The chosen milestones.
  final List<WeeklyProject> projects;

  /// How many milestones the week holds.
  int get milestoneCount => projects.length;

  /// More milestones than the cap.
  bool get overCap => milestoneCount > milestoneCap;

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

/// What the user decides about an unfinished milestone in the review.
///
/// Weeks that were reviewed before milestones used the words `carry` and
/// `backlog`; [parse] reads them as [recommit] and [park].
enum Decision {
  /// Put the milestone into next week's plan.
  recommit('recommit', 'Keep and recommit',
      'Put it in next week\'s plan. Its rollover count goes up by one.',
      legacyName: 'carry'),

  /// Set the milestone aside; it returns to the picker, marked parked.
  park('park', 'Keep but park',
      'Set it aside. It comes back in the picker, marked as parked.',
      legacyName: 'backlog'),

  /// Close the milestone and move its open tasks to its theme.
  close('close', 'Close and return tasks',
      'Stop here. Its open tasks move to the theme. You can undo it.'),

  /// Change nothing now.
  decideLater('decide_later', 'Decide later',
      'Change nothing now. The picker reminds you next time.');

  const Decision(this.api, this.label, this.sentence, {this.legacyName});

  /// The value in the API.
  final String api;

  /// The words on the choice.
  final String label;

  /// One plain sentence about what the choice does.
  final String sentence;

  /// The name that weeks before milestones used, if there was one.
  final String? legacyName;

  /// The decision named [v], in its new or its legacy name; null otherwise.
  static Decision? parse(Object? v) {
    for (final d in values) {
      if (v == d.api || (d.legacyName != null && v == d.legacyName)) return d;
    }
    return null;
  }
}

/// Whether the close choice is open for a milestone, and why not.
@immutable
class CloseInfo {
  /// Creates the info.
  const CloseInfo({
    this.available = false,
    this.reason,
    this.openTasks = 0,
    this.themeName,
  });

  /// Parses `close`; a missing object means "not available".
  factory CloseInfo.fromJson(Object? j) {
    if (j is! Map) return const CloseInfo();
    return CloseInfo(
      available: j['available'] == true,
      reason: j['reason'] as String?,
      openTasks: _int(j['open_tasks']),
      themeName: j['theme_name'] as String?,
    );
  }

  /// The milestone can be closed.
  final bool available;

  /// `no_theme`, `theme_unusable` or `not_supported` when it cannot.
  final String? reason;

  /// Open tasks that would move.
  final int openTasks;

  /// Name of the theme they would move to.
  final String? themeName;

  /// Why the close choice is hidden, in plain words.
  String get reasonLine => switch (reason) {
        'no_theme' => 'Close is not offered: there is no theme to return the '
            'tasks to.',
        'theme_unusable' => 'Close is not offered: the theme is ignored or '
            'gone from your task app, so the tasks have nowhere to go.',
        'not_supported' => 'Close is not offered: your task app cannot move '
            'tasks between projects.',
        _ => 'Close is not offered for this milestone.',
      };
}

/// How a milestone of the earlier week went.
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
    this.color,
    this.milestoneId,
    this.doneState,
    this.theme,
    this.milestoneState,
    this.decision,
    this.expectedRollover = false,
    this.legacy = false,
    this.rolloverCount = 0,
    this.needsRescope = false,
    this.outsideFocus = false,
    this.close = const CloseInfo(),
  });

  /// Parses a project JSON object.
  factory LookBackProject.fromJson(Map<String, dynamic> j) => LookBackProject(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        color: j['color'] as String?,
        committed: _int(j['committed']),
        done: _int(j['done']),
        completed: j['completed'] == true,
        outcome: j['outcome'] as String?,
        milestoneId: j['milestone_id'] == null ? null : '${j['milestone_id']}',
        doneState: _text(j['done_state']),
        theme: ThemeRef.fromJson(j['theme']),
        milestoneState: j['milestone_state'] as String?,
        decision: Decision.parse(j['decision']),
        expectedRollover: j['expected_rollover'] == true,
        legacy: j['legacy'] == true,
        rolloverCount: _int(j['rollover_count']),
        needsRescope: j['needs_rescope'] == true,
        outsideFocus: j['outside_focus'] == true,
        close: CloseInfo.fromJson(j['close']),
        leftover: [
          for (final t in (j['leftover'] as List? ?? const []))
            WeeklyTask.fromJson(t as Map<String, dynamic>),
        ],
      );

  /// Id of the project in its plan.
  final String id;

  /// Id of the milestone, or null for an entry from before milestones.
  final String? milestoneId;

  /// Milestone name.
  final String name;

  /// One sentence that says when the milestone is finished.
  final String? doneState;

  /// Its theme, or null for "no theme".
  final ThemeRef? theme;

  /// `active`, `parked`, `closed` or `done`, or null for an old entry.
  final String? milestoneState;

  /// The color of the project in the task app, as `#rrggbb`, or null.
  final String? color;

  /// Tasks that were planned for the week.
  final int committed;

  /// Planned tasks that are done.
  final int done;

  /// All planned tasks are done, or the milestone is done.
  final bool completed;

  /// `done` or `not_done` once reviewed.
  final String? outcome;

  /// The decision of a review that was saved, in the new names.
  final Decision? decision;

  /// The rollover of this decision was marked as expected.
  final bool expectedRollover;

  /// The row is from before milestones.
  final bool legacy;

  /// How often the milestone was recommitted.
  final int rolloverCount;

  /// Two unmarked rollovers in a row.
  final bool needsRescope;

  /// Its theme is not in the month's focus.
  final bool outsideFocus;

  /// Whether the close choice is open.
  final CloseInfo close;

  /// Planned tasks that are still open.
  final List<WeeklyTask> leftover;

  /// The milestone was closed already (and its tasks moved).
  bool get closed => milestoneState == 'closed';
}

/// One day of the pace line.
@immutable
class PaceDay {
  /// Creates a day.
  const PaceDay(this.day, this.done);

  /// The day.
  final DateTime day;

  /// Committed tasks that were done on that day.
  final int done;
}

/// The numbers at the top of the review.
@immutable
class ReviewSummary {
  /// Creates a summary.
  const ReviewSummary({
    this.committedTasks = 0,
    this.doneTasks = 0,
    this.milestonesCommitted = 0,
    this.milestonesDone = 0,
    this.pace = const [],
    this.focusShare,
    this.note,
  });

  /// Parses `summary`; a missing object gives an empty summary.
  factory ReviewSummary.fromJson(Object? j) {
    if (j is! Map) return const ReviewSummary();
    return ReviewSummary(
      committedTasks: _int(j['committed_tasks']),
      doneTasks: _int(j['done_tasks']),
      milestonesCommitted: _int(j['milestones_committed']),
      milestonesDone: _int(j['milestones_done']),
      pace: [
        for (final p in (j['pace'] as List? ?? const []))
          PaceDay(DateTime.parse('${(p as Map)['day']}'), _int(p['done'])),
      ],
      focusShare: (j['focus_share'] as num?)?.toDouble(),
      note: _text(j['note']),
    );
  }

  /// Tasks that were planned.
  final int committedTasks;

  /// Planned tasks that are done.
  final int doneTasks;

  /// Milestones that were committed.
  final int milestonesCommitted;

  /// Committed milestones that are finished.
  final int milestonesDone;

  /// Planned tasks done per day.
  final List<PaceDay> pace;

  /// Share (0 to 1) of completed tasks under focus themes, or null when there
  /// is no focus data or nothing was completed.
  final double? focusShare;

  /// A short text for a week in which nothing was committed.
  final String? note;

  /// Nothing was committed, so there is no ratio to show.
  bool get empty => committedTasks == 0;
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
    this.summary = const ReviewSummary(),
  });

  /// Parses a look-back JSON object.
  factory LookBack.fromJson(Map<String, dynamic> j) => LookBack(
        planId: '${j['plan_id']}',
        weekStart: DateTime.parse('${j['week_start']}'),
        reviewed: j['reviewed'] == true,
        reflection: '${j['reflection'] ?? ''}',
        summary: ReviewSummary.fromJson(j['summary']),
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

  /// The numbers of the week.
  final ReviewSummary summary;

  /// Its milestones.
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

/// A project the user can pick for the week: a milestone, or an unsorted
/// project that picking labels as a milestone.
@immutable
class MilestoneCandidate {
  /// Creates a candidate.
  const MilestoneCandidate({
    required this.containerId,
    this.connectionId = '',
    required this.connectionName,
    required this.name,
    required this.path,
    required this.openTasks,
    required this.carriedTasks,
    required this.selected,
    this.kind = 'milestone',
    this.milestoneId,
    this.doneState,
    this.state = 'active',
    this.theme,
    this.inFocus,
    this.rolloverCount = 0,
    this.needsRescope = false,
    this.decisionOpen = false,
  });

  /// Parses a candidate JSON object.
  factory MilestoneCandidate.fromJson(Map<String, dynamic> j) =>
      MilestoneCandidate(
        containerId: '${j['container_id']}',
        connectionId: '${j['connection_id'] ?? ''}',
        connectionName: '${j['connection_name'] ?? ''}',
        name: '${j['name'] ?? ''}',
        path: '${j['path'] ?? j['name'] ?? ''}',
        openTasks: _int(j['open_tasks']),
        carriedTasks: _int(j['carried_tasks']),
        selected: j['selected'] == true,
        kind:
            j['unsorted'] == true ? 'unsorted' : '${j['kind'] ?? 'milestone'}',
        milestoneId: j['milestone_id'] == null ? null : '${j['milestone_id']}',
        doneState: _text(j['done_state']),
        state: '${j['state'] ?? 'active'}',
        theme: ThemeRef.fromJson(j['theme']),
        inFocus: j['in_focus'] as bool?,
        rolloverCount: _int(j['rollover_count']),
        needsRescope: j['needs_rescope'] == true,
        decisionOpen: j['decision_open'] == true,
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

  /// `milestone` or `unsorted`.
  final String kind;

  /// Id of the milestone, or null for an unsorted project.
  final String? milestoneId;

  /// One sentence that says when the milestone is finished.
  final String? doneState;

  /// `active` or `parked`.
  final String state;

  /// The theme above it, or null for "no theme".
  final ThemeRef? theme;

  /// Its theme is in the month's focus; null when there is no focus data.
  final bool? inFocus;

  /// How often it was recommitted.
  final int rolloverCount;

  /// Two unmarked rollovers in a row.
  final bool needsRescope;

  /// The last review left it with "decide later".
  final bool decisionOpen;

  /// Open tasks in the project.
  final int openTasks;

  /// Open committed tasks of a milestone that the last review recommitted.
  final int carriedTasks;

  /// Already chosen for the week.
  final bool selected;

  /// The project has no label; picking it labels it milestone.
  bool get unsorted => kind == 'unsorted';

  /// The milestone was parked by a review.
  bool get parked => state == 'parked';
}

/// A theme that the picker shows as a group.
@immutable
class ThemeGroup {
  /// Creates a group.
  const ThemeGroup({
    required this.id,
    required this.containerId,
    this.connectionId = '',
    required this.name,
    this.inFocus,
    this.milestones = 0,
    this.openMilestones = 0,
  });

  /// Parses a theme JSON object.
  factory ThemeGroup.fromJson(Map<String, dynamic> j) => ThemeGroup(
        id: '${j['id']}',
        containerId: '${j['container_id']}',
        connectionId: '${j['connection_id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        inFocus: j['in_focus'] as bool?,
        milestones: _int(j['milestones']),
        openMilestones: _int(j['open_milestones']),
      );

  /// Id of the theme (as `theme.id` of a candidate).
  final String id;

  /// Project id: the parent for a new milestone.
  final String containerId;

  /// Id of the connection that holds it.
  final String connectionId;

  /// Theme name.
  final String name;

  /// In the month's focus; null when there is no focus data.
  final bool? inFocus;

  /// Milestones under it.
  final int milestones;

  /// Milestones under it that are not finished.
  final int openMilestones;
}

/// The answer of `GET /weekly/{week}/themes`.
@immutable
class WeeklyThemes {
  /// Creates the answer.
  const WeeklyThemes(
      {this.focusKnown = false,
      this.themes = const [],
      this.unsortedCount = 0});

  /// Parses the answer.
  factory WeeklyThemes.fromJson(Map<String, dynamic> j) => WeeklyThemes(
        focusKnown: j['focus_known'] == true,
        unsortedCount: _int(j['unsorted_count']),
        themes: [
          for (final t in (j['themes'] as List? ?? const []))
            ThemeGroup.fromJson(t as Map<String, dynamic>),
        ],
      );

  /// A monthly focus exists.
  final bool focusKnown;

  /// The themes the user can plan under.
  final List<ThemeGroup> themes;

  /// Projects that have no label yet.
  final int unsortedCount;
}

/// A milestone of an earlier week, as the history shows it.
@immutable
class HistoryMilestone {
  /// Creates the entry.
  const HistoryMilestone({
    required this.name,
    required this.done,
    this.decision,
    this.milestoneId,
    this.themeName,
    this.doneOn,
    this.rolloverCount = 0,
  });

  /// Parses an entry.
  factory HistoryMilestone.fromJson(Map<String, dynamic> j) => HistoryMilestone(
        name: '${j['name']}',
        done: j['done'] == true,
        decision: Decision.parse(j['decision']),
        milestoneId: j['milestone_id'] == null ? null : '${j['milestone_id']}',
        themeName: j['theme_name'] as String?,
        doneOn: _day(j['done_on']),
        rolloverCount: _int(j['rollover_count']),
      );

  /// Name as stored in that week.
  final String name;

  /// It was done.
  final bool done;

  /// What the review decided, in the new names (old rows are mapped).
  final Decision? decision;

  /// Id of the milestone; null for a project from before milestones.
  final String? milestoneId;

  /// Theme at the time.
  final String? themeName;

  /// The day it was finished.
  final DateTime? doneOn;

  /// Its rollover count.
  final int rolloverCount;

  /// The entry is from a week before milestones.
  bool get legacy => milestoneId == null;
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
        committedProjects: _int(j['committed_projects']),
        doneProjects: _int(j['done_projects']),
        committedTasks: _int(j['committed_tasks']),
        doneTasks: _int(j['done_tasks']),
        reflection: '${j['reflection'] ?? ''}',
        projects: [
          for (final p in (j['projects'] as List? ?? const []))
            HistoryMilestone.fromJson(p as Map<String, dynamic>),
        ],
      );

  /// Plan id.
  final String planId;

  /// Monday of the week.
  final DateTime weekStart;

  /// Milestones the user committed (projects, for an old week).
  final int committedProjects;

  /// Milestones that were done.
  final int doneProjects;

  /// Tasks that were planned.
  final int committedTasks;

  /// Planned tasks that were done.
  final int doneTasks;

  /// What the user wrote when looking back.
  final String reflection;

  /// The milestones and how each went.
  final List<HistoryMilestone> projects;
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
    int n(String k) => _int(t[k]);
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

  /// Milestones committed to, over all weeks.
  final int committedProjects;

  /// Milestones done, over all weeks.
  final int doneProjects;

  /// Tasks planned, over all weeks.
  final int committedTasks;

  /// Planned tasks done, over all weeks.
  final int doneTasks;

  /// Share of committed milestones that were done (0 to 1), or null with none.
  double? get projectRate =>
      committedProjects == 0 ? null : doneProjects / committedProjects;
}

/// A milestone that now needs to be re-scoped.
@immutable
class Nudge {
  /// Creates a nudge.
  const Nudge({required this.milestoneId, required this.name});

  /// Parses a nudge.
  factory Nudge.fromJson(Map<String, dynamic> j) =>
      Nudge(milestoneId: '${j['milestone_id']}', name: '${j['name'] ?? ''}');

  /// Id of the milestone.
  final String milestoneId;

  /// Its name.
  final String name;
}

/// The answer to saving a review: the history, and what the save changed.
@immutable
class ReviewResult {
  /// Creates a result.
  const ReviewResult(
      {required this.history, this.notices = const [], this.nudges = const []});

  /// Parses the answer (the history plus `notices` and `nudges`).
  factory ReviewResult.fromJson(Map<String, dynamic> j) => ReviewResult(
        history: WeeklyHistory.fromJson(j),
        notices: [for (final n in (j['notices'] as List? ?? const [])) '$n'],
        nudges: [
          for (final n in (j['nudges'] as List? ?? const []))
            Nudge.fromJson(n as Map<String, dynamic>),
        ],
      );

  /// The reviewed weeks.
  final WeeklyHistory history;

  /// Plain sentences about what the save changed (for example that next
  /// week's plan went back to draft).
  final List<String> notices;

  /// Milestones that now need to be re-scoped.
  final List<Nudge> nudges;
}

/// What the user decided about one milestone while looking back.
@immutable
class LookBackAnswer {
  /// Creates an answer.
  const LookBackAnswer({
    required this.projectId,
    this.decision,
    this.expected = false,
    this.markDone = false,
    this.archive = false,
  });

  /// Id of the milestone in its plan.
  final String projectId;

  /// What happens to the milestone; null while the user has not chosen. It is
  /// sent as `decide_later`, which changes nothing.
  final Decision? decision;

  /// The rollover is expected (used with a recommit only).
  final bool expected;

  /// Mark the milestone done by hand when the review is saved.
  final bool markDone;

  /// Archive the project in the task app when the review is saved.
  final bool archive;

  /// A copy with [decision] set (null clears it).
  LookBackAnswer withDecision(Decision? decision) => LookBackAnswer(
        projectId: projectId,
        decision: decision,
        expected: expected,
        markDone: markDone,
        archive: archive,
      );

  /// A copy with some fields changed.
  LookBackAnswer copyWith({bool? expected, bool? markDone, bool? archive}) =>
      LookBackAnswer(
        projectId: projectId,
        decision: decision,
        expected: expected ?? this.expected,
        markDone: markDone ?? this.markDone,
        archive: archive ?? this.archive,
      );

  /// The JSON body of the review request.
  Map<String, Object?> toJson() => {
        'plan_project_id': projectId,
        'decision': (decision ?? Decision.decideLater).api,
        'expected': decision == Decision.recommit && expected,
        'mark_done': markDone,
        'archive': archive,
      };
}

/// A task that a close moved, or tried to move.
@immutable
class MovedTask {
  /// Creates a task.
  const MovedTask(this.taskId, this.title, {this.reason});

  /// Parses `{task_id, title, reason?}`.
  factory MovedTask.fromJson(Map<String, dynamic> j) =>
      MovedTask('${j['task_id']}', '${j['title'] ?? ''}',
          reason: j['reason'] as String?);

  /// Task id.
  final String taskId;

  /// Task title.
  final String title;

  /// Why a task could not move back: `changed`, `moved` or `missing`.
  final String? reason;

  /// The reason of a failed move back, in plain words.
  String get reasonLine => switch (reason) {
        'changed' => 'You changed it after the move.',
        'moved' => 'It is in another project now.',
        'missing' => 'It is gone from your task app.',
        _ => 'It could not move back.',
      };
}

/// The effect of a close, before it is confirmed.
@immutable
class ClosePreview {
  /// Creates a preview.
  const ClosePreview(
      {required this.openTasks, required this.themeName, this.message = ''});

  /// Parses the dry-run answer.
  factory ClosePreview.fromJson(Map<String, dynamic> j) => ClosePreview(
        openTasks: _int(j['open_tasks']),
        themeName: ThemeRef.fromJson(j['theme'])?.name ?? '',
        message: '${j['message'] ?? ''}',
      );

  /// Open tasks that will move.
  final int openTasks;

  /// The theme they move to.
  final String themeName;

  /// The sentence from the server.
  final String message;
}

/// The answer of a confirmed close.
@immutable
class CloseResult {
  /// Creates a result.
  const CloseResult({required this.moved, this.closureId});

  /// Parses the answer.
  factory CloseResult.fromJson(Map<String, dynamic> j) => CloseResult(
      moved: _int(j['moved']),
      closureId: j['closure_id'] == null ? null : '${j['closure_id']}');

  /// How many tasks moved.
  final int moved;

  /// Id of the closure, for the undo.
  final String? closureId;
}

/// A close that stopped part way: the milestone stays unclosed.
@immutable
class CloseFailure {
  /// Creates a failure.
  const CloseFailure(
      {required this.message, this.moved = const [], this.remaining = 0});

  /// Reads the failure from an API error body. Missing parts stay empty.
  factory CloseFailure.fromBody(Object? data, String message) {
    final m = data is Map ? data : const {};
    return CloseFailure(
      message: message,
      moved: [
        for (final t in (m['moved'] as List? ?? const []))
          if (t is Map<String, dynamic>) MovedTask.fromJson(t),
      ],
      remaining: _int(m['remaining']),
    );
  }

  /// What went wrong, from the server.
  final String message;

  /// Tasks that were already moved.
  final List<MovedTask> moved;

  /// Tasks that are still to move.
  final int remaining;
}

/// The answer of a reopen.
@immutable
class ReopenResult {
  /// Creates a result.
  const ReopenResult({required this.movedBack, this.notMovedBack = const []});

  /// Parses the answer.
  factory ReopenResult.fromJson(Map<String, dynamic> j) => ReopenResult(
        movedBack: _int(j['moved_back']),
        notMovedBack: [
          for (final t in (j['not_moved_back'] as List? ?? const []))
            MovedTask.fromJson(t as Map<String, dynamic>),
        ],
      );

  /// Tasks that went back where they were.
  final int movedBack;

  /// Tasks that could not go back, with the reason.
  final List<MovedTask> notMovedBack;
}

/// The effect of marking a milestone done by hand.
@immutable
class DonePreview {
  /// Creates a preview.
  const DonePreview({required this.openTasks, required this.message});

  /// Parses the dry-run answer.
  factory DonePreview.fromJson(Map<String, dynamic> j) => DonePreview(
      openTasks: _int(j['open_tasks']), message: '${j['message'] ?? ''}');

  /// Open tasks that stay where they are.
  final int openTasks;

  /// The sentence from the server.
  final String message;
}
