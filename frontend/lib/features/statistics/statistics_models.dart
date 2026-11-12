/// The numbers and lists of the work categories, as the server sends them.
///
/// The server decides every category and every percentage. These classes only
/// read the answer; they never work out a category or a share.
library;

import 'package:flutter/foundation.dart' show immutable;

import '../weekly/week_progress.dart';

/// Where a completed task belongs. The first three are the work categories;
/// [hidden] is the quiet count of tasks in ignored projects.
enum Category {
  /// Work in a milestone that was committed for the week.
  goalAligned('goal_aligned'),

  /// Work in a maintenance project.
  maintenance('maintenance'),

  /// Goal-type work that was not committed.
  offPlan('off_plan'),

  /// A task in an ignored project. It is in no work category.
  hidden('hidden');

  const Category(this.json);

  /// The value in the API and in addresses.
  final String json;

  /// The three work categories, in the order they are always shown.
  static const work = [goalAligned, maintenance, offPlan];

  /// The category called [value] in the API, or null when unknown.
  static Category? tryParse(String? value) {
    for (final c in values) {
      if (c.json == value) return c;
    }
    return null;
  }

  /// Like [tryParse], but a value this client does not know is an error: a
  /// list must never put a task in the wrong group.
  static Category parse(Object? value) =>
      tryParse('$value') ?? (throw FormatException('Unknown category $value'));
}

/// The three counts (or the three percentages) of a period.
@immutable
class CategoryCounts {
  /// Creates the counts.
  const CategoryCounts(this.goalAligned, this.maintenance, this.offPlan);

  /// Reads the `{goal_aligned, maintenance, off_plan}` object.
  factory CategoryCounts.fromJson(Object? json) {
    final j = (json as Map?) ?? const {};
    int n(String k) => (j[k] as num? ?? 0).toInt();
    return CategoryCounts(n('goal_aligned'), n('maintenance'), n('off_plan'));
  }

  /// All zero.
  static const zero = CategoryCounts(0, 0, 0);

  /// Goal-aligned tasks.
  final int goalAligned;

  /// Maintenance tasks.
  final int maintenance;

  /// Off-plan tasks.
  final int offPlan;

  /// The number for a work category. [Category.hidden] has none here.
  int of(Category c) => switch (c) {
        Category.goalAligned => goalAligned,
        Category.maintenance => maintenance,
        Category.offPlan => offPlan,
        Category.hidden => 0,
      };

  /// Whether there is nothing to show (the bar draws nothing).
  bool get isZero => goalAligned == 0 && maintenance == 0 && offPlan == 0;

  @override
  bool operator ==(Object other) =>
      other is CategoryCounts &&
      other.goalAligned == goalAligned &&
      other.maintenance == maintenance &&
      other.offPlan == offPlan;

  @override
  int get hashCode => Object.hash(goalAligned, maintenance, offPlan);
}

/// One day of a week or month, or one month of a year.
@immutable
class StatPart {
  /// Creates a part.
  const StatPart(
      {required this.start,
      required this.end,
      required this.counts,
      this.hidden = 0});

  /// Reads a part.
  factory StatPart.fromJson(Map<String, dynamic> j) => StatPart(
        start: DateTime.parse('${j['start']}'),
        end: DateTime.parse('${j['end']}'),
        counts: CategoryCounts.fromJson(j['counts']),
        hidden: (j['hidden'] as num? ?? 0).toInt(),
      );

  /// First day of the part.
  final DateTime start;

  /// First day after the part.
  final DateTime end;

  /// Its three counts.
  final CategoryCounts counts;

  /// Its hidden count.
  final int hidden;
}

/// Why a period has nothing to show, and the one thing to do about it.
@immutable
class StatEmpty {
  /// Creates the reason.
  const StatEmpty(this.reason, this.action);

  /// Reads the `empty` object.
  factory StatEmpty.fromJson(Map<String, dynamic> j) =>
      StatEmpty('${j['reason']}', '${j['action']}');

  /// `no_tasks` or `no_labels`.
  final String reason;

  /// `plan_week` or `label_projects`.
  final String action;

  /// No project has a label yet.
  bool get noLabels => reason == 'no_labels';
}

/// When the task apps were last read, and how the last read ended.
@immutable
class StatSync {
  /// Creates the state.
  const StatSync({this.lastSyncedAt, this.outcome});

  /// Reads the `sync` object.
  factory StatSync.fromJson(Object? json) {
    final j = (json as Map?) ?? const {};
    final at = j['last_synced_at'];
    return StatSync(
      lastSyncedAt: at == null ? null : DateTime.parse('$at'),
      outcome: j['outcome'] as String?,
    );
  }

  /// End of the newest sync, or null before the first one.
  final DateTime? lastSyncedAt;

  /// `ok`, `auth_expired`, `unreachable`, `error` or null.
  final String? outcome;

  /// The newest sync did not end well.
  bool get failed => outcome != null && outcome != 'ok';
}

