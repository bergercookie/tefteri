import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/api_client.dart';

/// Route value that makes the fake answer with an API error.
class ApiFailure {
  const ApiFailure(this.status, this.detail, this.code, {this.extra = const {}})
      : nested = false;

  /// The error shape of the classification routes:
  /// `{"detail": {"code": ..., "message": ...}}`.
  const ApiFailure.contract(this.status, this.code, String message)
      : detail = message,
        nested = true,
        extra = const {};

  final int status;
  final String detail;
  final String code;
  final bool nested;

  /// More fields of the body, such as the tasks that a failed move had
  /// already moved.
  final Map<String, Object?> extra;
}

/// Route value that makes the fake answer 204 with no body.
class NoContent {
  const NoContent();
}

/// Route value that computes the answer from the request.
typedef RouteBuilder = Object? Function(RequestOptions options);

/// One request seen by [FakeApi].
class Recorded {
  Recorded(this.method, this.path, this.query, this.data);

  final String method;
  final String path;
  final Map<String, dynamic> query;
  final Object? data;

  String get key => '$method $path';
}

/// Fake HTTP adapter. Routes map "METHOD path" to a JSON body, an
/// [ApiFailure] or [NoContent]; unknown routes answer 404.
class FakeApi implements HttpClientAdapter {
  FakeApi(this.routes);

  final Map<String, Object?> routes;
  final List<Recorded> requests = [];

  /// Requests whose "METHOD path" equals [key].
  List<Recorded> where(String key) =>
      requests.where((r) => r.key == key).toList();

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(Recorded(options.method, options.path,
        Map<String, dynamic>.from(options.queryParameters), options.data));
    final found = routes['${options.method} ${options.path}'];
    final route = found is RouteBuilder ? found(options) : found;
    const json = {
      Headers.contentTypeHeader: ['application/json'],
    };
    if (route is ApiFailure) {
      final body = route.nested
          ? {
              'detail': {'code': route.code, 'message': route.detail},
            }
          : {'detail': route.detail, 'code': route.code, ...route.extra};
      return ResponseBody.fromString(jsonEncode(body), route.status,
          headers: json);
    }
    if (route is NoContent) return ResponseBody.fromString('', 204);
    if (route == null) return ResponseBody.fromString('{}', 404, headers: json);
    return ResponseBody.fromString(jsonEncode(route), 200, headers: json);
  }
}

/// Pumps [home] with a fake backend and a tall surface.
Future<void> pumpWithApi(WidgetTester tester, FakeApi api, Widget home,
    {List<Override> overrides = const [],
    Size size = const Size(1000, 2400),
    ThemeData? theme,
    ThemeMode themeMode = ThemeMode.light,
    ThemeData? darkTheme,
    GoRouter? router}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The default transformer decodes a large answer in another isolate, which
  // a widget test cannot wait for.
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = api
    ..transformer = SyncTransformer();
  await tester.pumpWidget(ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio), ...overrides],
    child: router == null
        ? MaterialApp(
            theme: theme,
            darkTheme: darkTheme,
            themeMode: themeMode,
            home: home,
          )
        : MaterialApp.router(
            theme: theme,
            darkTheme: darkTheme,
            themeMode: themeMode,
            routerConfig: router,
          ),
  ));
  await tester.pumpAndSettle();
}

/// A connection JSON object for `GET /connections`.
Map<String, Object?> connectionJson(String id, String kind, String name) => {
      'id': id,
      'kind': kind,
      'provider': 'test',
      'display_name': name,
      'status': 'ok',
      'last_sync_at': null,
      'last_sync_outcome': null,
    };

/// A task JSON object.
Map<String, Object?> taskJson(String id, String title,
        {String status = 'open'}) =>
    {
      'id': id,
      'connection_id': 'c1',
      'title': title,
      'description': null,
      'status': status,
      'due_at': null,
      'scheduled_start': null,
      'scheduled_end': null,
      'sync_state': 'synced',
    };

