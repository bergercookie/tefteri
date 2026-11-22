import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/daily/daily_screen.dart';

import '../../support/fake_api.dart';

const _path = 'GET /views/day/2026-11-01';

Map<String, Object?> _day() => {
      'date': '2026-11-01',
      'entries': [
        {
          'id': 'e1',
          'connection_id': 'c2',
          'title': 'Team sync',
          'start': '2026-11-01T09:00:00Z',
          'end': '2026-11-01T09:30:00Z',
          'all_day': false,
          'location': 'Room 4',
          'sync_state': 'synced',
        },
      ],
      'tasks': [
        taskJson('t1', 'Write report'),
        taskJson('t2', 'Buy milk'),
        taskJson('t3', 'Old task', status: 'done'),
      ],
      'note': {
        'id': 'n1',
        'connection_id': null,
        'kind': 'daily',
        'title': 'Daily',
        'body': 'Plan: focus.',
        'note_date': '2026-11-01',
        'sync_state': 'synced',
      },
    };

FakeApi _api([Map<String, Object?> extra = const {}]) => FakeApi({
      _path: _day(),
      'GET /connections': [
        connectionJson('c1', 'tasks', 'Home tasks'),
        connectionJson('c2', 'calendar', 'Work calendar'),
      ],
      ...extra,
    });

Future<void> _pump(WidgetTester tester, FakeApi api) =>
    pumpWithApi(tester, api, DailyScreen(initialDate: DateTime(2026, 11, 1)));

