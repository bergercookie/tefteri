import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'planner_helpers.dart';

const _invitees = ['sam@example.com', 'kim@example.org'];

FakeApi _api({List<String> invitees = _invitees}) => plannerApi(extra: {
      'GET /connections': [connectionJson('c1', 'calendar', 'Work account')],
      'GET /connections/c1/containers': [
        {'id': 'k1', 'name': 'Home', 'enabled': true, 'read_only': false},
      ],
      'GET /me/settings': {
        'random_time_on_date_drop': false,
        'default_event_container_id': null,
        'event_invitees': invitees,
      },
      'POST /calendar/entries': {
        'id': 'new',
        'connection_id': 'c1',
        'title': 'x',
        'start': '2026-11-04T14:00:00Z',
        'end': '2026-11-04T15:00:00Z',
        'all_day': false,
        'sync_state': 'synced',
      },
    });

Future<void> _openFromButton(WidgetTester tester, FakeApi api) async {
  await pumpPlanner(tester, api);
  await tester.tap(find.byKey(const Key('new-event-button')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('new-event-dialog')), findsOneWidget);
}

/// The name of the typed field that has the keyboard focus, or null.
String? _focusedField(WidgetTester tester) {
  for (final name in ['title', 'date', 'start', 'length', 'location']) {
    final editable = find.descendant(
        of: find.byKey(Key('new-event-$name')),
        matching: find.byType(EditableText));
    if (editable.evaluate().isNotEmpty &&
        tester.widget<EditableText>(editable).focusNode.hasFocus) {
      return name;
    }
  }
  return null;
}

void main() {
  testWidgets('the planner has a New event button that opens the pop-up',
      (tester) async {
    await _openFromButton(tester, _api());
    expect(find.text('New event'), findsWidgets);
    // The pop-up starts at the next full hour of the planner clock.
    expect(find.byKey(const Key('new-event-ends')), findsOneWidget);
  });

  testWidgets('the standard invitees are listed, and nobody is ticked at first',
      (tester) async {
    final api = _api();
    await _openFromButton(tester, api);
    for (final a in _invitees) {
      final box = tester
          .widget<CheckboxListTile>(find.byKey(Key('new-event-invitee-$a')));
      expect(box.value, isFalse);
    }
    await tester.enterText(find.byKey(const Key('new-event-title')), 'Plan');
    await tester.pump();
    await tester.tap(find.byKey(const Key('new-event-create')));
    await tester.pumpAndSettle();
    // Nobody ticked: nobody is invited.
    expect(
        (api.where('POST /calendar/entries').single.data! as Map)
            .containsKey('attendees'),
        isFalse);
  });

  testWidgets('the ticked people are sent as attendees', (tester) async {
    final api = _api();
    await _openFromButton(tester, api);
    await tester.enterText(find.byKey(const Key('new-event-title')), 'Plan');
    await tester.ensureVisible(
        find.byKey(const Key('new-event-invitee-kim@example.org')));
    await tester
        .tap(find.byKey(const Key('new-event-invitee-kim@example.org')));
    await tester.pump();
    expect(find.byKey(const Key('new-event-invite-note')), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-event-create')));
    await tester.pumpAndSettle();
    expect(
        (api.where('POST /calendar/entries').single.data! as Map)['attendees'],
        ['kim@example.org']);
  });

  testWidgets('with no standard invitees the pop-up points to the settings',
      (tester) async {
    await _openFromButton(tester, _api(invitees: const []));
    expect(find.byKey(const Key('new-event-no-invitees')), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets('Tab goes from field to field, and skips the picker buttons',
      (tester) async {
    await _openFromButton(tester, _api());
    expect(_focusedField(tester), 'title');
    final seen = <String?>[];
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      seen.add(_focusedField(tester));
    }
    // title, [calendar], day, [all day], starts at, length, place. A focusable
    // picker button would add a null between the typed fields.
    expect(seen, [null, 'date', null, 'start', 'length', 'location']);
    // Space ticks the invitee that the next Tab reaches.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const Key('new-event-invitee-sam@example.com')))
            .value,
        isTrue);
  });

  testWidgets('the day and the time are typed as 20261102 and 1105',
      (tester) async {
    final api = _api();
    await _openFromButton(tester, api);
    await tester.enterText(find.byKey(const Key('new-event-title')), 'Plan');
    await tester.enterText(find.byKey(const Key('new-event-date')), '20261102');
    await tester.enterText(find.byKey(const Key('new-event-start')), '1105');
    await tester.pump();
    expect(find.text('Ends 2026-11-02 12:05'), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-event-create')));
    await tester.pumpAndSettle();
    final start = DateTime.parse(
        '${(api.where('POST /calendar/entries').single.data! as Map)['start']}');
    expect(start.toLocal(), DateTime(2026, 11, 2, 11, 5));
  });

  testWidgets('the time picker uses 24 hours, with no AM or PM',
      (tester) async {
    await _openFromButton(tester, _api());
    await tester.tap(find.byKey(const Key('new-event-start-pick')));
    await tester.pumpAndSettle();
    expect(find.text('AM'), findsNothing);
    expect(find.text('PM'), findsNothing);
  });
}