/// `GET /statistics`: the counts of one period.
@immutable
class StatisticsSummary {
  /// Creates a summary.
  const StatisticsSummary({
    required this.period,
    required this.start,
    required this.end,
    required this.available,
    required this.counts,
    required this.total,
    required this.percentages,
    required this.hidden,
    required this.unsorted,
    required this.parts,
    required this.sync,
    this.unavailableReason,
    this.empty,
    this.progress,
  });

  /// Reads the answer.
  factory StatisticsSummary.fromJson(Map<String, dynamic> j) =>
      StatisticsSummary(
        period: '${j['period']}',
        start: DateTime.parse('${j['start']}'),
        end: DateTime.parse('${j['end']}'),
        available: j['available'] as bool? ?? true,
        unavailableReason: j['unavailable_reason'] as String?,
        counts: CategoryCounts.fromJson(j['counts']),
        total: (j['total'] as num? ?? 0).toInt(),
        percentages: CategoryCounts.fromJson(j['percentages']),
        hidden: (j['hidden'] as num? ?? 0).toInt(),
        unsorted: (j['unsorted'] as num? ?? 0).toInt(),
        parts: [
          for (final p in (j['parts'] as List? ?? const []))
            StatPart.fromJson(p as Map<String, dynamic>),
        ],
        empty: j['empty'] == null
            ? null
            : StatEmpty.fromJson(j['empty'] as Map<String, dynamic>),
        sync: StatSync.fromJson(j['sync']),
        progress: j['progress'] == null
            ? null
            : WeekProgress.fromJson(j['progress'] as Map<String, dynamic>),
      );

  /// `week`, `month` or `year`.
  final String period;

  /// First day of the period.
  final DateTime start;

  /// First day after the period.
  final DateTime end;

  /// False when the weekly commitment cannot be read. Then there is no number.
  final bool available;

  /// Why it is not available.
  final String? unavailableReason;

  /// The three counts.
  final CategoryCounts counts;

  /// The sum of the three counts. Hidden tasks are not in it.
  final int total;

  /// The three shares, whole numbers that add up to 100 (or all zero).
  final CategoryCounts percentages;

  /// Tasks in ignored projects.
  final int hidden;

  /// Off-plan tasks that carry the "unsorted" note.
  final int unsorted;

  /// The days of a week or month, or the months of a year.
  final List<StatPart> parts;

  /// Why there is nothing to show, or null.
  final StatEmpty? empty;

  /// The last sync.
  final StatSync sync;

  /// The committed plan of a week, or null.
  final WeekProgress? progress;
}

/// The project of a completed task.
@immutable
class StatProject {
  /// Creates a project.
  const StatProject(
      {this.id, required this.name, this.color, this.orphaned = false});

  /// Reads the `project` object.
  factory StatProject.fromJson(Object? json) {
    final j = (json as Map?) ?? const {};
    return StatProject(
      id: j['id'] as String?,
      name: '${j['name'] ?? ''}',
      color: j['color'] as String?,
      orphaned: j['orphaned'] as bool? ?? false,
    );
  }

  /// Id of the project label, or null for a task with no project.
  final String? id;

  /// The name kept at the time of completion.
  final String name;

  /// Its color in the task app, `#rrggbb`.
  final String? color;

  /// The project is gone from the task app.
  final bool orphaned;
}

/// A completed task in a list.
@immutable
class StatTask {
  /// Creates a task.
  const StatTask({
    required this.id,
    required this.title,
    required this.completedDay,
    required this.category,
    required this.project,
    this.reason = '',
    this.unsorted = false,
    this.url,
  });

  /// Reads a task of `GET /statistics/tasks`.
  factory StatTask.fromJson(Map<String, dynamic> j) => StatTask(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        completedDay: DateTime.parse('${j['completed_day']}'),
        category: Category.parse(j['category']),
        reason: '${j['reason'] ?? ''}',
        unsorted: j['unsorted'] as bool? ?? false,
        project: StatProject.fromJson(j['project']),
        url: j['url'] as String?,
      );

  /// Task id.
  final String id;

  /// Task title.
  final String title;

  /// The local day it was completed.
  final DateTime completedDay;

  /// Its category, decided once when Tefteri first saw it done.
  final Category category;

  /// Why, as a code. The client shows no code.
  final String reason;

  /// The project has no label, or the task has no project.
  final bool unsorted;

  /// The project it was in when it was completed.
  final StatProject project;

  /// Page of the task in the task app.
  final String? url;
}

/// One page of `GET /statistics/tasks`.
@immutable
class StatTasksPage {
  /// Creates a page.
  const StatTasksPage(
      {required this.total, required this.items, this.nextCursor});

  /// Reads the answer.
  factory StatTasksPage.fromJson(Map<String, dynamic> j) => StatTasksPage(
        total: (j['total'] as num? ?? 0).toInt(),
        items: [
          for (final t in (j['items'] as List? ?? const []))
            StatTask.fromJson(t as Map<String, dynamic>),
        ],
        nextCursor: j['next_cursor'] as String?,
      );

  /// Tasks for the filter, over the whole period.
  final int total;

  /// The tasks of this page.
  final List<StatTask> items;

  /// Where the next page starts, or null on the last page.
  final String? nextCursor;
}