void main() {
  testWidgets('shows entries, tasks and the daily note', (tester) async {
    final api = _api();
    await _pump(tester, api);
    expect(find.text('Team sync'), findsOneWidget);
    expect(find.textContaining('Room 4'), findsOneWidget);
    expect(find.text('Write report'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Plan: focus.'), findsOneWidget);
  });

  testWidgets('complete calls the API and reloads', (tester) async {
    final api = _api({'POST /tasks/t1/complete': taskJson('t1', 'x')});
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('complete-t1')));
    await tester.pumpAndSettle(); // sends the write
    await tester.pumpAndSettle(); // then reloads the day
    expect(api.where('POST /tasks/t1/complete'), hasLength(1));
    expect(api.where(_path), hasLength(2));
  });

  testWidgets('a done task is marked not done by its check mark',
      (tester) async {
    final api = _api({'POST /tasks/t3/reopen': taskJson('t3', 'Old task')});
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('complete-t3')));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(api.where('POST /tasks/t3/complete'), isEmpty);
    expect(api.where('POST /tasks/t3/reopen'), hasLength(1));
    expect(api.where(_path), hasLength(2));
  });

  testWidgets('the check mark is a target that a finger can hit',
      (tester) async {
    await _pump(tester, _api());
    final size = tester.getSize(find.byKey(const Key('complete-t1')));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets(
      'a tap on a task opens it, and a change of the title is saved and the day is loaded again',
      (tester) async {
    final api = _api({
      'GET /tasks/t1': taskJson('t1', 'Write report'),
      'PATCH /tasks/t1': taskJson('t1', 'Write the report'),
      'POST /tasks/t1/schedule': taskJson('t1', 'Write the report'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('task-t1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-details')), findsOneWidget);
    // Nothing was completed by opening it.
    expect(api.where('POST /tasks/t1/complete'), isEmpty);
    await tester.enterText(
        find.byKey(const Key('task-edit-title')), 'Write the report');
    await tester.pump();
    await tester.tap(find.byKey(const Key('task-save')));
    await tester.pumpAndSettle();
    expect(api.where('PATCH /tasks/t1').single.data,
        {'title': 'Write the report', 'description': ''});
    // The pop-up is closed and the day is loaded again.
    expect(find.byKey(const Key('task-details')), findsNothing);
    expect(api.where(_path), hasLength(2));
  });

  testWidgets('the due date of a task can be removed in its pop-up',
      (tester) async {
    final dated = {
      ...taskJson('t1', 'Write report'),
      'due_at': DateTime(2026, 11, 1).toUtc().toIso8601String(),
    };
    final day = _day();
    (day['tasks']! as List<Object?>)[0] = dated;
    final api = FakeApi({
      _path: day,
      'GET /connections': [connectionJson('c1', 'tasks', 'Home tasks')],
      'GET /tasks/t1': dated,
      'DELETE /tasks/t1/schedule': taskJson('t1', 'Write report'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('task-t1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-edit-date')), findsOneWidget);
    expect(find.byKey(const Key('task-edit-time')), findsOneWidget);
    await tester.tap(find.byKey(const Key('task-edit-date-clear')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('task-save')));
    await tester.pumpAndSettle();
    expect(api.where('DELETE /tasks/t1/schedule'), hasLength(1));
    // The day is loaded again, so the task can leave the list.
    expect(api.where(_path), hasLength(2));
  });

  testWidgets('a task shows its due time, or all day', (tester) async {
    final day = _day();
    (day['tasks']! as List<Object?>)
      ..[0] = {
        ...taskJson('t1', 'Write report'),
        'due_at': DateTime(2026, 11, 1, 14, 30).toUtc().toIso8601String(),
        'scheduled_start':
            DateTime(2026, 11, 1, 14, 30).toUtc().toIso8601String(),
        'scheduled_end':
            DateTime(2026, 11, 1, 15, 30).toUtc().toIso8601String(),
        'project': 'Home',
      }
      ..[1] = {
        ...taskJson('t2', 'Buy milk'),
        'due_at': DateTime(2026, 11, 1).toUtc().toIso8601String(),
        'all_day': true,
      };
    await _pump(
        tester,
        FakeApi({
          _path: day,
          'GET /connections': [connectionJson('c1', 'tasks', 'Home tasks')],
        }));
    final timed = tester.widget<Text>(find.byKey(const Key('task-due-t1')));
    expect(timed.data, 'Due 14:30 \u00b7 Home');
    final allDay = tester.widget<Text>(find.byKey(const Key('task-due-t2')));
    expect(allDay.data, 'All day');
  });

  testWidgets('delete calls the API', (tester) async {
    final api = _api({'DELETE /tasks/t1': const NoContent()});
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('delete-t1')));
    await tester.pumpAndSettle();
    expect(api.where('DELETE /tasks/t1'), hasLength(1));
  });

  testWidgets('quick add sends the title to the task connection',
      (tester) async {
    final api = _api({'POST /tasks': taskJson('t9', 'Call Sam')});
    await _pump(tester, api);
    await tester.enterText(
        find.byKey(const Key('quick-add-field')), 'Call Sam');
    await tester.tap(find.byKey(const Key('quick-add-button')));
    await tester.pumpAndSettle();
    final post = api.where('POST /tasks').single;
    expect(post.data, {'connection_id': 'c1', 'title': 'Call Sam'});
    expect(find.text('Call Sam'), findsNothing); // field cleared
  });

  testWidgets('daily note append sends the text', (tester) async {
    final api = _api({'POST /notes/daily/2026-11-01/append': {}});
    await _pump(tester, api);
    await tester.enterText(find.byKey(const Key('note-field')), 'More');
    await tester.tap(find.byKey(const Key('note-append-button')));
    await tester.pumpAndSettle();
    expect(api.where('POST /notes/daily/2026-11-01/append').single.data,
        {'text': 'More'});
  });

  testWidgets('unreachable app shows the detail and does not retry',
      (tester) async {
    final api = _api({
      'POST /tasks/t1/complete': const ApiFailure(
          502,
          'Home tasks is not reachable. Try again later.',
          'backend_unavailable'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('complete-t1')));
    await tester.pumpAndSettle();
    expect(find.text('Home tasks is not reachable. Try again later.'),
        findsOneWidget);
    expect(api.where('POST /tasks/t1/complete'), hasLength(1));
    expect(api.where(_path), hasLength(1)); // no reload, no queue
  });

  testWidgets('unsupported action shows the detail', (tester) async {
    final api = _api({
      'DELETE /tasks/t1': const ApiFailure(
          409, 'Delete is not available for this app.', 'not_supported'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('delete-t1')));
    await tester.pumpAndSettle();
    expect(find.text('Delete is not available for this app.'), findsOneWidget);
  });

  testWidgets('expired credentials show the detail', (tester) async {
    final api = _api({
      'POST /tasks': const ApiFailure(
          502, 'Home tasks: your login expired.', 'auth_expired'),
    });
    await _pump(tester, api);
    await tester.enterText(find.byKey(const Key('quick-add-field')), 'X');
    await tester.tap(find.byKey(const Key('quick-add-button')));
    await tester.pumpAndSettle();
    expect(find.text('Home tasks: your login expired.'), findsOneWidget);
  });
}
