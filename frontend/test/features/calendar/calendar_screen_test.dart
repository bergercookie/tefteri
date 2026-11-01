import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/calendar/calendar_screen.dart';

import '../../support/fake_api.dart';

// 2026-11-04 is a Wednesday; its week starts on Monday 2026-11-02.
final _day = DateTime(2026, 11, 4);

Map<String, Object?> _item(String type, String id, String title, String start,
        {String? context = 'work'}) =>
    {
      'type': type,
      'id': id,
      'title': title,
      'start': start,
      'end': null,
      'all_day': false,
      'context': context,
      'effective_context': context ?? 'work',
      'connection_id': 'c1',
    };

FakeApi _api([Map<String, Object?> extra = const {}]) => FakeApi({
      'GET /calendar': [
        _item('entry', 'e1', 'Standup',
            DateTime(2026, 11, 3, 10).toUtc().toIso8601String()),
        _item('task', 't1', 'Scheduled job',
            DateTime(2026, 11, 3, 14).toUtc().toIso8601String(),
            context: null),
      ],
      'GET /tasks': [taskJson('t2', 'Plan trip')],
      ...extra,
    });

Future<void> _pump(WidgetTester tester, FakeApi api) =>
    pumpWithApi(tester, api, CalendarScreen(initialDate: _day));

void main() {
  testWidgets('shows tasks and entries with distinct styling', (tester) async {
    final api = _api();
    await _pump(tester, api);
    expect(find.byKey(const Key('entry-item-e1')), findsOneWidget);
    expect(find.byKey(const Key('task-item-t1')), findsOneWidget);
    expect(find.textContaining('Event -'), findsOneWidget);
    expect(find.textContaining('Task -'), findsOneWidget);
    final entry = tester.widget<Card>(find.byKey(const Key('entry-item-e1')));
    final task = tester.widget<Card>(find.byKey(const Key('task-item-t1')));
    expect(entry.color, isNot(task.color));
    expect(find.byKey(const Key('unclassified-marker')), findsOneWidget);
    expect(find.byKey(const Key('unscheduled-t2')), findsOneWidget);
    final q = api.where('GET /calendar').first.query;
    expect(q['context'], 'all');
    expect(q['from'], DateTime(2026, 11, 2).toUtc().toIso8601String());
    expect(q['to'], DateTime(2026, 11, 9).toUtc().toIso8601String());
  });

  testWidgets('choose a time schedules the task', (tester) async {
    final api = _api({'PUT /tasks/t2/schedule': taskJson('t2', 'Plan trip')});
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('unscheduled-t2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-confirm')));
    await tester.pumpAndSettle();
    final put = api.where('PUT /tasks/t2/schedule').single;
    expect((put.data! as Map)['start'],
        DateTime(2026, 11, 2, 9).toUtc().toIso8601String());
    // Scheduling never creates an entry.
    expect(api.where('POST /calendar/entries'), isEmpty);
  });

  testWidgets('dropping a task on a day schedules it', (tester) async {
    final api = _api({'PUT /tasks/t2/schedule': taskJson('t2', 'Plan trip')});
    await _pump(tester, api);
    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('unscheduled-t2'))));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture
        .moveTo(tester.getCenter(find.byKey(const Key('day-2026-11-05'))));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    final put = api.where('PUT /tasks/t2/schedule').single;
    expect((put.data! as Map)['start'],
        DateTime(2026, 11, 5, 9).toUtc().toIso8601String());
  });

  testWidgets('unschedule calls DELETE on the schedule', (tester) async {
    final api = _api({'DELETE /tasks/t1/schedule': taskJson('t1', 'x')});
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('task-menu-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unschedule'));
    await tester.pumpAndSettle();
    expect(api.where('DELETE /tasks/t1/schedule'), hasLength(1));
  });

  testWidgets('unsupported scheduling shows the detail', (tester) async {
    final api = _api({
      'PUT /tasks/t2/schedule': const ApiFailure(
          409, 'Scheduling is not available for this app.', 'not_supported'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('unscheduled-t2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-confirm')));
    await tester.pumpAndSettle();
    expect(
        find.text('Scheduling is not available for this app.'), findsOneWidget);
    expect(api.where('PUT /tasks/t2/schedule'), hasLength(1));
  });

  testWidgets('unreachable app shows the detail', (tester) async {
    final api = _api({
      'PUT /tasks/t2/schedule': const ApiFailure(
          502, 'Home tasks is not reachable.', 'backend_unavailable'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('unscheduled-t2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Home tasks is not reachable.'), findsOneWidget);
  });
}