/// A period view JSON object (`GET /views/week|month|year`).
Map<String, Object?> periodJson(String type, String start, String end,
        {Map<String, Object?> goalTitles = const {},
        List<Object?> tasks = const [],
        List<Object?> entries = const []}) =>
    {
      'period_type': type,
      'start': start,
      'end': end,
      'goal_titles': goalTitles,
      'tasks': tasks,
      'entries': entries,
    };

/// One flag of the annual plan, such as `no_usable_theme`.
Map<String, Object?> flagJson(String code,
        {List<String>? actions, List<Object?> reasons = const []}) =>
    {
      'code': code,
      'actions': actions ??
          switch (code) {
            'no_key_result' => ['add_key_result'],
            'no_usable_theme' => ['link_theme', 'create_theme'],
            _ => ['update_value'],
          },
      if (code == 'no_usable_theme') 'reasons': reasons,
    };

/// A link of a key result to a theme.
Map<String, Object?> linkJson(String projectId, String name,
        {bool active = true,
        bool usable = true,
        String state = 'ok',
        String? label = 'theme'}) =>
    {
      'id': 'l-$projectId',
      'project_id': projectId,
      'name': name,
      'active': active,
      'usable': usable,
      'state': state,
      'label': label,
      'started_at': '2030-01-05T10:00:00Z',
      'ended_at': active ? null : '2030-02-05T10:00:00Z',
    };

/// A key result of `GET /annual/{year}`.
Map<String, Object?> keyResultJson(String id, String metric,
    {String goalId = 'g1',
    num start = 0,
    num target = 10,
    String kind = 'number',
    num? current,
    String? currentAt,
    String deadline = '2030-12-31',
    String source = 'manual',
    String status = 'active',
    List<Object?> flags = const [],
    List<Object?> links = const []}) {
  final now = current ?? start;
  final progress = target == start ? 0 : (now - start) / (target - start);
  return {
    'id': id,
    'goal_id': goalId,
    'metric': metric,
    'kind': kind,
    'start_value': start,
    'target': target,
    'deadline': deadline,
    'update_source': source,
    'status': status,
    'current_value': now,
    'current_at': currentAt,
    'progress': progress,
    'met': progress >= 1,
    'retired_at': status == 'retired' ? '2030-03-01T10:00:00Z' : null,
    'flags': flags,
    'links': links,
  };
}

/// A goal of `GET /annual/{year}`.
Map<String, Object?> annualGoalJson(String id, String title,
        {List<Object?> keyResults = const [],
        List<Object?>? flags,
        List<String> notes = const [],
        String status = 'active',
        bool legacyDone = false,
        String? criteria}) =>
    {
      'id': id,
      'title': title,
      'status': status,
      'legacy_done': legacyDone,
      'criteria_suggestion': criteria,
      'progress': 0,
      'flags': flags ??
          (keyResults.isEmpty && status == 'active'
              ? [flagJson('no_key_result')]
              : const []),
      'notes': notes,
      'updated_at': '2030-01-05T10:00:00Z',
      'key_results': keyResults,
    };

/// The plan of a year (`GET /annual/{year}`).
Map<String, Object?> annualPlanJson(
        {int year = 2030,
        String state = 'current',
        bool? editable,
        List<Object?> goals = const [],
        List<Object?> retiredGoals = const []}) =>
    {
      'year': year,
      'state': state,
      'editable': editable ?? state != 'past',
      'goals': goals,
      'retired_goals': retiredGoals,
      'theme_usage': const [],
    };

/// One theme of `GET /annual/themes`.
Map<String, Object?> themeJson(String id, String name,
        {String connectionId = 'c1',
        String connectionName = 'Vikunja',
        List<String> keyResultIds = const []}) =>
    {
      'project_id': id,
      'connection_id': connectionId,
      'connection_name': connectionName,
      'name': name,
      'key_result_ids': keyResultIds,
    };

/// The answer of `GET /annual/themes`.
Map<String, Object?> themesJson(
        {List<Object?> themes = const [],
        int unsorted = 0,
        List<Object?> connections = const [
          {'id': 'c1', 'name': 'Vikunja', 'can_create': true},
        ]}) =>
    {
      'themes': themes,
      'unsorted_count': unsorted,
      'task_connections': connections,
    };

