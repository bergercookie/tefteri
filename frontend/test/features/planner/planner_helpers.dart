import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/planner/planner_screen.dart';
import 'package:tefteri/features/planner/time_grid.dart';

import '../../support/fake_api.dart';

/// 2026-11-04 is a Wednesday. Its week starts on Monday 2026-11-02.
final wednesday = DateTime(2026, 11, 4);

String _iso(DateTime local) => local.toUtc().toIso8601String();

/// A calendar item JSON object. Times are local.
Map<String, Object?> calItem(String type, String id, String title,
        {required DateTime start,
        DateTime? end,
        bool allDay = false,
        String? status,
        String? project,
        String? color,
        bool readOnly = false,
        bool clipped = false,
        String connectionId = 'c1',
        String? containerId}) =>
    {
      'type': type,
      'id': id,
      'title': title,
      'start': _iso(start),
      'end': _iso(end ?? start.add(const Duration(hours: 1))),
      'all_day': allDay,
      'connection_id': connectionId,
      if (containerId != null) 'container_id': containerId,
      if (status != null) 'status': status,
      'clipped_start': clipped,
      if (project != null) 'project': project,
      if (color != null) 'color': color,
      if (readOnly) 'read_only': true,
    };

/// A task JSON object with a due date. Local time; `null` means no due date.
Map<String, Object?> dueTask(String id, String title, {DateTime? due}) => {
      ...taskJson(id, title),
      'due_at': due == null ? null : _iso(due),
      'scheduled_start':
          due == null ? null : _iso(due.subtract(const Duration(hours: 1))),
      'scheduled_end': due == null ? null : _iso(due),
    };

/// A fake backend for the planner. [tasksFor] answers `GET /tasks`.
FakeApi plannerApi({
  List<Object?> calendar = const [],
  List<Object?> Function(RequestOptionsLike q)? tasksFor,
  Map<String, int> counts = const {
    'today': 2,
    'tomorrow': 0,
    'week': 3,
    'all': 5,
    'none': 1,
    'overdue': 1,
  },
  Map<String, Object?> extra = const {},
}) =>
    FakeApi({
      'GET /calendar': calendar,
      'GET /tasks': (o) => (tasksFor ??
          (_) => [
                dueTask('t1', 'Write report'),
                dueTask('t2', 'Plan trip'),
              ])(RequestOptionsLike(o.queryParameters)),
      'GET /tasks/counts': counts,
      ...extra,
    });

/// The query of a request, as the fake sees it.
class RequestOptionsLike {
  RequestOptionsLike(this.query);

  final Map<String, dynamic> query;
}

Future<void> pumpPlanner(WidgetTester tester, FakeApi api,
        {List<Override> overrides = const [],
        Size size = const Size(1000, 2400)}) =>
    pumpWithApi(tester, api, PlannerScreen(initialDate: wednesday),
        overrides: overrides, size: size);

/// Top-left of a day's column in the time grid (global).
Offset columnTopLeft(WidgetTester tester, DateTime day) {
  final key = Key(
      'day-column-${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}');
  return tester.getTopLeft(find.byKey(key));
}

/// A global point inside [day]'s column at [hour]:[minute].
Offset slotPoint(WidgetTester tester, DateTime day, int hour, int minute) {
  final top = columnTopLeft(tester, day);
  return top + Offset(24, minutesToOffset(hour * 60 + minute));
}

/// Drags the widget found by [from] to the global point [to] and drops it.
Future<void> dragTo(WidgetTester tester, Finder from, Offset to) async {
  final gesture = await tester.startGesture(tester.getCenter(from));
  await gesture.moveBy(const Offset(24, 0));
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  await gesture.up();
  await settle(tester);
}

/// Lets the save, the reload that follows it and the rebuild finish. A plain
/// `pumpAndSettle` can stop while a fake network call is still in flight.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}
