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
          'context': 'work',
          'effective_context': 'work',
          'sync_state': 'synced',
        },
      ],
      'tasks': [
        taskJson('t1', 'Write report'),
        taskJson('t2', 'Buy milk', context: null),
        taskJson('t3', 'Old task', status: 'done'),
      ],
      'note': {
        'id': 'n1',
        'connection_id': null,
        'kind': 'daily',
        'title': 'Daily',
        'body': 'Plan: focus.',
        'note_date': '2026-11-01',
        'context': null,
        'effective_context': 'life',
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
    // Only the task with no context gets the marker.
    expect(find.byKey(const Key('unclassified-marker')), findsOneWidget);
    expect(api.where(_path).first.query['context'], 'all');
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

  testWidgets('a done task cannot be completed again', (tester) async {
    final api = _api();
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('complete-t3')));
    await tester.pumpAndSettle();
    expect(api.where('POST /tasks/t3/complete'), isEmpty);
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