/// One line of `GET /annual/{year}/history`.
Map<String, Object?> changeJson(String id, String kind,
        {String batch = 'b1',
        String? goalId,
        String? keyResultId,
        String? field,
        String? oldValue,
        String? newValue,
        String? reason,
        String source = 'user',
        String at = '2030-03-01T10:00:00Z',
        bool undone = false}) =>
    {
      'id': id,
      'kind': kind,
      'goal_id': goalId,
      'key_result_id': keyResultId,
      'field': field,
      'old_value': oldValue,
      'new_value': newValue,
      'reason': reason,
      'batch_id': batch,
      'source': source,
      'at': at,
      'undone': undone,
    };

/// The answer of `GET /annual/{year}/history`.
Map<String, Object?> historyJson(List<Object?> changes, {int year = 2030}) =>
    {'year': year, 'changes': changes};

/// One month of `GET /annual-review/{year}`.
Map<String, Object?> reviewMonthJson(String month,
        {String status = 'stored', int? version = 1, String? action}) =>
    {
      'month': month,
      'status': status,
      'version': version,
      'taken_at': status == 'stored' ? '2030-02-01T10:00:00Z' : null,
      'schema_version': status == 'stored' ? 1 : null,
      'action': action ??
          (status == 'missing' || status == 'open'
              ? 'open_monthly_review'
              : null),
    };

/// One month point of a review series.
Map<String, Object?> reviewSeriesJson(String month,
        {num? value, String status = 'stored', bool notStored = false}) =>
    {'month': month, 'status': status, 'value': value, 'not_stored': notStored};

/// One theme contribution of the review.
Map<String, Object?> reviewThemeJson(String name,
        {int shipped = 2,
        int outside = 0,
        int? targetSum = 2,
        double fraction = 0.1,
        String? hint}) =>
    {
      'project_id': 'p1',
      'connection_id': 'c1',
      'connection_name': 'Vikunja',
      'name': name,
      'label': 'theme',
      'orphaned': null,
      'ranges': [
        {
          'from': '2030-01-01',
          'to': null,
          'months': ['2030-01', '2030-02'],
        }
      ],
      'shipped': shipped,
      'shipped_outside_focus': outside,
      'target_sum': targetSum,
      'months_with_target': targetSum == null ? 0 : 2,
      'movement': {
        'from': 10,
        'to': 12,
        'fraction': fraction,
        'months': 2,
      },
      'hint': hint,
      'milestones': [
        {
          'milestone_id': 'm1',
          'name': 'Ship it',
          'done_on': '2030-02-08',
          'month': '2030-02',
          'in_focus': true,
        }
      ],
    };

/// One key result of the annual review.
Map<String, Object?> reviewKeyResultJson(String id, String metric,
        {num start = 0,
        num target = 10,
        String kind = 'number',
        String outcome = 'hit',
        num? last,
        String? lastMonth,
        String state = 'reached',
        List<Object?> series = const [],
        List<Object?> themes = const [],
        List<Object?> changes = const [],
        List<Object?> flags = const []}) =>
    {
      'id': id,
      'metric': metric,
      'kind': kind,
      'start_value': start,
      'target': target,
      'direction': 'up',
      'deadline': '2030-12-31',
      'update_source': 'manual',
      'status': 'active',
      'retired_at': null,
      'outcome': outcome,
      'last_value': last,
      'last_month': lastMonth,
      'last_at': last == null ? null : '2030-10-08T12:00:00Z',
      'deadline_line': {
        'state': state,
        'value': last,
        'month': lastMonth,
      },
      'series': series,
      'peak': null,
      'moved_after_snapshot': null,
      'current_value': last ?? start,
      'changes': changes,
      'flags': flags,
      'themes': themes,
    };

/// One goal of the annual review.
Map<String, Object?> reviewGoalJson(String id, String title,
        {List<Object?> keyResults = const [],
        String status = 'active',
        List<Object?> flags = const [],
        Map<String, Object?>? note}) =>
    {
      'id': id,
      'title': title,
      'status': status,
      'retired_at': null,
      'retired_reason': null,
      'counts': const {
        'hit': 0,
        'missed': 0,
        'no_value': 0,
        'retired': 0,
        'in_progress': 0,
      },
      'flags': flags,
      'note': note,
      'key_results': keyResults,
    };

