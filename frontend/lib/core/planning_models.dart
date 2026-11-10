/// Data models for tasks, entries, notes, calendar items and conflicts.
library;

import 'package:flutter/foundation.dart';

DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse('$v');

/// Formats [d] as `YYYY-MM-DD` (the API date format).
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Formats [d] as local `HH:MM`.
String hhmm(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:'
      '${l.minute.toString().padLeft(2, '0')}';
}

/// A task from a connected task app.
@immutable
class PlanTask {
  /// Creates a task.
  const PlanTask({
    required this.id,
    required this.connectionId,
    required this.title,
    required this.status,
    required this.syncState,
    this.description,
    this.dueAt,
    this.scheduledStart,
    this.scheduledEnd,
    this.goalId,
    this.project,
    this.projectColor,
    this.labels = const [],
    this.url,
  });

  /// Parses a task JSON object.
  factory PlanTask.fromJson(Map<String, dynamic> j) => PlanTask(
        id: '${j['id']}',
        connectionId: '${j['connection_id']}',
        title: '${j['title'] ?? ''}',
        description: j['description'] as String?,
        status: '${j['status'] ?? 'open'}',
        dueAt: _dt(j['due_at']),
        scheduledStart: _dt(j['scheduled_start']),
        scheduledEnd: _dt(j['scheduled_end']),
        syncState: '${j['sync_state'] ?? 'synced'}',
        goalId: j['goal_id'] == null ? null : '${j['goal_id']}',
        project: j['project'] as String?,
        projectColor: j['project_color'] as String?,
        labels: [for (final l in (j['labels'] as List? ?? const [])) '$l'],
        url: j['url'] as String?,
      );

  /// Task id.
  final String id;

  /// Owning connection id.
  final String connectionId;

  /// Task title.
  final String title;

  /// Optional description.
  final String? description;

  /// `open` or `done`.
  final String status;

  /// Due time, if any.
  final DateTime? dueAt;

  /// Planned start, if scheduled.
  final DateTime? scheduledStart;

  /// Planned end, if scheduled.
  final DateTime? scheduledEnd;

  /// `synced`, `conflict` or `deleted_remotely`.
  final String syncState;

  /// Id of the goal this task serves, if any.
  final String? goalId;

  /// Name of the project (in the task app) that holds the task.
  final String? project;

  /// The color of the project in the task app, as `#rrggbb`, or null.
  final String? projectColor;

  /// Names of the labels the task has in the task app.
  final List<String> labels;

  /// Page of the task in the task app, when it has one.
  final String? url;

  /// True when the task is complete.
  bool get done => status == 'done';

  /// True when the task has a due date. The due date is the planned time.
  bool get isScheduled => dueAt != null;
}

/// A calendar entry (event).
@immutable
class PlanEntry {
  /// Creates an entry.
  const PlanEntry({
    required this.id,
    required this.connectionId,
    required this.title,
    required this.allDay,
    required this.syncState,
    this.start,
    this.end,
    this.location,
    this.color,
    this.readOnly = false,
  });

  /// Parses an entry JSON object.
  factory PlanEntry.fromJson(Map<String, dynamic> j) => PlanEntry(
        id: '${j['id']}',
        connectionId: '${j['connection_id']}',
        title: '${j['title'] ?? ''}',
        start: _dt(j['start']),
        end: _dt(j['end']),
        allDay: j['all_day'] == true,
        location: j['location'] as String?,
        color: j['color'] as String?,
        readOnly: j['read_only'] == true,
        syncState: '${j['sync_state'] ?? 'synced'}',
      );

  /// Entry id.
  final String id;

  /// The color of its calendar in the calendar app, as `#rrggbb`, or null.
  final String? color;

  /// Its calendar is read-only: the user cannot move or change it.
  final bool readOnly;

  /// Owning connection id.
  final String connectionId;

  /// Entry title.
  final String title;

  /// Start time.
  final DateTime? start;

  /// End time.
  final DateTime? end;

  /// True for all-day entries.
  final bool allDay;

  /// Place, if any.
  final String? location;

  /// `synced`, `conflict` or `deleted_remotely`.
  final String syncState;
}

