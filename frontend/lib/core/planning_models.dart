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
    this.allDay = false,
    this.scheduledStart,
    this.scheduledEnd,
    this.goalId,
    this.project,
    this.projectColor,
    this.theme,
    this.category,
    this.work = false,
    this.labels = const [],
    this.url,
    this.completedAt,
  });

  /// Parses a task JSON object.
  factory PlanTask.fromJson(Map<String, dynamic> j) => PlanTask(
        id: '${j['id']}',
        connectionId: '${j['connection_id']}',
        title: '${j['title'] ?? ''}',
        description: j['description'] as String?,
        status: '${j['status'] ?? 'open'}',
        dueAt: _dt(j['due_at']),
        allDay: j['all_day'] == true,
        scheduledStart: _dt(j['scheduled_start']),
        scheduledEnd: _dt(j['scheduled_end']),
        syncState: '${j['sync_state'] ?? 'synced'}',
        goalId: j['goal_id'] == null ? null : '${j['goal_id']}',
        project: j['project'] as String?,
        work: j['work'] == true,
        projectColor: j['project_color'] as String?,
        theme: j['theme'] as String?,
        category: j['category'] as String?,
        labels: [for (final l in (j['labels'] as List? ?? const [])) '$l'],
        url: j['url'] as String?,
        completedAt: _dt(j['completed_at']),
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

  /// The task has a due day but no time of day.
  final bool allDay;

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

  /// Name of the theme project above the task's project (or the project
  /// itself), or null when the task is outside every theme.
  final String? theme;

  /// The work category of the task (`goal_aligned`, `maintenance`,
  /// `off_plan` or `hidden`), or null when the server does not know it.
  final String? category;

  /// The task sits under a theme that the user marked as work.
  final bool work;

  /// Names of the labels the task has in the task app.
  final List<String> labels;

  /// Page of the task in the task app, when it has one.
  final String? url;

  /// When the task was done, or null while it is open (or when the task app
  /// did not say).
  final DateTime? completedAt;

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

  /// `daily` or `custom` (any other note).
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
    this.containerId,
    this.status,
    this.clippedStart = false,
    this.project,
    this.work = false,
    this.color,
    this.readOnly = false,
    this.location,
    this.description,
    this.calendar,
    this.uid,
    this.alsoIn = const [],
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
        containerId: j['container_id'] as String?,
        status: j['status'] as String?,
        clippedStart: j['clipped_start'] == true,
        project: j['project'] as String?,
        work: j['work'] == true,
        color: j['color'] as String?,
        readOnly: j['read_only'] == true,
        location: j['location'] as String?,
        description: j['description'] as String?,
        calendar: j['calendar'] as String?,
        uid: j['uid'] as String?,
      );

  /// This event, shown once for itself and its copies in [others]: the same
  /// event in other calendars (see [uid]).
  CalendarItem withCopies(List<CalendarItem> others) => CalendarItem(
        type: type,
        id: id,
        title: title,
        allDay: allDay,
        start: start,
        end: end,
        connectionId: connectionId,
        containerId: containerId,
        status: status,
        clippedStart: clippedStart,
        project: project,
        color: color,
        readOnly: readOnly,
        location: location,
        description: description,
        calendar: calendar,
        uid: uid,
        alsoIn: [
          ...alsoIn,
          for (final o in others)
            EventCopy(
                containerId: o.containerId, name: o.calendar, color: o.color),
        ],
      );

  /// For an event: the place.
  final String? location;

  /// For an event: the description, as the calendar app keeps it.
  final String? description;

  /// For an event: the name of its calendar, when known.
  final String? calendar;

  /// For an event: its iCalendar UID. Copies of one event in several
  /// calendars (the owner of one calendar was invited to an event of another)
  /// have the same UID.
  final String? uid;

  /// The other calendars that hold a copy of this event. Empty for most.
  final List<EventCopy> alsoIn;

  /// True for an event that is shown once for copies in several calendars.
  bool get isShared => alsoIn.isNotEmpty;

  /// Names of every calendar that holds this event, its own first.
  List<String> get calendarNames => [
        if (calendar != null) calendar!,
        for (final c in alsoIn)
          if (c.name != null) c.name!,
      ];

  /// Colors (`#rrggbb` or null) of every calendar that holds this event.
  List<String?> get calendarColors => [color, for (final c in alsoIn) c.color];

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

  /// The calendar of an entry, or the project of a task, when known.
  final String? containerId;

  /// Task status (`open` or `done`); null for events.
  final String? status;

  /// True when a task block would start on the previous day and is cut at
  /// 00:00 ("continues from previous day").
  final bool clippedStart;

  /// For a task: the name of its project in the task app.
  final String? project;

  /// For a task: its project sits under a theme that the user marked as work.
  final bool work;

  /// True when this item is a scheduled task.
  bool get isTask => type == 'task';

  /// True for a task that is done.
  bool get isDone => isTask && status == 'done';
}