/// The answer of `GET /annual-review/{year}`.
Map<String, Object?> annualReviewJson({
  int year = 2030,
  String state = 'past',
  int stored = 12,
  int expected = 12,
  List<Object?> goals = const [],
  List<Object?>? months,
  List<Object?>? missing,
  Map<String, Object?>? empty,
  List<Object?> splitMonths = const [],
  int monthsCovered = 12,
  int goalAligned = 120,
  int maintenance = 40,
  int offPlan = 30,
  int hidden = 12,
  Map<String, Object?>? yearNote,
  Map<String, Object?>? nextYear,
}) =>
    {
      'year': year,
      'state': state,
      'in_progress': state == 'current',
      'rules': {'hit': 'last_value_reaches_target', 'differ_threshold': 0.25},
      'months': months ??
          [
            for (var m = 1; m <= 12; m++)
              reviewMonthJson('$year-${m.toString().padLeft(2, '0')}'),
          ],
      'coverage': {
        'stored': stored,
        'expected': expected,
        'missing': missing ?? const [],
      },
      'empty': empty,
      'goals': goals,
      'milestones_shipped': {'count': 24, 'months_covered': stored},
      'split': {
        'months_covered': monthsCovered,
        'counts': {
          'goal_aligned': goalAligned,
          'maintenance': maintenance,
          'off_plan': offPlan,
        },
        'total': goalAligned + maintenance + offPlan,
        'hidden': hidden,
        'percentages': {
          'goal_aligned': 63,
          'maintenance': 21,
          'off_plan': 16,
        },
        'months': [
          for (var m = 1; m <= 12; m++)
            {
              'month': '$year-${m.toString().padLeft(2, '0')}',
              'status': m <= stored ? 'stored' : 'missing',
              'counts': {
                'goal_aligned': 10,
                'maintenance': 4,
                'off_plan': 3,
              },
              'hidden': 1,
              'percentages': {
                'goal_aligned': 59,
                'maintenance': 23,
                'off_plan': 18,
              },
              'not_stored': false,
            },
        ],
        'trend_note': null,
      },
      'drill_down': {
        'live': true,
        'route': '/statistics/tasks',
        'query': {'period': 'year', 'day': '$year-01-01'},
      },
      'next_year': nextYear ??
          {
            'year': year + 1,
            'from_year': year,
            'available': state != 'future',
            'has_plan': true,
            'unmet_key_results': 2,
            'links': 3,
          },
      'year_note': yearNote,
    };

/// The answer of `GET /annual/{year}/suggestions`.
Map<String, Object?> suggestionsJson(
        {int year = 2031,
        int fromYear = 2030,
        bool hasPlan = true,
        List<Object?> goals = const []}) =>
    {
      'year': year,
      'from_year': fromYear,
      'has_plan': hasPlan,
      'goals': goals,
    };

/// One suggested goal, with its unmet key results.
Map<String, Object?> suggestedGoalJson(String id, String title,
        {List<Object?> keyResults = const []}) =>
    {'goal_id': id, 'title': title, 'key_results': keyResults};

/// One suggested key result.
Map<String, Object?> suggestedKeyResultJson(String id, String metric,
        {num start = 0,
        num target = 10,
        String kind = 'number',
        String deadline = '2031-12-31',
        List<Object?> themes = const []}) =>
    {
      'key_result_id': id,
      'metric': metric,
      'kind': kind,
      'start_value': start,
      'target': target,
      'deadline': deadline,
      'update_source': 'manual',
      'themes': themes,
    };

/// One old goal row of `GET /goals/history`.
Map<String, Object?> legacyGoalJson(String id, String title,
        {String periodType = 'month',
        String periodStart = '2026-11-01',
        String? parentId,
        String status = 'active',
        int linkedTasks = 0}) =>
    {
      'id': id,
      'parent_id': parentId,
      'period_type': periodType,
      'period_start': periodStart,
      'title': title,
      'description': '',
      'criteria': '',
      'status': status,
      'linked_tasks': linkedTasks,
    };

