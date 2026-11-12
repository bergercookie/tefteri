/// Read models for monthly planning and its immutable review snapshots.
library;

import 'package:flutter/foundation.dart';

Map<String, dynamic> _object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Map<String, dynamic>> _objects(Object? value) => [
      for (final item in value is List ? value : const [])
        if (item is Map) Map<String, dynamic>.from(item),
    ];

int? _integer(Object? value) => value is num ? value.toInt() : null;

/// One theme in a month's focus.
@immutable
class MonthEntry {
  /// Parses a planning entry.
  MonthEntry.fromJson(Map<String, dynamic> json)
      : id = '${json['id'] ?? ''}',
        projectId = '${json['project_id'] ?? ''}',
        connectionId = '${json['connection_id'] ?? ''}',
        name = '${json['name'] ?? ''}',
        target = _integer(json['target']),
        countsFrom = '${json['counts_from'] ?? ''}',
        leftOn = json['left_on'] as String?,
        status = '${json['status'] ?? 'in_focus'}',
        done = _integer(json['done']) ?? 0,
        earlierNotCounted = _integer(json['earlier_not_counted']) ?? 0,
        marker = json['marker'] as String?,
        orphaned = _object(json['orphaned']).isEmpty
            ? null
            : _object(json['orphaned']),
        labelChanged = json['label_changed'] as String?,
        linkedKeyResults = _integer(json['linked_key_results']) ?? 0,
        lastMonthDone = _integer(json['last_month_done']) ?? 0;

  /// Entry id.
  final String id;

  /// Theme project id.
  final String projectId;

  /// Task connection id.
  final String connectionId;

  /// Name at planning time (or stored name for an orphan).
  final String name;

  /// Milestone count target. Null means no target.
  final int? target;

  /// First date counted toward the target.
  final String countsFrom;

  /// Date the theme left the focus.
  final String? leftOn;

  /// `in_focus`, `swapped_out` or `removed`.
  final String status;

  /// Milestones counted toward this entry.
  final int done;

  /// Milestones finished before this entry started counting.
  final int earlierNotCounted;

  /// Result marker, or null before this month starts.
  final String? marker;

  /// Orphan reason and timestamp.
  final Map<String, dynamic>? orphaned;

  /// New project label, when it changed.
  final String? labelChanged;

  /// Number of linked key results.
  final int linkedKeyResults;

  /// Milestones completed under this theme last month.
  final int lastMonthDone;

  /// True while the theme remains in the focus.
  bool get inFocus => status == 'in_focus';
}

/// The monthly plan read model.
@immutable
class MonthPlan {
  /// Parses `GET /monthly/{month}`.
  MonthPlan.fromJson(Map<String, dynamic> json)
      : month = '${json['month'] ?? ''}',
        start = '${json['start'] ?? ''}',
        end = '${json['end'] ?? ''}',
        state = '${json['state'] ?? ''}',
        planningYear = _integer(json['planning_year']) ?? 0,
        focusKnown = json['focus_known'] == true,
        countNote = json['count_note'] as String?,
        entries = [
          for (final entry in _objects(json['entries']))
            MonthEntry.fromJson(entry),
        ],
        keyResults = _objects(json['key_results']),
        themesWithoutKeyResult = [
          for (final id
              in json['themes_without_key_result'] as List? ?? const [])
            '$id',
        ],
        review = _object(json['review']),
        earlierFormat = json['earlier_format'] == true;

  /// Month key, `YYYY-MM`.
  final String month;

  /// Inclusive first day.
  final String start;

  /// Exclusive first day of the next month.
  final String end;

  /// `past`, `current` or `future`.
  final String state;

  /// Year of annual planning that contains this month.
  final int planningYear;

  /// Whether this month has a saved focus, including an empty one.
  final bool focusKnown;

  /// Soft guidance for focus size.
  final String? countNote;

  /// Focus entries, active first.
  final List<MonthEntry> entries;

  /// Key results relevant to this focus.
  final List<Map<String, dynamic>> keyResults;

  /// Project ids with no linked key result.
  final List<String> themesWithoutKeyResult;

  /// Stored review version status.
  final Map<String, dynamic> review;

  /// Whether only legacy month goals exist.
  final bool earlierFormat;

  /// Entries that are still part of the focus.
  List<MonthEntry> get activeEntries =>
      entries.where((entry) => entry.inFocus).toList();
}

/// A theme picker option from the monthly API.
@immutable
class MonthTheme {
  /// Parses an eligible picker option.
  MonthTheme.fromJson(Map<String, dynamic> json)
      : projectId = '${json['project_id'] ?? ''}',
        connectionId = '${json['connection_id'] ?? ''}',
        connectionName = '${json['connection_name'] ?? ''}',
        name = '${json['name'] ?? ''}',
        inFocus = json['in_focus'] == true,
        leftThisMonth = json['left_this_month'] == true,
        lastMonthDone = _integer(json['last_month_done']) ?? 0,
        keyResultIds = [
          for (final id in json['key_result_ids'] as List? ?? const []) '$id',
        ];

  /// Theme project id.
  final String projectId;

  /// Connection id.
  final String connectionId;

  /// Connection name used to group the list.
  final String connectionName;

  /// Theme name.
  final String name;

  /// Whether it is already focused.
  final bool inFocus;

  /// Whether it left earlier this month and cannot be re-added.
  final bool leftThisMonth;