/// A note (the daily view uses the daily note).
@immutable
class PlanNote {
  /// Creates a note.
  const PlanNote({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    this.noteDate,
  });

  /// Parses a note JSON object.
  factory PlanNote.fromJson(Map<String, dynamic> j) => PlanNote(
        id: '${j['id']}',
        kind: '${j['kind'] ?? 'daily'}',
        title: '${j['title'] ?? ''}',
        body: '${j['body'] ?? ''}',
        noteDate: j['note_date'] as String?,
      );

  /// Note id.
  final String id;

  /// `daily`, `retrospective` or `custom` (any other note).
  final String kind;

  /// Note title.
  final String title;

  /// Note text.
  final String body;

  /// Date for daily notes (`YYYY-MM-DD`).
  final String? noteDate;
}

/// Response of `GET /views/day/{date}`.
@immutable
class DayView {
  /// Creates a day view.
  const DayView({
    required this.date,
    required this.entries,
    required this.tasks,
    this.note,
  });

  /// Parses the day view JSON.
  factory DayView.fromJson(Map<String, dynamic> j) => DayView(
        date: '${j['date']}',
        entries: [
          for (final e in (j['entries'] as List? ?? const []))
            PlanEntry.fromJson(e as Map<String, dynamic>),
        ],
        tasks: [
          for (final t in (j['tasks'] as List? ?? const []))
            PlanTask.fromJson(t as Map<String, dynamic>),
        ],
        note: j['note'] == null
            ? null
            : PlanNote.fromJson(j['note'] as Map<String, dynamic>),
      );

  /// The day, `YYYY-MM-DD`.
  final String date;

  /// Entries on that day.
  final List<PlanEntry> entries;

  /// Tasks due or scheduled on that day.
  final List<PlanTask> tasks;

  /// Daily note, if one exists.
  final PlanNote? note;
}

/// One item of `GET /calendar`: an entry or a scheduled task.
@immutable
class CalendarItem {
  /// Creates a calendar item.
  const CalendarItem({
    required this.type,
    required this.id,
    required this.title,
    required this.allDay,
    this.start,
    this.end,
    this.connectionId,
    this.status,
    this.clippedStart = false,
    this.project,
    this.color,
    this.readOnly = false,
  });

  /// Parses one calendar item JSON object.
  factory CalendarItem.fromJson(Map<String, dynamic> j) => CalendarItem(
        type: '${j['type']}',
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        start: _dt(j['start']),
        end: _dt(j['end']),
        allDay: j['all_day'] == true,
        connectionId: j['connection_id'] as String?,
        status: j['status'] as String?,
        clippedStart: j['clipped_start'] == true,
        project: j['project'] as String?,
        color: j['color'] as String?,
        readOnly: j['read_only'] == true,
      );

  /// The calendar of an event is read-only: the user cannot move it.
  final bool readOnly;

  /// A timed event of a calendar that the user can change: it can be dragged.
  bool get movable => !isTask && !allDay && !readOnly && start != null;

  /// The color of the calendar of an entry, as `#rrggbb`, or null.
  final String? color;

  /// `entry` or `task`.
  final String type;

  /// Item id.
  final String id;

  /// Title.
  final String title;

  /// Start time.
  final DateTime? start;

  /// End time.
  final DateTime? end;

  /// True for all-day items.
  final bool allDay;

  /// Owning connection id.
  final String? connectionId;

  /// Task status (`open` or `done`); null for events.
  final String? status;

  /// True when a task block would start on the previous day and is cut at
  /// 00:00 ("continues from previous day").
  final bool clippedStart;

  /// For a task: the name of its project in the task app.
  final String? project;

  /// True when this item is a scheduled task.
  bool get isTask => type == 'task';

  /// True for a task that is done.
  bool get isDone => isTask && status == 'done';
}

/// A sync conflict with both versions of the item.
@immutable
class SyncConflict {
  /// Creates a conflict.
  const SyncConflict({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.local,
    required this.remote,
    this.createdAt,
  });