/// One monthly focus entry. This helper mirrors `/api/v1/monthly/{month}`.
Map<String, Object?> monthlyEntryJson(
  String id,
  String projectId,
  String name, {
  String connectionId = 'c1',
  int? target,
  String countsFrom = '2030-03-01',
  String? leftOn,
  String status = 'in_focus',
  int done = 0,
  int earlierNotCounted = 0,
  String? marker,
  Map<String, Object?>? orphaned,
  String? labelChanged,
  int linkedKeyResults = 0,
  int lastMonthDone = 0,
}) =>
    {
      'id': id,
      'project_id': projectId,
      'connection_id': connectionId,
      'name': name,
      'target': target,
      'counts_from': countsFrom,
      'left_on': leftOn,
      'status': status,
      'done': done,
      'earlier_not_counted': earlierNotCounted,
      'marker': marker,
      'orphaned': orphaned,
      'label_changed': labelChanged,
      'linked_key_results': linkedKeyResults,
      'last_month_done': lastMonthDone,
    };

/// A key result in a monthly planning read model.
Map<String, Object?> monthlyKeyResultJson({
  String id = 'kr1',
  String goalId = 'g1',
  String goalTitle = 'Build a useful product',
  String metric = 'Active users',
  num startValue = 10,
  num currentValue = 18,
  String? currentAt = '2030-03-20T09:00:00Z',
  num target = 30,
  String deadline = '2030-12-31',
  String updateSource = 'manual',
  bool pastDeadline = false,
  List<String> themeIds = const ['p1'],
  List<Object?> flags = const [],
}) =>
    {
      'id': id,
      'goal_id': goalId,
      'goal_title': goalTitle,
      'metric': metric,
      'start_value': startValue,
      'current_value': currentValue,
      'current_at': currentAt,
      'target': target,
      'deadline': deadline,
      'update_source': updateSource,
      'past_deadline': pastDeadline,
      'theme_ids': themeIds,
      'flags': flags,
    };

/// The monthly plan read model for widget tests.
Map<String, Object?> monthlyJson({
  String month = '2030-03',
  String state = 'current',
  bool focusKnown = true,
  String? countNote,
  List<Object?> entries = const [],
  List<Object?> keyResults = const [],
  List<String> themesWithoutKeyResult = const [],
  Map<String, Object?> review = const {
    'stored': false,
    'current_version': null,
    'versions': 0,
  },
  bool earlierFormat = false,
}) =>
    {
      'month': month,
      'start': '$month-01',
      'end': _nextMonthKey(month),
      'state': state,
      'planning_year': int.parse(month.substring(0, 4)),
      'focus_known': focusKnown,
      'count_note': countNote,
      'entries': entries,
      'key_results': keyResults,
      'themes_without_key_result': themesWithoutKeyResult,
      'review': review,
      'earlier_format': earlierFormat,
    };

/// Picker option in a monthly theme list.
Map<String, Object?> monthlyThemeJson(
  String id,
  String name, {
  String connectionId = 'c1',
  String connectionName = 'Work',
  bool inFocus = false,
  bool leftThisMonth = false,
  int lastMonthDone = 0,
  List<String> keyResultIds = const [],
}) =>
    {
      'project_id': id,
      'connection_id': connectionId,
      'connection_name': connectionName,
      'name': name,
      'in_focus': inFocus,
      'left_this_month': leftThisMonth,
      'last_month_done': lastMonthDone,
      'key_result_ids': keyResultIds,
    };

/// `GET /monthly/{month}/themes` answer.
Map<String, Object?> monthlyPickerJson({
  List<Object?> themes = const [],
  int unsortedCount = 0,
  List<Object?> taskConnections = const [
    {'id': 'c1', 'name': 'Work', 'can_create': true},
  ],
}) =>
    {
      'themes': themes,
      'unsorted_count': unsortedCount,
      'task_connections': taskConnections,
    };