  /// Previous month's completed milestone count.
  final int lastMonthDone;

  /// Linked key result ids.
  final List<String> keyResultIds;
}

/// Theme picker data and task connections for the inline create action.
@immutable
class MonthThemePicker {
  /// Parses `GET /monthly/{month}/themes`.
  MonthThemePicker.fromJson(Map<String, dynamic> json)
      : themes = [
          for (final item in _objects(json['themes']))
            MonthTheme.fromJson(item),
        ],
        unsortedCount = _integer(json['unsorted_count']) ?? 0,
        taskConnections = _objects(json['task_connections']);

  /// Eligible theme choices.
  final List<MonthTheme> themes;

  /// Number of unclassified projects.
  final int unsortedCount;

  /// Connections where a theme can be created.
  final List<Map<String, dynamic>> taskConnections;

  /// Groups themes by connection, preserving the API's sorted order.
  Map<String, List<MonthTheme>> get grouped => {
        for (final theme in themes)
          theme.connectionName: [
            for (final candidate in themes)
              if (candidate.connectionName == theme.connectionName) candidate,
          ],
      };
}

/// The suggestion of a theme and optional target from a prior review.
@immutable
class MonthSuggestion {
  /// Parses one editable suggestion.
  MonthSuggestion.fromJson(Map<String, dynamic> json)
      : projectId = '${json['project_id'] ?? ''}',
        name = '${json['name'] ?? ''}',
        target = _integer(json['target']),
        reason = '${json['reason'] ?? 'carry'}',
        replaces = json['replaces'] == null ? null : _object(json['replaces']);

  /// Theme project id.
  final String projectId;

  /// Current theme name.
  final String name;

  /// Suggested target, editable before save.
  final int? target;

  /// `carry` or `replace`.
  final String reason;

  /// Theme this suggestion replaces, when applicable.
  final Map<String, dynamic>? replaces;
}

/// Suggestions and themes skipped from the last stored review.
@immutable
class MonthSuggestions {
  /// Parses `GET /monthly/{month}/suggestions`.
  MonthSuggestions.fromJson(Map<String, dynamic> json)
      : fromMonth = json['from_month'] as String?,
        suggestions = [
          for (final item in _objects(json['suggestions']))
            MonthSuggestion.fromJson(item),
        ],
        skipped = _objects(json['skipped']);

  /// Prior review month, if any.
  final String? fromMonth;

  /// Editable suggested focus entries.
  final List<MonthSuggestion> suggestions;

  /// Suggestions not carried forward and their reasons.
  final List<Map<String, dynamic>> skipped;
}

/// Read model of a monthly review or draft.
@immutable
class MonthReview {
  /// Parses `GET /monthly/{month}/review`.
  MonthReview.fromJson(Map<String, dynamic> json)
      : month = '${json['month'] ?? ''}',
        stored = json['stored'] == true,
        draft = json['draft'] == true,
        version = _integer(json['version']),
        currentVersion = _integer(json['current_version']),
        takenAt = json['taken_at'] as String?,
        versions = _objects(json['versions']),
        snapshot = _object(json['snapshot']),
        trend = _object(json['trend']),
        categoriesNote = json['categories_note'] as String?;

  /// Month key.
  final String month;

  /// True when this response is a stored snapshot.
  final bool stored;

  /// True for a live, unsaved draft.
  final bool draft;

  /// Selected snapshot version.
  final int? version;

  /// Current version number.
  final int? currentVersion;

  /// Time the snapshot was stored.
  final String? takenAt;

  /// Available immutable versions.
  final List<Map<String, dynamic>> versions;

  /// Snapshot payload (or live draft payload).
  final Map<String, dynamic> snapshot;

  /// Display-only category trend.
  final Map<String, dynamic> trend;

  /// No-data note from category reader.
  final String? categoriesNote;
}

/// One historical focus change.
@immutable
class MonthFocusChange {
  /// Parses a history entry.
  MonthFocusChange.fromJson(Map<String, dynamic> json)
      : batchId = '${json['batch_id'] ?? ''}',
        kind = '${json['kind'] ?? ''}',
        on = '${json['on'] ?? ''}',
        outName = json['out_name'] as String?,
        inName = json['in_name'] as String?,
        targetBefore = _integer(json['target_before']),
        targetAfter = _integer(json['target_after']),
        source = '${json['source'] ?? 'user'}',
        undone = json['undone'] == true,
        canUndo = json['can_undo'] == true;

  /// Batch id used to undo this change.
  final String batchId;

  /// Change type.
  final String kind;

  /// Local change date.
  final String on;

  /// Theme that left, if any.
  final String? outName;

  /// Theme that came, if any.
  final String? inName;

  /// Previous target.
  final int? targetBefore;

  /// New target.
  final int? targetAfter;

  /// User change or undo record.
  final String source;

  /// Whether an undo has already been made.
  final bool undone;

  /// Whether this change can be undone now.
  final bool canUndo;
}

/// Parses the ordered changes from the history endpoint.
List<MonthFocusChange> monthFocusChanges(Object? value) => [
      for (final item in _objects(_object(value)['changes']))
        MonthFocusChange.fromJson(item),
    ];

/// The original goal rows, shown read-only for legacy months.
List<Map<String, dynamic>> monthLegacyGoals(Object? value) => _objects(value);

/// Converts response data to string-keyed JSON maps.
Map<String, dynamic> monthJsonMap(Object? value) => _object(value);
