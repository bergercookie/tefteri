import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/api_client.dart';

/// Route value that makes the fake answer with an API error.
class ApiFailure {
  const ApiFailure(this.status, this.detail, this.code) : nested = false;

  /// The error shape of the classification routes:
  /// `{"detail": {"code": ..., "message": ...}}`.
  const ApiFailure.contract(this.status, this.code, String message)
      : detail = message,
        nested = true;

  final int status;
  final String detail;
  final String code;
  final bool nested;
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
          : {'detail': route.detail, 'code': route.code};
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
    bool inPlan = false}) {
  final proposal = parent == null ? 'theme' : 'milestone';
  return {
    'id': id,
    'name': name,
    'parent_id': parent,
    'label': label,
    'proposal': {
      'label': proposal,
      'reason': parent == null ? 'top_level' : 'nested',
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