/// An editable carried-forward theme suggestion.
Map<String, Object?> monthlySuggestionJson(
  String projectId,
  String name, {
  int? target,
  String reason = 'carry',
  Map<String, Object?>? replaces,
}) =>
    {
      'project_id': projectId,
      'name': name,
      'target': target,
      'reason': reason,
      'replaces': replaces,
    };

/// `GET /monthly/{month}/suggestions` answer.
Map<String, Object?> monthlySuggestionsJson({
  String? fromMonth = '2030-02',
  List<Object?> suggestions = const [],
  List<Object?> skipped = const [],
}) =>
    {
      'from_month': fromMonth,
      'suggestions': suggestions,
      'skipped': skipped,
    };

/// A monthly key result inside a review snapshot.
Map<String, Object?> monthlyReviewKeyResultJson({
  String id = 'kr1',
  String goalId = 'g1',
  String goalTitle = 'Build a useful product',
  String metric = 'Active users',
  String updateSource = 'manual',
  num startValue = 10,
  num baseValue = 12,
  num latestValue = 18,
  String? latestAt = '2030-03-20T09:00:00Z',
  num change = 6,
  String status = 'updated',
  bool enteredInReview = false,
  bool afterMonthEnd = false,
  num target = 30,
  String deadline = '2030-12-31',
  bool pastDeadline = false,
  bool retired = false,
  List<String> themeIds = const ['p1'],
  bool shared = false,
  List<String> flags = const [],
}) =>
    {
      'key_result_id': id,
      'goal_id': goalId,
      'goal_title': goalTitle,
      'metric': metric,
      'update_source': updateSource,
      'start_value': startValue,
      'base_value': baseValue,
      'latest_value': latestValue,
      'latest_at': latestAt,
      'change': change,
      'status': status,
      'entered_in_review': enteredInReview,
      'after_month_end': afterMonthEnd,
      'target': target,
      'deadline': deadline,
      'past_deadline': pastDeadline,
      'retired': retired,
      'theme_ids': themeIds,
      'shared': shared,
      'flags': flags,
    };

/// One theme inside a monthly review snapshot.
Map<String, Object?> monthlyReviewThemeJson({
  String projectId = 'p1',
  String name = 'Open source',
  int? target = 3,
  String countsFrom = '2030-03-01',
  String? leftOn,
  String status = 'in_focus',
  Map<String, Object?>? orphaned,
  String? labelChanged,
  int done = 2,
  String marker = 'missed',
  List<Object?> milestones = const [],
  List<Object?> earlierNotCounted = const [],
  List<String> keyResultIds = const ['kr1'],
}) =>
    {
      'project_id': projectId,
      'name': name,
      'target': target,
      'counts_from': countsFrom,
      'left_on': leftOn,
      'status': status,
      'orphaned': orphaned,
      'label_changed': labelChanged,
      'done': done,
      'marker': marker,
      'milestones': milestones,
      'earlier_not_counted': earlierNotCounted,
      'key_result_ids': keyResultIds,
    };

/// A complete snapshot payload used by monthly review widget tests.
Map<String, Object?> monthlySnapshotJson({
  String month = '2030-03-01',
  List<Object?> themes = const [],
  List<Object?> changes = const [],
  List<Object?> outsideFocus = const [],
  Map<String, Object?> categories = const {
    'goal_aligned': 10,
    'maintenance': 4,
    'off_plan': 3,
    'hidden': 1,
  },
  List<Object?> keyResults = const [],
  List<Object?> decisions = const [],
}) =>
    {
      'schema_version': 1,
      'month': month,
      'month_end': _nextMonthKey(month.substring(0, 7)),
      'taken_at': '2030-04-02T08:00:00Z',
      'themes': themes,
      'changes': changes,
      'outside_focus': outsideFocus,
      'categories': categories,
      'key_results': keyResults,
      'decisions': decisions,
    };

