import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/week/week_screen.dart';

import '../../support/fake_api.dart';

// 2026-11-04 is a Wednesday; its week starts on Monday 2026-11-02.
final _day = DateTime(2026, 11, 4);
const _path = 'GET /views/week/2026-11-02';

Map<String, Object?> _week() => periodJson(
      'week',
      '2026-11-02',
      '2026-11-09',
      goals: [
        goalJson('g1', 'Ship beta',
            periodType: 'week', periodStart: '2026-11-02', progress: 0.5),
      ],
      tasks: [
        {...taskJson('t1', 'Write plan'), 'goal_id': 'g1'},
        {
          ...taskJson('t2', 'Call Sam', context: null),
          'scheduled_start': '2026-11-03T09:00:00Z',
        },
      ],
      entries: [
        {
          'id': 'e1',
          'connection_id': 'c2',
          'title': 'Standup',
          'start': DateTime(2026, 11, 3, 10).toUtc().toIso8601String(),
          'end': null,
          'all_day': false,
          'context': 'work',
          'sync_state': 'synced',
        },
      ],
    );

FakeApi _api([Map<String, Object?> extra = const {}]) =>
    FakeApi({_path: _week(), ...extra});

Future<void> _pump(WidgetTester tester, FakeApi api) =>
    pumpWithApi(tester, api, WeekScreen(initialDate: _day));

void main() {
  testWidgets('shows goals with progress, events and tasks', (tester) async {
    final api = _api();
    await _pump(tester, api);
    expect(find.text('Week of 2026-11-02'), findsOneWidget);
    expect(find.text('Ship beta'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('goal-progress-g1')));
    expect(bar.value, 0.5);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Standup'), findsOneWidget);
    expect(find.text('Write plan'), findsOneWidget);
    expect(find.textContaining('Goal: Ship beta'), findsOneWidget);
    expect(find.textContaining('Not scheduled'), findsOneWidget);
    expect(find.byKey(const Key('unclassified-marker')), findsOneWidget);
    expect(api.where(_path).first.query['context'], 'all');
  });

  testWidgets('context filter reloads with the new value', (tester) async {
    final api = _api();
    await _pump(tester, api);
    await tester.tap(find.text('work'));
    await tester.pumpAndSettle();
    expect(api.where(_path).last.query['context'], 'work');
  });

  testWidgets('next week loads the following Monday', (tester) async {
    final api = _api({
      'GET /views/week/2026-11-09':
          periodJson('week', '2026-11-09', '2026-11-16'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('next-period')));
    await tester.pumpAndSettle();
    expect(api.where('GET /views/week/2026-11-09'), hasLength(1));
    expect(find.text('Week of 2026-11-09'), findsOneWidget);
    expect(find.byKey(const Key('no-goals')), findsOneWidget);
  });

  testWidgets('schedule puts the task on the chosen day and hour',
      (tester) async {
    final api = _api({'PUT /tasks/t1/schedule': taskJson('t1', 'x')});
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('task-menu-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-day')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-11-04').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-confirm')));
    await tester.pumpAndSettle();
    final put = api.where('PUT /tasks/t1/schedule').single;
    expect((put.data! as Map)['start'],
        DateTime(2026, 11, 4, 9).toUtc().toIso8601String());
    expect(api.where('POST /calendar/entries'), isEmpty);
    expect(api.where(_path), hasLength(2));
  });

  testWidgets('unschedule calls DELETE on the schedule', (tester) async {
    final api = _api({'DELETE /tasks/t2/schedule': taskJson('t2', 'x')});
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('task-menu-t2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unschedule'));
    await tester.pumpAndSettle();
    expect(api.where('DELETE /tasks/t2/schedule'), hasLength(1));
  });

  testWidgets('a task can be linked to a goal', (tester) async {
    final api = _api({'PATCH /tasks/t2': taskJson('t2', 'x')});
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('task-menu-t2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link to goal'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('link-goal-g1')));
    await tester.pumpAndSettle();
    expect((api.where('PATCH /tasks/t2').single.data! as Map)['goal_id'], 'g1');
  });

  testWidgets('a scheduling failure shows the server message', (tester) async {
    final api = _api({
      'PUT /tasks/t1/schedule': const ApiFailure(
          409, 'Scheduling is not available for this app.', 'not_supported'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('task-menu-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-confirm')));
    await tester.pumpAndSettle();
    expect(
        find.text('Scheduling is not available for this app.'), findsOneWidget);
  });

  testWidgets('a load failure offers a retry', (tester) async {
    final api = FakeApi({
      _path:
          const ApiFailure(502, 'The server is down.', 'backend_unavailable'),
    });
    await _pump(tester, api);
    expect(find.text('The server is down.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reload-button')));
    await tester.pumpAndSettle();
    expect(api.where(_path), hasLength(2));
  });
}
