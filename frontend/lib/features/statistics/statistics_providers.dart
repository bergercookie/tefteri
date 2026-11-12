/// State of the category card and its lists.
library;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_models.dart';
import '../goals/periods.dart';
import 'statistics_api.dart';
import 'statistics_models.dart';

/// The days that name a period for the server: the Monday of a week, the
/// first of a month and the first of January.
String periodDayKey(String period, DateTime day) => switch (period) {
      'month' => dateKey(DateTime(day.year, day.month, 1)),
      'year' => dateKey(DateTime(day.year, 1, 1)),
      _ => dateKey(weekStartOf(day)),
    };

/// Which summary to load.
@immutable
class StatsQuery {
  /// Creates the query; [day] is a `YYYY-MM-DD` key.
  const StatsQuery(this.period, this.day);

  /// `week`, `month` or `year`.
  final String period;

  /// A day of the period, as a key.
  final String day;

  @override
  bool operator ==(Object other) =>
      other is StatsQuery && other.period == period && other.day == day;

  @override
  int get hashCode => Object.hash(period, day);
}

/// The summary of a period. It is read again whenever the page is built
/// anew and when a sync ends.
final statisticsProvider = FutureProvider.autoDispose
    .family<StatisticsSummary, StatsQuery>(
        (ref, q) => ref.watch(statisticsApiProvider).summary(q.period, q.day));

/// Which list to load.
@immutable
class TaskListQuery {
  /// Creates the query.
  const TaskListQuery({
    required this.period,
    required this.day,
    this.category,
    this.order = 'newest',
    this.limit = 50,
  });

  /// `week`, `month` or `year`.
  final String period;

  /// A day of the period, as a key.
  final String day;

  /// The category, or null for the three work categories.
  final Category? category;

  /// `newest` or `project`.
  final String order;

  /// Tasks per page.
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is TaskListQuery &&
      other.period == period &&
      other.day == day &&
      other.category == category &&
      other.order == order &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(period, day, category, order, limit);
}

/// What the list holds so far.
@immutable
class TaskListState {
  /// Creates a state.
  const TaskListState({
    this.items = const [],
    this.total,
    this.nextCursor,
    this.loading = true,
    this.error,
  });

  /// The tasks loaded so far, each once.
  final List<StatTask> items;

  /// Tasks in the whole list, known after the first page.
  final int? total;

  /// Where the next page starts; null on the last page or before the first.
  final String? nextCursor;

  /// A page is on its way.
  final bool loading;

  /// What went wrong with the last page, or null.
  final String? error;

  /// The first page has not arrived yet.
  bool get first => total == null && error == null;

  /// More tasks can be loaded.
  bool get hasMore => nextCursor != null;
}

/// Loads a list page by page. It keeps the cursor, asks for each page once
/// and never loads a page it already has.
class TaskListController extends StateNotifier<TaskListState> {
  /// Creates the controller and starts the first page.
  TaskListController(this._api, this.query) : super(const TaskListState()) {
    _load(null);
  }

  final StatisticsApi _api;

  /// The list this controller loads.
  final TaskListQuery query;

  /// Cursors that were asked for and answered; the first page is `''`.
  final Set<String> _done = {};
  bool _busy = false;

  Future<void> _load(String? cursor) async {
    if (_busy || _done.contains(cursor ?? '')) return;
    _busy = true;
    state = TaskListState(
      items: state.items,
      total: state.total,
      nextCursor: state.nextCursor,
      loading: true,
    );
    try {
      final page = await _api.tasks(
        period: query.period,
        day: query.day,
        category: query.category,
        order: query.order,
        limit: query.limit,
        cursor: cursor,
      );
      if (!mounted) return;
      _done.add(cursor ?? '');
      final seen = {for (final t in state.items) t.id};
      state = TaskListState(
        items: [
          ...state.items,
          for (final t in page.items)
            if (seen.add(t.id)) t,
        ],
        total: page.total,
        nextCursor: page.nextCursor,
        loading: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = TaskListState(
        items: state.items,
        total: state.total,
        nextCursor: state.nextCursor,
        loading: false,
        error: apiErrorMessage(e),
      );
    } finally {
      _busy = false;
    }
  }

  /// Loads the next page, once. Does nothing while a page is on its way or
  /// when the last page is in.
  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (cursor == null) return;
    await _load(cursor);
  }

  /// Asks again for the page that failed.
  Future<void> retry() =>
      state.items.isEmpty && state.total == null ? _load(null) : loadMore();
}

/// A list, kept while a widget watches it.
final taskListProvider = StateNotifierProvider.autoDispose
    .family<TaskListController, TaskListState, TaskListQuery>(
        (ref, q) => TaskListController(ref.watch(statisticsApiProvider), q));
