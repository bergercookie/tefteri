/// Data models for plan reviews and the plan history.
library;

import 'package:flutter/foundation.dart';

import '../../core/planning_models.dart';

/// A planned goal or task and whether it was completed.
@immutable
class ReviewItem {
  /// Creates an item.
  const ReviewItem({
    required this.type,
    required this.id,
    required this.title,
    required this.completed,
  });

  /// Parses an item JSON object.
  factory ReviewItem.fromJson(Map<String, dynamic> j) => ReviewItem(
        type: '${j['type']}',
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        completed: j['completed'] == true,
      );

  /// `goal` or `task`.
  final String type;

  /// Goal or task id.
  final String id;

  /// Title when the review was generated.
  final String title;

  /// True when it was completed when the review was generated.
  final bool completed;
}

/// Response of `GET /plans/{id}/review`: a snapshot of one plan's period.
@immutable
class PlanReview {
  /// Creates a review.
  const PlanReview({
    required this.planId,
    required this.planTitle,
    required this.periodType,
    required this.periodStart,
    required this.periodEnd,
    required this.periodEnded,
    required this.generatedAt,
    required this.plannedCount,
    required this.completedCount,
    required this.items,
    required this.carriedOver,
    this.retrospective,
  });

  /// Parses the review JSON.
  factory PlanReview.fromJson(Map<String, dynamic> j) => PlanReview(
        planId: '${j['plan_id']}',
        planTitle: '${j['plan_title'] ?? ''}',
        periodType: '${j['period_type']}',
        periodStart: '${j['period_start']}',
        periodEnd: '${j['period_end']}',
        periodEnded: j['period_ended'] == true,
        generatedAt: DateTime.parse('${j['generated_at']}'),
        plannedCount: (j['planned_count'] as num?)?.toInt() ?? 0,
        completedCount: (j['completed_count'] as num?)?.toInt() ?? 0,
        items: [
          for (final i in (j['items'] as List? ?? const []))
            ReviewItem.fromJson(i as Map<String, dynamic>),
        ],
        carriedOver: [
          for (final i in (j['carried_over'] as List? ?? const [])) '$i'
        ],
        retrospective: j['retrospective'] == null
            ? null
            : PlanNote.fromJson(j['retrospective'] as Map<String, dynamic>),
      );

  /// Plan id.
  final String planId;

  /// Plan title.
  final String planTitle;

  /// `year`, `month` or `week`.
  final String periodType;

  /// First day of the period (`YYYY-MM-DD`).
  final String periodStart;

  /// Day after the period (`YYYY-MM-DD`, exclusive).
  final String periodEnd;

  /// True when the period is over.
  final bool periodEnded;

  /// When the snapshot was taken.
  final DateTime generatedAt;

  /// Number of planned goals and tasks.
  final int plannedCount;

  /// Number of planned items that were completed.
  final int completedCount;

  /// Planned goals and tasks.
  final List<ReviewItem> items;

  /// Ids of planned items that were not completed.
  final List<String> carriedOver;

  /// The retrospective note, once saved.
  final PlanNote? retrospective;

  /// Goals belong to the annual plan only. The goals of a stored month or
  /// week plan are history, and the review says so.
  bool get goalsAreHistory => periodType == 'month' || periodType == 'week';

  /// The word for the planned goals: `planned goals`, or `goals (history)`
  /// for a month or week plan.
  String get goalsWord => goalsAreHistory ? 'goals (history)' : 'planned goals';

  /// The word for one item of type [type].
  String itemWord(String type) => type == 'task'
      ? 'Task'
      : goalsAreHistory
          ? 'Goal (history)'
          : 'Goal';

  /// Completed share (0..1); 0 when nothing was planned.
  double get ratio => plannedCount == 0 ? 0 : completedCount / plannedCount;
}

/// A plan in `GET /reviews/history`.
@immutable
class PlanHistoryEntry {
  /// Creates an entry.
  const PlanHistoryEntry({
    required this.planId,
    required this.title,
    required this.periodType,
    required this.periodStart,
    required this.periodEnded,
    this.plannedCount,
    this.completedCount,
    this.hasRetrospective = false,
  });

  /// Parses a history JSON object.
  factory PlanHistoryEntry.fromJson(Map<String, dynamic> j) {
    final review = j['review'] as Map<String, dynamic>?;
    return PlanHistoryEntry(
      planId: '${j['plan_id']}',
      title: '${j['title'] ?? ''}',
      periodType: '${j['period_type']}',
      periodStart: '${j['period_start']}',
      periodEnded: j['period_ended'] == true,
      plannedCount: (review?['planned_count'] as num?)?.toInt(),
      completedCount: (review?['completed_count'] as num?)?.toInt(),
      hasRetrospective: review?['has_retrospective'] == true,
    );
  }

  /// Plan id.
  final String planId;

  /// Plan title.
  final String title;

  /// `year`, `month` or `week`.
  final String periodType;

  /// First day of the period (`YYYY-MM-DD`).
  final String periodStart;

  /// True when the period is over.
  final bool periodEnded;

  /// Planned count of the stored review; null when there is no review yet.
  final int? plannedCount;

  /// Completed count of the stored review; null when there is no review yet.
  final int? completedCount;

  /// True when a retrospective was saved.
  final bool hasRetrospective;
}