  /// Parses one item of `GET /conflicts`.
  factory SyncConflict.fromJson(Map<String, dynamic> j) => SyncConflict(
        id: '${j['id']}',
        entityType: '${j['entity_type']}',
        entityId: '${j['entity_id']}',
        local: Map<String, dynamic>.from(
            (j['local_snapshot'] as Map?) ?? const {}),
        remote: Map<String, dynamic>.from(
            (j['remote_snapshot'] as Map?) ?? const {}),
        createdAt: _dt(j['created_at']),
      );

  /// Conflict id.
  final String id;

  /// `task`, `entry` or `note`.
  final String entityType;

  /// Id of the conflicting item.
  final String entityId;

  /// The version stored here.
  final Map<String, dynamic> local;

  /// The version in the other app.
  final Map<String, dynamic> remote;

  /// When the conflict was found.
  final DateTime? createdAt;

  /// Best title for the item.
  String get title => '${local['title'] ?? remote['title'] ?? entityId}';
}

/// A goal for a year, a month or a week.
@immutable
class PlanGoal {
  /// Creates a goal.
  const PlanGoal({
    required this.id,
    required this.periodType,
    required this.periodStart,
    required this.title,
    required this.status,
    required this.progress,
    this.parentId,
    this.description,
    this.criteria,
  });

  /// Parses a goal JSON object.
  factory PlanGoal.fromJson(Map<String, dynamic> j) => PlanGoal(
        id: '${j['id']}',
        parentId: j['parent_id'] == null ? null : '${j['parent_id']}',
        periodType: '${j['period_type'] ?? 'week'}',
        periodStart: '${j['period_start']}',
        title: '${j['title'] ?? ''}',
        description: j['description'] as String?,
        criteria: j['criteria'] as String?,
        status: '${j['status'] ?? 'active'}',
        progress: ((j['progress'] as num?) ?? 0).toDouble().clamp(0.0, 1.0),
      );

  /// Goal id.
  final String id;

  /// Parent goal id (null for a top-level goal).
  final String? parentId;

  /// `year`, `month` or `week`.
  final String periodType;

  /// First day of the period, `YYYY-MM-DD`.
  final String periodStart;

  /// Goal title.
  final String title;

  /// Optional description.
  final String? description;

  /// What has to be true for the goal to count as complete.
  final String? criteria;

  /// `active`, `done` or `dropped`.
  final String status;

  /// Progress from 0 to 1, computed by the server.
  final double progress;
}

/// Response of `GET /views/week|month|year`.
@immutable
class PeriodView {
  /// Creates a period view.
  const PeriodView({
    required this.periodType,
    required this.start,
    required this.end,
    required this.goals,
    required this.tasks,
    required this.entries,
  });

  /// Parses the period view JSON.
  factory PeriodView.fromJson(Map<String, dynamic> j) => PeriodView(
        periodType: '${j['period_type']}',
        start: '${j['start']}',
        end: '${j['end']}',
        goals: [
          for (final g in (j['goals'] as List? ?? const []))
            PlanGoal.fromJson(g as Map<String, dynamic>),
        ],
        tasks: [
          for (final t in (j['tasks'] as List? ?? const []))
            PlanTask.fromJson(t as Map<String, dynamic>),
        ],
        entries: [
          for (final e in (j['entries'] as List? ?? const []))
            PlanEntry.fromJson(e as Map<String, dynamic>),
        ],
      );

  /// `week`, `month` or `year`.
  final String periodType;

  /// First day, `YYYY-MM-DD`.
  final String start;

  /// Day after the last day, `YYYY-MM-DD`.
  final String end;

  /// Goals of the period.
  final List<PlanGoal> goals;

  /// Tasks due or scheduled in the period.
  final List<PlanTask> tasks;

  /// Entries in the period (empty for a year).
  final List<PlanEntry> entries;
}

/// A child goal to create in a breakdown.
@immutable
class GoalDraft {
  /// Creates a draft.
  const GoalDraft(
      {required this.title,
      required this.periodType,
      required this.periodStart});

  /// Goal title.
  final String title;

  /// `year`, `month` or `week`.
  final String periodType;

  /// First day of the period, `YYYY-MM-DD`.
  final String periodStart;

  /// JSON for the breakdown request.
  Map<String, Object?> toJson() => {
        'title': title,
        'period_type': periodType,
        'period_start': periodStart,
      };
}

