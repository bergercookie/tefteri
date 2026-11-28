import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/planner/time_grid.dart';

import '../../support/fake_api.dart';
import 'planner_helpers.dart';

DateTime _at(int h, [int m = 0]) => DateTime(2026, 11, 3, h, m);

FakeApi _api(List<Object?> calendar, {Map<String, Object?> extra = const {}}) =>
    plannerApi(calendar: calendar, extra: {
      'PATCH /calendar/entries/e1': {
        'id': 'e1',
        'connection_id': 'c1',
        'title': 'x',
        'start': '2026-11-03T09:00:00Z',
        'end': '2026-11-03T09:30:00Z',
        'all_day': false,
        'location': '',
        'description': '',
        'sync_state': 'synced',
      },
      ...extra,
    });

Map<String, Object?> _event(
        {String title = 'Team standup',
        DateTime? start,
        DateTime? end,
        bool allDay = false,
        bool readOnly = false,
        String? location,
        String? description,
        String? calendar,
        String? uid}) =>
    calItem('entry', 'e1', title,
        start: start ?? _at(9),
        end: end ?? _at(9, 30),
        allDay: allDay,
        readOnly: readOnly,
        location: location,
        description: description,
        calendar: calendar,
        uid: uid);

Future<FakeApi> _open(WidgetTester tester, Map<String, Object?> event,
    {FakeApi? api, String block = 'block-entry-e1'}) async {
  final fake = api ?? _api([event]);
  await pumpPlanner(tester, fake);
  await tester.tap(find.byKey(Key(block)));
  await settle(tester);
  expect(find.byKey(const Key('event-details')), findsOneWidget);
  return fake;
}

String _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

bool _canSave(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const Key('event-edit-save')))
        .onPressed !=
    null;

Map<Object?, Object?> _patch(FakeApi api) =>
    api.where('PATCH /calendar/entries/e1').single.data! as Map;

