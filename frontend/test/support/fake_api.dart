import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    ThemeData? darkTheme}) async {
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
    child: MaterialApp(
        theme: theme, darkTheme: darkTheme, themeMode: themeMode, home: home),
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

/// A goal JSON object.
Map<String, Object?> goalJson(String id, String title,
        {String periodType = 'year',
        String periodStart = '2026-01-01',
        String? parentId,
        String status = 'active',
        String description = '',
        String criteria = '',
        double progress = 0}) =>
    {
      'id': id,
      'parent_id': parentId,
      'period_type': periodType,
      'period_start': periodStart,
      'title': title,
      'description': description,
      'criteria': criteria,
      'status': status,
      'progress': progress,
    };

/// A period view JSON object (`GET /views/week|month|year`).
Map<String, Object?> periodJson(String type, String start, String end,
        {List<Object?> goals = const [],
        List<Object?> tasks = const [],
        List<Object?> entries = const []}) =>
    {
      'period_type': type,
      'start': start,
      'end': end,
      'goals': goals,
      'tasks': tasks,
      'entries': entries,
    };

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