/// A copy of an event in another calendar.
@immutable
class EventCopy {
  /// Creates the reference to a copy.
  const EventCopy({this.containerId, this.name, this.color});

  /// The calendar of the copy.
  final String? containerId;

  /// Name of that calendar.
  final String? name;

  /// Color of that calendar, as `#rrggbb`, or null.
  final String? color;
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

/// The title of a goal that a task points to (`goal_titles` of a view).
@immutable
class GoalTitle {
  /// Creates a title.
  const GoalTitle({required this.title, required this.annual});

  /// Parses one `goal_titles` value.
  factory GoalTitle.fromJson(Map<String, dynamic> j) =>
      GoalTitle(title: '${j['title'] ?? ''}', annual: j['annual'] == true);

  /// The goal sentence.
  final String title;

  /// True for a goal of an annual plan; false for an old month or week goal.
  final bool annual;
}

/// Response of `GET /views/week|month|year`.
@immutable
class PeriodView {
  /// Creates a period view.
  const PeriodView({
    required this.periodType,
    required this.start,
    required this.end,
    required this.tasks,
    required this.entries,
    this.goalTitles = const {},
  });

  /// Parses the period view JSON.
  factory PeriodView.fromJson(Map<String, dynamic> j) => PeriodView(
        periodType: '${j['period_type']}',
        start: '${j['start']}',
        end: '${j['end']}',
        goalTitles: {
          for (final e in ((j['goal_titles'] as Map?) ?? const {}).entries)
            '${e.key}': GoalTitle.fromJson(e.value as Map<String, dynamic>),
        },
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

  /// The goals that tasks of the view point to, by goal id. A goal that is
  /// not [GoalTitle.annual] is shown as history.
  final Map<String, GoalTitle> goalTitles;

  /// Tasks due or scheduled in the period.
  final List<PlanTask> tasks;

  /// Entries in the period (empty for a year).
  final List<PlanEntry> entries;
}

/// Planning settings of the signed-in user (`/me/settings`).
@immutable
class UserSettings {
  /// Creates settings.
  const UserSettings({
    required this.randomTimeOnDateDrop,
    this.defaultReminderMinutes = defaultReminderOffset,
    this.eventReminderMinutes = defaultReminderOffset,
    this.checklists = const {},
    this.checklistSources = const {},
    this.defaultEventContainerId,
    this.eventInvitees = const [],
    this.seenHints = const [],
  });

  /// Parses the settings JSON object.
  factory UserSettings.fromJson(Map<String, dynamic> j) => UserSettings(
        randomTimeOnDateDrop: j['random_time_on_date_drop'] == true,
        defaultReminderMinutes:
            (j['default_reminder_minutes'] as num?)?.toInt() ??
                defaultReminderOffset,
        eventReminderMinutes: (j['event_reminder_minutes'] as num?)?.toInt() ??
            defaultReminderOffset,
        checklists: {
          for (final kind in ChecklistKind.values)
            kind: [
              for (final i in ((j['checklists'] as Map?)?[kind.name] as List? ??
                  const []))
                '$i',
            ],
        },
        checklistSources: {
          for (final kind in ChecklistKind.values)
            kind: '${((j['checklist_sources'] as Map?)?[kind.name]) ?? ''}',
        },
        defaultEventContainerId: j['default_event_container_id'] as String?,
        eventInvitees: [
          for (final a in (j['event_invitees'] as List? ?? const [])) '$a',
        ],
        seenHints: [
          for (final h in (j['seen_hints'] as List? ?? const [])) '$h',
        ],
      );

