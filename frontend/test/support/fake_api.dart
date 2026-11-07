import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/api_client.dart';

/// Route value that makes the fake answer with an API error.
class ApiFailure {
  const ApiFailure(this.status, this.detail, this.code);

  final int status;
  final String detail;
  final String code;
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
      return ResponseBody.fromString(
          jsonEncode({'detail': route.detail, 'code': route.code}),
          route.status,
          headers: json);
    }
    if (route is NoContent) return ResponseBody.fromString('', 204);
    if (route == null) return ResponseBody.fromString('{}', 404, headers: json);
    return ResponseBody.fromString(jsonEncode(route), 200, headers: json);
  }
}

/// Pumps [home] with a fake backend and a tall surface.
Future<void> pumpWithApi(WidgetTester tester, FakeApi api, Widget home,
    {List<Override> overrides = const []}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = api;
  await tester.pumpWidget(ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio), ...overrides],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

/// A connection JSON object for `GET /connections`.
Map<String, Object?> connectionJson(String id, String kind, String name) => {
      'id': id,
      'kind': kind,
      'provider': 'test',
      'display_name': name,
      'default_context': null,
      'status': 'ok',
      'last_sync_at': null,
      'last_sync_outcome': null,
    };

/// A task JSON object.
Map<String, Object?> taskJson(String id, String title,
        {String status = 'open', String? context = 'work'}) =>
    {
      'id': id,
      'connection_id': 'c1',
      'title': title,
      'description': null,
      'status': status,
      'due_at': null,
      'scheduled_start': null,
      'scheduled_end': null,
      'context': context,
      'effective_context': context ?? 'work',
      'sync_state': 'synced',
    };

/// A goal JSON object.
Map<String, Object?> goalJson(String id, String title,
        {String periodType = 'year',
        String periodStart = '2026-01-01',
        String? parentId,
        String status = 'active',
        double progress = 0}) =>
    {
      'id': id,
      'parent_id': parentId,
      'period_type': periodType,
      'period_start': periodStart,
      'title': title,
      'description': '',
      'context': 'work',
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
