/// Data models of the annual plan: goals, key results, theme links, flags,
/// the history of a year, suggestions from an earlier year and the push
/// token. They follow `/api/v1/annual/...` of feature 006.
library;

import 'package:flutter/foundation.dart';

List<Map<String, dynamic>> _maps(Object? v) => [
      for (final e in (v as List? ?? const []))
        if (e is Map) Map<String, dynamic>.from(e),
    ];

double _num(Object? v, [double fallback = 0]) =>
    v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? fallback);

double? _numOrNull(Object? v) => v is num ? v.toDouble() : null;

String? _str(Object? v) => v == null ? null : '$v';

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v');

/// Formats [v] without a trailing `.0`, for example `120` or `1.5`.
String formatNumber(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
  final s = v.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// `YYYY-MM-DD` of [d].
String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The share of the way from [start] to [target] that [current] has gone, in
/// either direction (a lower target counts down). It is not capped: 1.2 means
/// 120%.
double keyResultProgress(double start, double target, double current) {
  if (target == start) return 0;
  return (current - start) / (target - start);
}

/// Why a linked project does not count as a usable theme.
@immutable
class FlagReason {
  /// Creates a reason.
  const FlagReason(
      {required this.state, this.name, this.label, this.projectId});

  /// Parses one entry of `reasons`.
  factory FlagReason.fromJson(Map<String, dynamic> j) => FlagReason(
        projectId: _str(j['project_id']),
        name: _str(j['name']),
        state: '${j['state'] ?? 'no_links'}',
        label: _str(j['label']),
      );

  /// The linked project, or null for `no_links`.
  final String? projectId;

  /// The stored name of the project.
  final String? name;

  /// `no_links`, `orphaned`, `ignored`, `relabelled` or `unclassified`.
  final String state;

  /// The new label of a relabelled project.
  final String? label;

  /// The reason in words, such as `"Open source" is ignored.`
  String get sentence {
    if (state == 'no_links') return 'No theme is linked.';
    final who = '"${name ?? 'A project'}"';
    return switch (state) {
      'orphaned' => '$who is no longer in your task app.',
      'ignored' => '$who is ignored.',
      'relabelled' => '$who is now labelled ${label ?? 'as something else'}.',
      'unclassified' => '$who has no label yet.',
      _ => '$who cannot be used.',
    };
  }
}

/// A warning on a goal or key result. It never blocks a save.
@immutable
class PlanFlag {
  /// Creates a flag.
  const PlanFlag(
      {required this.code, this.actions = const [], this.reasons = const []});

  /// Parses one flag.
  factory PlanFlag.fromJson(Map<String, dynamic> j) => PlanFlag(
        code: '${j['code']}',
        actions: [for (final a in (j['actions'] as List? ?? const [])) '$a'],
        reasons: [for (final r in _maps(j['reasons'])) FlagReason.fromJson(r)],
      );

  /// `no_key_result`, `no_usable_theme` or `overdue`.
  final String code;

  /// The inline actions: `add_key_result`, `link_theme`, `create_theme`,
  /// `update_value`.
  final List<String> actions;

  /// For `no_usable_theme`: why each link is not usable.
  final List<FlagReason> reasons;
}

/// A link from a key result to a theme project.
@immutable
class ThemeLink {
  /// Creates a link.
  const ThemeLink({
    required this.id,
    required this.projectId,
    required this.name,
    required this.active,
    required this.usable,
    required this.state,
    this.label,
    this.startedAt,
    this.endedAt,
  });

  /// Parses one link.
  factory ThemeLink.fromJson(Map<String, dynamic> j) => ThemeLink(
        id: '${j['id']}',
        projectId: '${j['project_id']}',
        name: '${j['name'] ?? ''}',
        active: j['active'] != false,
        usable: j['usable'] == true,
        state: '${j['state'] ?? 'ok'}',
        label: _str(j['label']),
        startedAt: _date(j['started_at']),
        endedAt: _date(j['ended_at']),
      );

  /// Link id.
  final String id;

  /// The theme project.
  final String projectId;

  /// Its stored name.
  final String name;

  /// False once the link has ended.
  final bool active;

  /// True when the project is still a live theme.
  final bool usable;

  /// `ok`, `orphaned`, `ignored`, `relabelled` or `unclassified`.
  final String state;

  /// The current label of the project.
  final String? label;

  /// When the link started.
  final DateTime? startedAt;

  /// When it ended, or null.
  final DateTime? endedAt;
}

/// A key result: a number with a start value, a target and a deadline.
@immutable
class KeyResult {
  /// Creates a key result.
  const KeyResult({
    required this.id,
    required this.goalId,
    required this.metric,
    required this.startValue,
    required this.target,
    required this.deadline,
    required this.updateSource,
    required this.status,
    required this.currentValue,
    this.kind = 'number',
    this.currentAt,
    this.met = false,
    this.retiredAt,
    this.flags = const [],
    this.links = const [],
  });

  /// Parses one key result.
  factory KeyResult.fromJson(Map<String, dynamic> j) {
    final start = _num(j['start_value']);
    return KeyResult(
      id: '${j['id']}',
      goalId: '${j['goal_id'] ?? ''}',
      metric: '${j['metric'] ?? ''}',
      kind: '${j['kind'] ?? 'number'}',
      startValue: start,
      target: _num(j['target']),
      deadline: '${j['deadline'] ?? ''}',
      updateSource: '${j['update_source'] ?? 'manual'}',
      status: '${j['status'] ?? 'active'}',
      currentValue: _numOrNull(j['current_value']) ?? start,
      currentAt: _date(j['current_at']),
      met: j['met'] == true,
      retiredAt: _date(j['retired_at']),
      flags: [for (final f in _maps(j['flags'])) PlanFlag.fromJson(f)],
      links: [for (final l in _maps(j['links'])) ThemeLink.fromJson(l)],
    );
  }

  /// Key result id.
  final String id;

  /// The goal it belongs to.
  final String goalId;

  /// What is measured, such as "Stars on one repository".
  final String metric;

  /// `number` or `yes_no`.
  final String kind;

  /// The value at the start.
  final double startValue;

  /// The value to reach.
  final double target;

  /// The deadline, `YYYY-MM-DD`.
  final String deadline;

  /// `manual` or `automatic`.
  final String updateSource;

  /// `active` or `retired`.
  final String status;

  /// The latest value, or the start value while the series is empty.
  final double currentValue;

  /// When the current value was stored; null for the start value.
  final DateTime? currentAt;

  /// True when the current value reached the target.
  final bool met;

  /// When it was retired.
  final DateTime? retiredAt;

  /// The flags of an active key result.
  final List<PlanFlag> flags;

  /// Its links, the active ones and the ended ones.
  final List<ThemeLink> links;

  /// True while it counts.
  bool get active => status == 'active';

  /// True for a yes/no key result.
  bool get yesNo => kind == 'yes_no';

  /// The answer of a yes/no key result.
  String get yesNoAnswer => currentValue >= 0.5 ? 'Yes' : 'No';

  /// True when an outside source may push values.
  bool get automatic => updateSource == 'automatic';

  /// The links that have not ended.
  List<ThemeLink> get activeLinks => [
        for (final l in links)
          if (l.active) l
      ];

  /// The progress from the start value to the target; not capped.
  double get progress => keyResultProgress(startValue, target, currentValue);
}

/// A goal of the annual plan.
@immutable
class AnnualGoal {
  /// Creates a goal.
  const AnnualGoal({
    required this.id,
    required this.title,
    required this.status,
    this.legacyDone = false,
    this.criteriaSuggestion,
    this.flags = const [],
    this.notes = const [],
    this.keyResults = const [],
  });

  /// Parses one goal.
  factory AnnualGoal.fromJson(Map<String, dynamic> j) => AnnualGoal(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        status: '${j['status'] ?? 'active'}',
        legacyDone: j['legacy_done'] == true,
        criteriaSuggestion: (j['criteria_suggestion'] as String?)?.trim() == ''
            ? null
            : j['criteria_suggestion'] as String?,
        flags: [for (final f in _maps(j['flags'])) PlanFlag.fromJson(f)],
        notes: [for (final n in (j['notes'] as List? ?? const [])) '$n'],
        keyResults: [
          for (final k in _maps(j['key_results'])) KeyResult.fromJson(k)
        ],
      );

  /// Goal id.
  final String id;

  /// The loose sentence.
  final String title;

  /// `active` or `retired` (an old completed goal is `done`).
  final String status;

  /// True for a goal marked complete before annual planning.
  final bool legacyDone;

  /// The old criteria text, offered as a metric while there is no key result.
  final String? criteriaSuggestion;

  /// The flags of the goal.
  final List<PlanFlag> flags;

  /// Quiet hints, such as `duplicate_metric`.
  final List<String> notes;

  /// All key results, active and retired.
  final List<KeyResult> keyResults;

  /// The key results that count.
  List<KeyResult> get activeKeyResults => [
        for (final k in keyResults)
          if (k.active) k
      ];

  /// The retired key results.
  List<KeyResult> get retiredKeyResults => [
        for (final k in keyResults)
          if (!k.active) k
      ];
}

/// The plan of one planning year (`GET /annual/{year}`).
@immutable
class AnnualPlan {
  /// Creates a plan.
  const AnnualPlan({
    required this.year,
    required this.state,
    required this.editable,
    this.goals = const [],
    this.retiredGoals = const [],
  });

  /// Parses the plan.
  factory AnnualPlan.fromJson(Map<String, dynamic> j) => AnnualPlan(
        year: (j['year'] as num?)?.toInt() ?? 0,
        state: '${j['state'] ?? 'current'}',
        editable: j['editable'] != false,
        goals: [for (final g in _maps(j['goals'])) AnnualGoal.fromJson(g)],
        retiredGoals: [
          for (final g in _maps(j['retired_goals'])) AnnualGoal.fromJson(g)
        ],
      );

  /// The planning year.
  final int year;

  /// `past`, `current` or `future`.
  final String state;

  /// False in a past year: only values can be entered then.
  final bool editable;

  /// The active goals.
  final List<AnnualGoal> goals;

  /// The retired goals, for the history part of the screen.
  final List<AnnualGoal> retiredGoals;

  /// The key result [id], or null.
  KeyResult? keyResult(String id) {
    for (final g in [...goals, ...retiredGoals]) {
      for (final k in g.keyResults) {
        if (k.id == id) return k;
      }
    }
    return null;
  }

  /// The goal [id], or null.
  AnnualGoal? goal(String id) {
    for (final g in [...goals, ...retiredGoals]) {
      if (g.id == id) return g;
    }
    return null;
  }
}

/// A theme the picker offers (`GET /annual/themes`).
@immutable
class ThemeOption {
  /// Creates an option.
  const ThemeOption({
    required this.projectId,
    required this.name,
    this.connectionId = '',
    this.connectionName = '',
    this.keyResultIds = const [],
  });

  /// Parses one theme.
  factory ThemeOption.fromJson(Map<String, dynamic> j) => ThemeOption(
        projectId: '${j['project_id']}',
        name: '${j['name'] ?? ''}',
        connectionId: '${j['connection_id'] ?? ''}',
        connectionName: '${j['connection_name'] ?? ''}',
        keyResultIds: [
          for (final k in (j['key_result_ids'] as List? ?? const [])) '$k'
        ],
      );

  /// The project id.
  final String projectId;

  /// The project name.
  final String name;

  /// The task connection that holds it.
  final String connectionId;

  /// The name of that connection.
  final String connectionName;

  /// The key results it serves.
  final List<String> keyResultIds;
}

/// A task connection that can hold a new theme.
@immutable
class TaskConnection {
  /// Creates a connection.
  const TaskConnection(
      {required this.id, required this.name, this.canCreate = true});

  /// Parses one connection.
  factory TaskConnection.fromJson(Map<String, dynamic> j) => TaskConnection(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        canCreate: j['can_create'] != false,
      );

  /// Connection id.
  final String id;

  /// Its name.
  final String name;

  /// True when it can create projects.
  final bool canCreate;
}

/// The answer of `GET /annual/themes`.
@immutable
class ThemeChoices {
  /// Creates the choices.
  const ThemeChoices(
      {this.themes = const [],
      this.unsortedCount = 0,
      this.taskConnections = const []});

  /// Parses the answer.
  factory ThemeChoices.fromJson(Map<String, dynamic> j) => ThemeChoices(
        themes: [for (final t in _maps(j['themes'])) ThemeOption.fromJson(t)],
        unsortedCount: (j['unsorted_count'] as num?)?.toInt() ?? 0,
        taskConnections: [
          for (final c in _maps(j['task_connections']))
            TaskConnection.fromJson(c)
        ],
      );

  /// The eligible themes.
  final List<ThemeOption> themes;

  /// How many projects have no label yet.
  final int unsortedCount;

  /// The connections a theme can be created in.
  final List<TaskConnection> taskConnections;
}

/// What a retire does, from a dry run.
@immutable
class RetireEffect {
  /// Creates the effect.
  const RetireEffect(
      {this.keyResultsRetired = 0,
      this.linksEnded = 0,
      this.flagsRemoved = const [],
      this.historyKept = true});

  /// Parses `effect`.
  factory RetireEffect.fromJson(Object? v) {
    final j = v is Map ? v : const {};
    return RetireEffect(
      keyResultsRetired: (j['key_results_retired'] as num?)?.toInt() ?? 0,
      linksEnded: (j['links_ended'] as num?)?.toInt() ?? 0,
      flagsRemoved: [
        for (final f in (j['flags_removed'] as List? ?? const [])) '$f'
      ],
      historyKept: j['history_kept'] != false,
    );
  }

  /// How many key results retire.
  final int keyResultsRetired;

  /// How many links end.
  final int linksEnded;

  /// The flags that go away.
  final List<String> flagsRemoved;

  /// True: the history stays.
  final bool historyKept;
}

/// A project named in a link effect.
typedef NamedProject = ({String projectId, String name});

/// What a change of links does, from a dry run.
@immutable
class LinkEffect {
  /// Creates the effect.
  const LinkEffect({this.added = const [], this.ended = const []});

  /// Parses `effect`.
  factory LinkEffect.fromJson(Object? v) {
    final j = v is Map ? v : const {};
    List<NamedProject> named(Object? list) => [
          for (final p in _maps(list))
            (projectId: '${p['project_id']}', name: '${p['name'] ?? ''}'),
        ];
    return LinkEffect(added: named(j['added']), ended: named(j['ended']));
  }

  /// The links that start.
  final List<NamedProject> added;

  /// The links that end.
  final List<NamedProject> ended;
}

/// One line of the history of a year.
@immutable
class PlanChange {
  /// Creates a line.
  const PlanChange({
    required this.id,
    required this.kind,
    required this.batchId,
    required this.source,
    required this.at,
    this.goalId,
    this.keyResultId,
    this.field,
    this.oldValue,
    this.newValue,
    this.reason,
    this.undone = false,
  });

  /// Parses one change.
  factory PlanChange.fromJson(Map<String, dynamic> j) => PlanChange(
        id: '${j['id']}',
        kind: '${j['kind'] ?? ''}',
        goalId: _str(j['goal_id']),
        keyResultId: _str(j['key_result_id']),
        field: _str(j['field']),
        oldValue: _str(j['old_value']),
        newValue: _str(j['new_value']),
        reason: _str(j['reason']),
        batchId: '${j['batch_id'] ?? ''}',
        source: '${j['source'] ?? 'user'}',
        at: _date(j['at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        undone: j['undone'] == true,
      );

  /// Change id.
  final String id;

  /// What happened, such as `key_result_retired`.
  final String kind;

  /// The goal.
  final String? goalId;

  /// The key result.
  final String? keyResultId;

  /// The changed field of an edit.
  final String? field;

  /// The value before.
  final String? oldValue;

  /// The value after.
  final String? newValue;

  /// The reason the user gave.
  final String? reason;

  /// The user action this line belongs to.
  final String batchId;

  /// `user`, `undo`, `seed` or `migration`.
  final String source;

  /// When it happened.
  final DateTime at;

  /// True when the batch was undone later.
  final bool undone;
}

/// A key result that a new year can take over from year N.
@immutable
class SuggestedKeyResult {
  /// Creates a suggestion.
  const SuggestedKeyResult({
    required this.keyResultId,
    required this.metric,
    required this.startValue,
    required this.target,
    required this.deadline,
    this.kind = 'number',
    this.updateSource = 'manual',
    this.themes = const [],
  });

  /// Parses one suggestion.
  factory SuggestedKeyResult.fromJson(Map<String, dynamic> j) =>
      SuggestedKeyResult(
        keyResultId: '${j['key_result_id']}',
        metric: '${j['metric'] ?? ''}',
        kind: '${j['kind'] ?? 'number'}',
        startValue: _num(j['start_value']),
        target: _num(j['target']),
        deadline: '${j['deadline'] ?? ''}',
        updateSource: '${j['update_source'] ?? 'manual'}',
        themes: [
          for (final t in _maps(j['themes']))
            ThemeOption(projectId: '${t['project_id']}', name: '${t['name']}')
        ],
      );

  /// The key result of year N.
  final String keyResultId;

  /// Its metric.
  final String metric;

  /// `number` or `yes_no`.
  final String kind;

  /// The last value of year N, the new start value.
  final double startValue;

  /// Its target.
  final double target;

  /// The deadline moved into the new year.
  final String deadline;

  /// `manual` or `automatic`.
  final String updateSource;

  /// The themes whose links are still usable.
  final List<ThemeOption> themes;
}

/// A goal that a new year can take over from year N.
@immutable
class SuggestedGoal {
  /// Creates a suggestion.
  const SuggestedGoal(
      {required this.goalId, required this.title, this.keyResults = const []});

  /// Parses one suggestion.
  factory SuggestedGoal.fromJson(Map<String, dynamic> j) => SuggestedGoal(
        goalId: '${j['goal_id']}',
        title: '${j['title'] ?? ''}',
        keyResults: [
          for (final k in _maps(j['key_results']))
            SuggestedKeyResult.fromJson(k)
        ],
      );

  /// The goal of year N.
  final String goalId;

  /// Its sentence.
  final String title;

  /// Its unmet key results.
  final List<SuggestedKeyResult> keyResults;
}

/// The answer of `GET /annual/{year}/suggestions`.
@immutable
class PlanSuggestions {
  /// Creates the answer.
  const PlanSuggestions(
      {required this.year,
      required this.fromYear,
      required this.hasPlan,
      this.goals = const []});

  /// Parses the answer.
  factory PlanSuggestions.fromJson(Map<String, dynamic> j) => PlanSuggestions(
        year: (j['year'] as num?)?.toInt() ?? 0,
        fromYear: (j['from_year'] as num?)?.toInt() ?? 0,
        hasPlan: j['has_plan'] == true,
        goals: [for (final g in _maps(j['goals'])) SuggestedGoal.fromJson(g)],
      );

  /// The new year.
  final int year;

  /// Year N.
  final int fromYear;

  /// False when year N has no goals.
  final bool hasPlan;

  /// The suggested goals.
  final List<SuggestedGoal> goals;
}

/// A key result to create, with its links.
@immutable
class KeyResultDraft {
  /// Creates a draft.
  const KeyResultDraft({
    required this.metric,
    required this.startValue,
    required this.target,
    required this.deadline,
    this.kind = 'number',
    this.updateSource = 'manual',
    this.themes = const [],
    this.seededFromKeyResultId,
  });

  /// What is measured.
  final String metric;

  /// `number` or `yes_no`.
  final String kind;

  /// The start value.
  final double startValue;

  /// The target.
  final double target;

  /// `YYYY-MM-DD`.
  final String deadline;

  /// `manual` or `automatic`.
  final String updateSource;

  /// The themes to link.
  final List<ThemeOption> themes;

  /// The key result of year N it was taken from.
  final String? seededFromKeyResultId;

  /// The request body.
  Map<String, Object?> toJson() => {
        'metric': metric,
        'kind': kind,
        'start_value': startValue,
        'target': target,
        'deadline': deadline,
        'update_source': updateSource,
        'theme_ids': [for (final t in themes) t.projectId],
        if (seededFromKeyResultId != null)
          'seeded_from_key_result_id': seededFromKeyResultId,
      };
}

/// A goal to create in a bulk save.
@immutable
class GoalDraft {
  /// Creates a draft.
  const GoalDraft(
      {required this.title, this.keyResults = const [], this.seededFromGoalId});

  /// The sentence.
  final String title;

  /// Its key results.
  final List<KeyResultDraft> keyResults;

  /// The goal of year N it was taken from.
  final String? seededFromGoalId;

  /// The request body.
  Map<String, Object?> toJson() => {
        'title': title,
        if (seededFromGoalId != null) 'seeded_from_goal_id': seededFromGoalId,
        'key_results': [for (final k in keyResults) k.toJson()],
      };
}

/// An old goal row of a week, a month or a year (`GET /goals/history`).
@immutable
class LegacyGoal {
  /// Creates a row.
  const LegacyGoal({
    required this.id,
    required this.periodType,
    required this.periodStart,
    required this.title,
    required this.status,
    this.parentId,
    this.criteria = '',
    this.linkedTasks = 0,
  });

  /// Parses one row.
  factory LegacyGoal.fromJson(Map<String, dynamic> j) => LegacyGoal(
        id: '${j['id']}',
        parentId: _str(j['parent_id']),
        periodType: '${j['period_type'] ?? 'week'}',
        periodStart: '${j['period_start'] ?? ''}',
        title: '${j['title'] ?? ''}',
        criteria: '${j['criteria'] ?? ''}',
        status: '${j['status'] ?? 'active'}',
        linkedTasks: (j['linked_tasks'] as num?)?.toInt() ?? 0,
      );

  /// Goal id.
  final String id;

  /// The parent goal, if any.
  final String? parentId;

  /// `year`, `month` or `week`.
  final String periodType;

  /// The first day of the period.
  final String periodStart;

  /// The sentence.
  final String title;

  /// The old criteria text.
  final String criteria;

  /// `active`, `done`, `dropped` or `retired`.
  final String status;

  /// How many tasks point to it.
  final int linkedTasks;
}

/// The state of the push token (`GET /annual/push-token`).
@immutable
class PushTokenInfo {
  /// Creates the state.
  const PushTokenInfo(
      {required this.exists, this.hint, this.createdAt, this.lastUsedAt});

  /// Parses the answer.
  factory PushTokenInfo.fromJson(Map<String, dynamic> j) => PushTokenInfo(
        exists: j['exists'] == true,
        hint: _str(j['hint']),
        createdAt: _date(j['created_at']),
        lastUsedAt: _date(j['last_used_at']),
      );

  /// True when a token exists.
  final bool exists;

  /// The last characters of the token.
  final String? hint;

  /// When it was made.
  final DateTime? createdAt;

  /// When a source last used it.
  final DateTime? lastUsedAt;
}