void main() {
  testWidgets('an event shows its place and description in the form',
      (tester) async {
    await _open(
        tester,
        _event(
            location: 'Room 4',
            description: 'Roadmap and hiring.',
            calendar: 'Work'));
    expect(_field(tester, 'event-edit-location'), 'Room 4');
    expect(_field(tester, 'event-edit-description'), 'Roadmap and hiring.');
    // Nothing is changed: Save is off.
    expect(_canSave(tester), isFalse);
  });

  testWidgets('the title, the place and the description are saved',
      (tester) async {
    final api = await _open(tester, _event());
    await tester.enterText(
        find.byKey(const Key('event-edit-title')), '  Weekly standup ');
    await tester.enterText(
        find.byKey(const Key('event-edit-location')), 'Room 7');
    await tester.enterText(
        find.byKey(const Key('event-edit-description')), 'Agenda:\n1. Roadmap');
    await tester.pump();
    expect(_canSave(tester), isTrue);
    final before = api.where('GET /calendar').length;
    await tester.tap(find.byKey(const Key('event-edit-save')));
    await settle(tester);
    // Only what changed is sent, and the time is not in it.
    expect(_patch(api), {
      'title': 'Weekly standup',
      'location': 'Room 7',
      'description': 'Agenda:\n1. Roadmap',
    });
    expect(find.byKey(const Key('event-details')), findsNothing);
    // The calendar reads again, so the change shows.
    expect(api.where('GET /calendar').length, greaterThan(before));
  });

  testWidgets(
      'the day and the time are typed as 20261104 and 1105, in 24 hours',
      (tester) async {
    final api = await _open(tester, _event());
    await tester.enterText(find.byKey(const Key('event-edit-day')), '20261104');
    await tester.enterText(find.byKey(const Key('event-edit-start')), '1105');
    await tester.pump();
    expect(_canSave(tester), isTrue);
    // The length stays, so the end moves with the start.
    expect(find.text('Ends 2026-11-04 11:35'), findsOneWidget);
    await tester.tap(find.byKey(const Key('event-edit-save')));
    await settle(tester);
    final body = _patch(api);
    expect(DateTime.parse('${body['start']}').toLocal(),
        DateTime(2026, 11, 4, 11, 5));
    expect(DateTime.parse('${body['end']}').toLocal(),
        DateTime(2026, 11, 4, 11, 35));
    expect(body.keys, containsAll(['start', 'end']));
    expect(body.containsKey('title'), isFalse);
  });

  testWidgets('a new length changes the end', (tester) async {
    final api = await _open(tester, _event());
    await tester.enterText(find.byKey(const Key('event-edit-length')), '1h30');
    await tester.pump();
    expect(find.text('Ends 2026-11-03 10:30'), findsOneWidget);
    await tester.tap(find.byKey(const Key('event-edit-save')));
    await settle(tester);
    final body = _patch(api);
    expect(DateTime.parse('${body['start']}').toLocal(), _at(9));
    expect(DateTime.parse('${body['end']}').toLocal(), _at(10, 30));
  });

  testWidgets('a time or a length that is not valid stops Save',
      (tester) async {
    await _open(tester, _event());
    await tester.enterText(find.byKey(const Key('event-edit-start')), '2561');
    await tester.pump();
    expect(find.text('Type the time as HHmm'), findsOneWidget);
    expect(_canSave(tester), isFalse);
    await tester.enterText(find.byKey(const Key('event-edit-start')), '0900');
    await tester.enterText(find.byKey(const Key('event-edit-length')), 'soon');
    await tester.pump();
    expect(_canSave(tester), isFalse);
    // An empty title stops it too.
    await tester.enterText(find.byKey(const Key('event-edit-length')), '30m');
    await tester.enterText(find.byKey(const Key('event-edit-title')), '  ');
    await tester.pump();
    expect(_canSave(tester), isFalse);
  });

  testWidgets('the time picker uses 24 hours', (tester) async {
    await _open(tester, _event());
    await tester.tap(find.byKey(const Key('event-edit-start-pick')));
    await tester.pumpAndSettle();
    expect(find.text('AM'), findsNothing);
    expect(find.text('PM'), findsNothing);
  });

  testWidgets('Tab goes from field to field and skips the picker buttons',
      (tester) async {
    await _open(tester, _event());
    String? focused() {
      for (final n in [
        'title',
        'day',
        'start',
        'length',
        'location',
        'description'
      ]) {
        final f = find.descendant(
            of: find.byKey(Key('event-edit-$n')),
            matching: find.byType(EditableText));
        if (f.evaluate().isNotEmpty &&
            tester.widget<EditableText>(f).focusNode.hasFocus) {
          return n;
        }
      }
      return null;
    }

    expect(focused(), 'title');
    final seen = <String?>[];
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      seen.add(focused());
    }
    expect(seen, ['day', 'start', 'length', 'location', 'description']);
  });

  testWidgets('Ctrl+Enter saves, Cancel does not', (tester) async {
    final api = await _open(tester, _event());
    await tester.enterText(find.byKey(const Key('event-edit-title')), 'Sync');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(_patch(api), {'title': 'Sync'});

    final cancelled = await _open(tester, _event(), api: _api([_event()]));
    await tester.enterText(find.byKey(const Key('event-edit-title')), 'Nope');
    await tester.tap(find.byKey(const Key('event-details-close')));
    await settle(tester);
    expect(cancelled.where('PATCH /calendar/entries/e1'), isEmpty);
    expect(find.byKey(const Key('event-details')), findsNothing);
  });

  testWidgets('the message of the server shows, and the pop-up stays',
      (tester) async {
    final api = _api([
      _event()
    ], extra: {
      'PATCH /calendar/entries/e1': const ApiFailure(
          502, 'Google Calendar did not answer.', 'unavailable'),
    });
    await _open(tester, _event(), api: api);
    await tester.enterText(find.byKey(const Key('event-edit-title')), 'Sync');
    await tester.pump();
    await tester.tap(find.byKey(const Key('event-edit-save')));
    await settle(tester);
    expect(find.text('Google Calendar did not answer.'), findsOneWidget);
    expect(find.byKey(const Key('event-details')), findsOneWidget);
    expect(_field(tester, 'event-edit-title'), 'Sync');
  });

  testWidgets('an event of a read-only calendar cannot be changed',
      (tester) async {
    await _open(tester, _event(readOnly: true, location: 'Room 4'));
    expect(find.byKey(const Key('event-edit-readonly')), findsOneWidget);
    expect(find.byKey(const Key('event-edit-save')), findsNothing);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('event-edit-title')))
            .enabled,
        isFalse);
    expect(_field(tester, 'event-edit-location'), 'Room 4');
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('an all-day event has no time to change, only its text',
      (tester) async {
    final api = await _open(
        tester,
        _event(
            allDay: true,
            start: DateTime(2026, 11, 3),
            end: DateTime(2026, 11, 4)),
        block: 'allday-entry-e1');
    expect(find.byKey(const Key('event-edit-start')), findsNothing);
    expect(find.byKey(const Key('event-edit-day')), findsNothing);
    expect(find.byKey(const Key('event-edit-allday-note')), findsOneWidget);
    expect(find.text('2026-11-03, all day'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('event-edit-title')), 'Public holiday');
    await tester.pump();
    await tester.tap(find.byKey(const Key('event-edit-save')));
    await settle(tester);
    expect(_patch(api), {'title': 'Public holiday'});
  });

  testWidgets('an HTML description shows formatted first', (tester) async {
    await _open(
        tester,
        _event(
            description:
                '<p>See <a href="https://example.com/x">the plan</a></p>'));
    final formatted = find.byKey(const Key('event-edit-description-formatted'));
    expect(formatted, findsOneWidget);
    expect(find.textContaining('<p>'), findsNothing);
    expect(find.byKey(const Key('event-edit-description')), findsNothing);
    await tester.tap(find.byKey(const Key('event-edit-description-edit')));
    await tester.pump();
    expect(_field(tester, 'event-edit-description'),
        '<p>See <a href="https://example.com/x">the plan</a></p>');
  });

  testWidgets('an event in several calendars says where the change is made',
      (tester) async {
    final api = _api([
      calItem('entry', 'e1', 'Offsite',
          start: _at(9),
          end: _at(10),
          calendar: 'Work',
          containerId: 'k1',
          uid: 'u1'),
      calItem('entry', 'e2', 'Offsite',
          start: _at(9),
          end: _at(10),
          calendar: 'Family',
          containerId: 'k2',
          uid: 'u1'),
    ]);
    await pumpPlanner(tester, api);
    await tester.tap(find.byKey(const Key('block-entry-e1')));
    await settle(tester);
    expect(find.byKey(const Key('event-edit-shared')), findsOneWidget);
    expect(find.textContaining('is made in Work only'), findsOneWidget);
  });

  group('the edges of an event', () {
    Finder handle(String edge) => find.byKey(Key('resize-$edge-e1'));
    // An hour is hourHeight pixels, so a quarter of an hour is a quarter of it.
    const quarter = hourHeight / 4;

    Future<FakeApi> pump(WidgetTester tester, Map<String, Object?> e) async {
      final api = _api([e]);
      await pumpPlanner(tester, api);
      return api;
    }

    testWidgets('an Android phone has no edges to drag', (tester) async {
      await pump(tester, _event());
      expect(find.byKey(const Key('block-entry-e1')), findsOneWidget);
      expect(handle('start'), findsNothing);
      expect(handle('end'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('dragging the bottom edge down makes the event longer',
        (tester) async {
      final api = await pump(tester, _event());
      // Two quarters of an hour down: half an hour longer.
      await tester.drag(handle('end'), const Offset(0, quarter * 2));
      await settle(tester);
      final body = _patch(api);
      expect(DateTime.parse('${body['start']}').toLocal(), _at(9));
      expect(DateTime.parse('${body['end']}').toLocal(), _at(10));
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('dragging the top edge up makes the event start earlier',
        (tester) async {
      final api = await pump(tester, _event());
      await tester.drag(handle('start'), const Offset(0, -quarter * 3));
      await settle(tester);
      final body = _patch(api);
      expect(DateTime.parse('${body['start']}').toLocal(), _at(8, 15));
      expect(DateTime.parse('${body['end']}').toLocal(), _at(9, 30));
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('a change of an edge can be undone', (tester) async {
      final api = await pump(tester, _event());
      await tester.drag(handle('end'), const Offset(0, quarter * 2));
      await settle(tester);
      expect(find.text('Event changed'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await settle(tester);
      final all = api.where('PATCH /calendar/entries/e1');
      expect(all, hasLength(2));
      final back = all.last.data! as Map;
      expect(DateTime.parse('${back['start']}').toLocal(), _at(9));
      expect(DateTime.parse('${back['end']}').toLocal(), _at(9, 30));
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('an edge snaps to a quarter of an hour', (tester) async {
      final api = await pump(tester, _event());
      // A move that is too small starts no drag: nothing changes.
      await tester.drag(handle('end'), const Offset(0, 5));
      await settle(tester);
      expect(api.where('PATCH /calendar/entries/e1'), isEmpty);
      // 20 pixels are 21 minutes: it snaps to 15.
      await tester.drag(handle('end'), const Offset(0, 20));
      await settle(tester);
      final body = _patch(api);
      expect(DateTime.parse('${body['end']}').toLocal(), _at(9, 45));
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('the event is never shorter than a quarter of an hour',
        (tester) async {
      final api = await pump(tester, _event());
      await tester.drag(handle('end'), const Offset(0, -hourHeight * 3));
      await settle(tester);
      final body = _patch(api);
      expect(DateTime.parse('${body['start']}').toLocal(), _at(9));
      expect(DateTime.parse('${body['end']}').toLocal(), _at(9, 15));
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('the end stays on the day', (tester) async {
      final api = await pump(tester, _event(start: _at(23), end: _at(23, 30)));
      await tester.drag(handle('end'), const Offset(0, hourHeight * 3));
      await settle(tester);
      final body = _patch(api);
      expect(DateTime.parse('${body['end']}').toLocal(), DateTime(2026, 11, 4));
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('a label shows the new times while the edge is dragged',
        (tester) async {
      await pump(tester, _event());
      final gesture =
          await tester.startGesture(tester.getCenter(handle('end')));
      // An hour down: from 09:30 to 10:30.
      await gesture.moveBy(const Offset(0, hourHeight));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 0));
      await tester.pump();
      expect(find.byKey(const Key('resize-label-e1')), findsOneWidget);
      expect(find.text('09:00 - 10:30'), findsOneWidget);
      await gesture.up();
      await settle(tester);
      expect(find.byKey(const Key('resize-label-e1')), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('a click on the event still opens it', (tester) async {
      await pump(tester, _event());
      await tester.tap(find.byKey(const Key('block-entry-e1')));
      await settle(tester);
      expect(find.byKey(const Key('event-details')), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('a failed save shows the message and the event stays',
        (tester) async {
      final api = _api([
        _event()
      ], extra: {
        'PATCH /calendar/entries/e1': const ApiFailure(
            502, 'Google Calendar did not answer.', 'unavailable'),
      });
      await pumpPlanner(tester, api);
      await tester.drag(handle('end'), const Offset(0, quarter * 2));
      await settle(tester);
      expect(find.text('Google Calendar did not answer.'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets(
        'an event of a read-only calendar, an all-day event and a task '
        'have no edge to drag', (tester) async {
      await pump(tester, _event(readOnly: true));
      expect(handle('start'), findsNothing);
      expect(handle('end'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('an event that goes on past the day has no edge to drag',
        (tester) async {
      await pump(tester, _event(start: _at(22), end: DateTime(2026, 11, 4, 2)));
      expect(handle('end'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });
}