/// The review response for a monthly draft or stored snapshot.
Map<String, Object?> monthlyReviewJson({
  String month = '2030-03',
  bool stored = false,
  int? version,
  int? currentVersion,
  String? takenAt,
  List<Object?> versions = const [],
  Map<String, Object?>? snapshot,
  String trendState = 'not_enough_history',
  num? share,
  List<Object?> previous = const [],
  String? categoriesNote,
}) =>
    {
      'month': month,
      'stored': stored,
      'draft': !stored,
      'version': version,
      'current_version': currentVersion,
      'taken_at': takenAt,
      'versions': versions,
      'snapshot': snapshot ??
          monthlySnapshotJson(
              themes: [monthlyReviewThemeJson()],
              keyResults: [monthlyReviewKeyResultJson()]),
      'trend': {
        'state': trendState,
        'previous': previous,
        'share': share,
        'note':
            trendState == 'not_enough_history' ? 'not enough history' : null,
      },
      'categories_note': categoriesNote,
    };

String _nextMonthKey(String value) {
  final year = int.parse(value.substring(0, 4));
  final month = int.parse(value.substring(5, 7));
  return month == 12
      ? '${year + 1}-01-01'
      : '$year-${(month + 1).toString().padLeft(2, '0')}-01';
}

/// A project of `GET /projects/classification`. [label] null means unsorted;
/// the proposal follows the default rule (top level: theme, else milestone).
Map<String, Object?> classifiedJson(String id, String name,
    {String? parent,
    String? label,
    String? parentTheme,
    Map<String, Object?>? orphaned,
    int tasks = 0,
    int subprojects = 0,
    bool eligible = true,
    bool inPlan = false,
    String? proposalLabel,
    String? proposalReason}) {
  final proposal = proposalLabel ?? (parent == null ? 'theme' : 'milestone');
  return {
    'id': id,
    'name': name,
    'parent_id': parent,
    'label': label,
    'proposal': {
      'label': proposal,
      'reason': proposalReason ?? (parent == null ? 'top_level' : 'nested'),
    },
    'effective_label': label ?? proposal,
    'parent_theme_id': parentTheme,
    'unsorted': label == null,
    'orphaned': orphaned,
    'eligible': eligible,
    'open_tasks': tasks,
    'subprojects': subprojects,
    'in_committed_plan': inPlan,
  };
}

/// Three whole percentages that add up to 100 (largest remainder), or all
/// zero when there is nothing. The server does this; the fake does the same,
/// so the tests can feed the client numbers that are right.
Map<String, int> fakePercentages(int g, int m, int o) {
  final total = g + m + o;
  if (total == 0) return {'goal_aligned': 0, 'maintenance': 0, 'off_plan': 0};
  final raw = [g, m, o].map((c) => c * 100 / total).toList();
  final floor = raw.map((v) => v.floor()).toList();
  var left = 100 - floor.fold(0, (a, b) => a + b);
  final order = [0, 1, 2]
    ..sort((a, b) => (raw[b] - floor[b]).compareTo(raw[a] - floor[a]));
  for (final i in order) {
    if (left <= 0) break;
    floor[i]++;
    left--;
  }
  return {
    'goal_aligned': floor[0],
    'maintenance': floor[1],
    'off_plan': floor[2],
  };
}

/// The three counts of a category summary.
Map<String, Object?> categoryCountsJson(int g, int m, int o) =>
    {'goal_aligned': g, 'maintenance': m, 'off_plan': o};

/// `GET /statistics`. [parts] default to one part that holds every count.
Map<String, Object?> statisticsJson({
  String period = 'week',
  String start = '2026-11-02',
  String end = '2026-11-09',
  int goalAligned = 0,
  int maintenance = 0,
  int offPlan = 0,
  int hidden = 0,
  int unsorted = 0,
  bool available = true,
  Map<String, Object?>? empty,
  String? lastSyncedAt = '2026-11-04T12:30:00Z',
  String? outcome = 'ok',
  Map<String, Object?>? progress,
  List<Object?>? parts,
}) {
  final pct = fakePercentages(goalAligned, maintenance, offPlan);
  return {
    'period': period,
    'start': start,
    'end': end,
    'available': available,
    'unavailable_reason': available ? null : 'weekly_commitment_unavailable',
    'counts': categoryCountsJson(goalAligned, maintenance, offPlan),
    'total': goalAligned + maintenance + offPlan,
    'percentages': pct,
    'hidden': hidden,
    'unsorted': unsorted,
    'part_kind': period == 'year' ? 'month' : 'day',
    'parts': parts ??
        [
          {
            'start': start,
            'end': end,
            'counts': categoryCountsJson(goalAligned, maintenance, offPlan),
            'hidden': hidden,
          },
        ],
    'empty': empty,
    'sync': {'last_synced_at': lastSyncedAt, 'outcome': outcome},
    'progress': progress,
  };
}

