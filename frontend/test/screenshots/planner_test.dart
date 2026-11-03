@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/planner/planner_screen.dart';
import 'package:tefteri/features/planner/time_grid.dart';

import 'fixtures.dart';
import 'screenshot_helper.dart';

String _iso(DateTime t) => t.toUtc().toIso8601String();

Map<String, Object?> _item(String type, String id, String title, DateTime start,
        {DateTime? end,
        bool allDay = false,
        String? status,
        String context = 'work'}) =>
    {
      'type': type,
      'id': id,
      'title': title,
      'start': _iso(start),
      'end': _iso(end ?? start.add(const Duration(hours: 1))),
      'all_day': allDay,
      'context': context,
      'effective_context': context,
      'connection_id': type == 'task' ? 'c1' : 'c2',
      if (status != null) 'status': status,
      'clipped_start': false,
    };

Map<String, Object?> _task(String id, String title, {DateTime? due}) => {
      ...taskJson(id, title),
      'due_at': due == null ? null : _iso(due),
      'scheduled_start':
          due == null ? null : _iso(due.subtract(const Duration(hours: 1))),
      'scheduled_end': due == null ? null : _iso(due),
    };

final _calendar = [
  _item('entry', 'e1', 'Team standup', DateTime(2026, 11, 2, 9),
      end: DateTime(2026, 11, 2, 9, 30)),
  _item('task', 't1', 'Write the release notes', DateTime(2026, 11, 2, 10)),
  _item('task', 't4', 'Update the road map', DateTime(2026, 11, 2, 14)),
  _item('entry', 'e3', 'Design review', DateTime(2026, 11, 3, 14)),
  _item('task', 't3', 'Prepare the demo', DateTime(2026, 11, 3, 14, 30),
      end: DateTime(2026, 11, 3, 15, 30)),
  _item('entry', 'e2', 'Dentist', DateTime(2026, 11, 4, 16), context: 'life'),
  _item('task', 't5', 'Pay the invoice', DateTime(2026, 11, 5),
      end: DateTime(2026, 11, 6), allDay: true),
  _item('task', 't6', 'Send the report', DateTime(2026, 11, 4, 11),
      status: 'done'),
];

final _open = [
  _task('t2', 'Buy a birthday present'),
  _task('t4', 'Update the road map', due: DateTime(2026, 11, 2, 15)),
  _task('t7', 'Book the train tickets'),
];

const _counts = {
  'today': 2,
  'tomorrow': 1,
  'week': 5,
  'all': 7,
  'none': 3,
  'overdue': 1,
};

FakeApi _api([Map<String, Object?> extra = const {}]) => FakeApi({
      'GET /calendar': _calendar,
      'GET /tasks': (o) => switch (o.queryParameters['q']) {
            'road' => [_open[1]],
            _ when o.queryParameters['due'] == 'overdue' => [
                _task('t8', 'File the tax form',
                    due: DateTime(2026, 10, 30, 9)),
              ],
            _ => _open,
          },
      'GET /tasks/counts': _counts,
      ...extra,
    });

/// A fixed time, so the red line is in the same place in every image.
DateTime _now() => DateTime(2026, 11, 4, 10, 30);

final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

void main() {
  testWidgets('planner: tasks left, calendar right', (tester) async {
    await pumpScreen(
        tester, _api(), PlannerScreen(initialDate: day, clock: _now));
    await saveScreenshot('planner-split');
  });

  testWidgets('planner: filter overdue', (tester) async {
    await pumpScreen(
        tester, _api(), PlannerScreen(initialDate: day, clock: _now));
    await tester.tap(find.byKey(const Key('filter-overdue')));
    await tester.pumpAndSettle();
    await saveScreenshot('planner-filter-overdue');
  });

  testWidgets('planner: search', (tester) async {
    await pumpScreen(
        tester, _api(), PlannerScreen(initialDate: day, clock: _now));
    await tester.enterText(find.byKey(const Key('task-search')), 'road');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await saveScreenshot('planner-search');
  });

  testWidgets('planner: dragging a task over the calendar', (tester) async {
    await pumpScreen(
        tester,
        _api({'PUT /tasks/t2/schedule': _task('t2', 'Buy a birthday present')}),
        PlannerScreen(initialDate: day, clock: _now));
    final from = tester.getCenter(find.byKey(const Key('task-t2')));
    final column =
        tester.getTopLeft(find.byKey(const Key('day-column-2026-11-05')));
    final to = column + Offset(30, minutesToOffset(13 * 60 + 40));
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await saveScreenshot('planner-drag');
    await gesture.up();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }, variant: _linux);

  testWidgets('planner: the save failed', (tester) async {
    await pumpScreen(
        tester,
        _api({
          'PUT /tasks/t2/schedule': const ApiFailure(
              502,
              'Home tasks cannot be reached. Nothing was changed.',
              'backend_unavailable'),
        }),
        PlannerScreen(initialDate: day, clock: _now));
    final from = tester.getCenter(find.byKey(const Key('task-t2')));
    final column =
        tester.getTopLeft(find.byKey(const Key('day-column-2026-11-05')));
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.moveTo(column + Offset(30, minutesToOffset(13 * 60 + 40)));
    await tester.pump();
    await gesture.up();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    await saveScreenshot('planner-save-failed');
  }, variant: _linux);

  testWidgets('planner: small screen, tasks tab', (tester) async {
    await pumpScreen(
        tester, _api(), PlannerScreen(initialDate: day, clock: _now),
        size: const Size(420, 760));
    await saveScreenshot('planner-narrow-tasks');
  });

  testWidgets('planner: small screen, choose a time', (tester) async {
    await pumpScreen(
        tester, _api(), PlannerScreen(initialDate: day, clock: _now),
        size: const Size(420, 760));
    await tester.tap(find.byKey(const Key('schedule-task-t2')));
    await tester.pumpAndSettle();
    await saveScreenshot('planner-narrow-schedule');
  });

  testWidgets('planner: task details pop-up', (tester) async {
    await pumpScreen(
        tester,
        _api({
          'GET /tasks/t4': {
            ..._task('t4', 'Update the road map',
                due: DateTime(2026, 11, 2, 15)),
            'description':
                'Add the Q1 goals.\nAsk the team for feedback before Friday.',
            'effective_context': 'work',
          },
        }),
        PlannerScreen(initialDate: day, clock: _now));
    await tester.tap(find.byKey(const Key('task-t4')));
    await tester.pumpAndSettle();
    await saveScreenshot('planner-task-details');
  });
}