/// A task to create in a breakdown.
@immutable
class TaskDraft {
  /// Creates a draft.
  const TaskDraft({required this.connectionId, required this.title});

  /// Connection that owns the new task.
  final String connectionId;

  /// Task title.
  final String title;

  /// JSON for the breakdown request.
  Map<String, Object?> toJson() =>
      {'connection_id': connectionId, 'title': title};
}

/// Planning settings of the signed-in user (`/me/settings`).
@immutable
class UserSettings {
  /// Creates settings.
  const UserSettings({
    required this.randomTimeOnDateDrop,
    this.defaultReminderMinutes = defaultReminderOffset,
    this.checklists = const {},
  });

  /// Parses the settings JSON object.
  factory UserSettings.fromJson(Map<String, dynamic> j) => UserSettings(
        randomTimeOnDateDrop: j['random_time_on_date_drop'] == true,
        defaultReminderMinutes:
            (j['default_reminder_minutes'] as num?)?.toInt() ??
                defaultReminderOffset,
        checklists: {
          for (final kind in ChecklistKind.values)
            kind: [
              for (final i in ((j['checklists'] as Map?)?[kind.name] as List? ??
                  const []))
                '$i',
            ],
        },
      );

  /// When true, a date-only drop gets a random time of day on that date.
  final bool randomTimeOnDateDrop;

  /// Minutes before its due time that a new task reminder fires.
  final int defaultReminderMinutes;

  /// The planning checklists: the items to go through at each kind of
  /// planning. A kind without items has no checklist.
  final Map<ChecklistKind, List<String>> checklists;

  /// The items of the checklist of [kind].
  List<String> itemsOf(ChecklistKind kind) => checklists[kind] ?? const [];
}

/// The kind of planning that a checklist belongs to.
enum ChecklistKind {
  /// Goes with the weekly planning.
  week('Weekly', 'week'),

  /// Goes with the month.
  month('Monthly', 'month'),

  /// Goes with the year.
  year('Annual', 'year');

  const ChecklistKind(this.adjective, this.noun);

  /// `Weekly`, `Monthly` or `Annual`.
  final String adjective;

  /// `week`, `month` or `year`.
  final String noun;
}

/// One item of a checklist, ticked or not in a period.
@immutable
class ChecklistItem {
  /// Creates an item.
  const ChecklistItem(this.text, {this.checked = false});

  /// The words of the item.
  final String text;

  /// True when the item is ticked in the period.
  final bool checked;
}

/// The checklist of one week, month or year (`/checklists/{kind}/{day}`).
@immutable
class PeriodChecklist {
  /// Creates a checklist.
  const PeriodChecklist(this.items);

  /// Parses the checklist JSON object.
  factory PeriodChecklist.fromJson(Map<String, dynamic> j) => PeriodChecklist([
        for (final i in (j['items'] as List? ?? const []))
          ChecklistItem('${(i as Map)['text']}', checked: i['checked'] == true),
      ]);

  /// The items of the user's list. Empty when they have not made one.
  final List<ChecklistItem> items;

  /// How many items are ticked.
  int get done => items.where((i) => i.checked).length;

  /// The same checklist with [text] ticked or unticked.
  PeriodChecklist withTick(String text, bool checked) => PeriodChecklist([
        for (final i in items)
          i.text == text ? ChecklistItem(i.text, checked: checked) : i,
      ]);
}

/// What a new reminder uses until the user changes it: 15 minutes.
const int defaultReminderOffset = 15;

/// The reminder of one task in its task app (`/tasks/{id}/reminder`).
@immutable
class TaskReminder {
  /// Creates a reminder.
  const TaskReminder({required this.supported, this.minutesBefore});

  /// Parses the reminder JSON object.
  factory TaskReminder.fromJson(Map<String, dynamic> j) => TaskReminder(
        supported: j['supported'] == true,
        minutesBefore: (j['minutes_before'] as num?)?.toInt(),
      );

  /// False when the task app has no reminders: the button is hidden.
  final bool supported;

  /// Minutes before the due time that it fires, or null when there is none.
  final int? minutesBefore;
}