/// One completed task of `GET /statistics/tasks`.
Map<String, Object?> statTaskJson(
  String id,
  String title, {
  String category = 'off_plan',
  String completedDay = '2026-11-04',
  String? project = 'Home',
  String? projectId,
  bool unsorted = false,
  bool orphaned = false,
  String reason = 'theme',
  String? url,
}) =>
    {
      'id': id,
      'title': title,
      'completed_at': '${completedDay}T09:00:00Z',
      'completed_day': completedDay,
      'category': category,
      'reason': reason,
      'unsorted': unsorted,
      'project': {
        'id': project == null ? null : (projectId ?? 'p-$project'),
        'name': project ?? 'No project',
        'color': null,
        'orphaned': orphaned,
      },
      'url': url,
    };

/// The route `GET /statistics/tasks` over [all] (already in `newest` order).
/// It filters by `category` (all three work categories when omitted), sorts
/// by project name for `order=project`, and pages by `limit` and `cursor`.
/// The cursor is the offset as text. Every call is in `FakeApi.requests`.
RouteBuilder fakeStatisticsTasks(List<Map<String, Object?>> all,
    {String period = 'week',
    String start = '2026-11-02',
    String end = '2026-11-09'}) {
  return (options) {
    final q = options.queryParameters;
    final category = q['category'] as String?;
    final order = (q['order'] as String?) ?? 'newest';
    final limit = (q['limit'] as int?) ?? 50;
    final offset = int.tryParse('${q['cursor'] ?? 0}') ?? 0;
    var rows = [
      for (final t in all)
        if (category == null
            ? t['category'] != 'hidden'
            : t['category'] == category)
          t,
    ];
    if (order == 'project') {
      String name(Map<String, Object?> t) =>
          ((t['project']! as Map)['name'] as String).toLowerCase();
      rows = [...rows]..sort((a, b) => name(a).compareTo(name(b)));
    }
    final page = rows.skip(offset).take(limit).toList();
    final next = offset + limit < rows.length ? '${offset + limit}' : null;
    return {
      'period': period,
      'start': start,
      'end': end,
      'category': category,
      'order': order,
      'total': rows.length,
      'items': page,
      'next_cursor': next,
    };
  };
}

/// The committed-plan progress of a week for `GET /statistics` (the numbers
/// of the old client calculation, now sent by the server).
Map<String, Object?> weekProgressJson({
  int committed = 10,
  int done = 4,
  List<int> doneByDay = const [2, 1, 1, 0, 0, 0, 0],
  int doneBefore = 0,
  int doneUndated = 0,
  int doneAfter = 0,
  int daysElapsed = 3,
  int daysLeft = 5,
  double? cadence = 1.3333333333,
  double? neededPerDay = 1.2,
  bool onTrack = true,
  List<int?> remainingByDay = const [8, 7, 6, null, null, null, null],
  List<double> idealByDay = const [
    8.57,
    7.14,
    5.71,
    4.29,
    2.86,
    1.43,
    0.0,
  ],
  int scope = 10,
}) =>
    {
      'committed': committed,
      'done': done,
      'done_before': doneBefore,
      'done_undated': doneUndated,
      'done_after': doneAfter,
      'done_by_day': doneByDay,
      'days_elapsed': daysElapsed,
      'days_left': daysLeft,
      'cadence': cadence,
      'needed_per_day': neededPerDay,
      'on_track': onTrack,
      'remaining_by_day': remainingByDay,
      'ideal_by_day': idealByDay,
      'scope': scope,
    };