  /// When true, a date-only drop gets a random time of day on that date.
  final bool randomTimeOnDateDrop;

  /// Minutes before its due time that the app reminds the user of a task.
  /// A reminder that the user adds to a task in the task app uses it too.
  final int defaultReminderMinutes;

  /// Minutes before a calendar event starts that the app reminds the user.
  final int eventReminderMinutes;

  /// Id of the calendar that a new event starts in, or null to start in the
  /// calendar of the last event.
  final String? defaultEventContainerId;

  /// E-mail addresses of the people that the user usually invites to an
  /// event. The new event pop-up lists them.
  final List<String> eventInvitees;

  /// The ids of the hints that the user has seen. Each hint shows only once.
  final List<String> seenHints;

  /// The planning checklists: the items to go through at each kind of
  /// planning. A kind without items has no checklist.
  final Map<ChecklistKind, List<String>> checklists;

  /// The note path of each checklist. A non-empty path means that the
  /// checklist is read from the notes app and is read-only.
  final Map<ChecklistKind, String> checklistSources;

  /// The items of the checklist of [kind].
  List<String> itemsOf(ChecklistKind kind) => checklists[kind] ?? const [];

  /// The note path of the checklist of [kind]; empty when it is local.
  String sourceOf(ChecklistKind kind) => checklistSources[kind] ?? '';
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

/// A run of words in a checklist item. [url] is set when the run is a link.
@immutable
class ChecklistPart {
  /// Creates a part.
  const ChecklistPart(this.text, {this.url});

  /// The words of the part.
  final String text;

  /// The target of the link, or null for plain words.
  final String? url;
}

/// One item of a checklist, ticked or not in a period.
@immutable
class ChecklistItem {
  /// Creates an item.
  const ChecklistItem(this.text, {this.checked = false, this.parts = const []});

  /// The words of the item.
  final String text;

  /// True when the item is ticked in the period.
  final bool checked;

  /// The runs that build [text], with links. Empty for a local item.
  final List<ChecklistPart> parts;
}

/// The checklist of one week, month or year (`/checklists/{kind}/{day}`).
@immutable
class PeriodChecklist {
  /// Creates a checklist.
  const PeriodChecklist(this.items, {this.source, this.sourceUrl});

  /// Parses the checklist JSON object.
  factory PeriodChecklist.fromJson(Map<String, dynamic> j) => PeriodChecklist(
        [
          for (final i in (j['items'] as List? ?? const []))
            ChecklistItem(
              '${(i as Map)['text']}',
              checked: i['checked'] == true,
              parts: [
                for (final p in (i['parts'] as List? ?? const []))
                  ChecklistPart('${(p as Map)['text']}',
                      url: p['url'] as String?),
              ],
            ),
        ],
        source: j['source'] as String?,
        sourceUrl: j['source_url'] as String?,
      );

  /// The items of the user's list. Empty when they have not made one.
  final List<ChecklistItem> items;

  /// The note path that the list comes from, or null for a local list.
  final String? source;

  /// The address of that note in the notes app, or null when the app has none.
  final String? sourceUrl;

  /// How many items are ticked.
  int get done => items.where((i) => i.checked).length;

  /// The same checklist with [text] ticked or unticked.
  PeriodChecklist withTick(String text, bool checked) => PeriodChecklist([
        for (final i in items)
          i.text == text
              ? ChecklistItem(i.text, checked: checked, parts: i.parts)
              : i,
      ], source: source, sourceUrl: sourceUrl);
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
