import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/calendar_color.dart';
import 'package:tefteri/theme/theme.dart';

import '../../support/fake_api.dart';
import 'planner_helpers.dart';

/// Mouse-like platform: a drag starts at once (touch needs a long press).
final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

final _thursday = DateTime(2026, 11, 5);

Map<String, Object?> _entryJson(String id) => {
      'id': id,
      'connection_id': 'c2',
      'title': 'x',
      'start': '2026-11-04T14:00:00Z',
      'end': '2026-11-04T15:00:00Z',
      'all_day': false,
      'sync_state': 'synced',
    };

FakeApi _api(
        {List<Object?>? calendar, Map<String, Object?> extra = const {}}) =>
    plannerApi(
      calendar: calendar ??
          [
            calItem('entry', 'e1', 'Standup',
                start: DateTime(2026, 11, 4, 9),
                end: DateTime(2026, 11, 4, 10, 30),
                color: '#039be5'),
            calItem('entry', 'ro', 'Holiday party',
                start: DateTime(2026, 11, 4, 16), readOnly: true),
            calItem('entry', 'day', 'All day thing',
                start: DateTime(2026, 11, 5),
                end: DateTime(2026, 11, 6),
                allDay: true),
          ],
      extra: {
        'PATCH /calendar/entries/e1': _entryJson('e1'),
        'POST /calendar/entries': _entryJson('new'),
        'GET /connections': [
          connectionJson('c1', 'tasks', 'Home tasks'),
          connectionJson('c2', 'calendar', 'Work calendar'),
        ],
        'GET /connections/c2/containers': [
          {
            'id': 'k1',
            'remote_id': 'work',
            'name': 'Work',
            'color': '#d50000',
            'enabled': true,
            'read_only': false,
          },
          {
            'id': 'k2',
            'remote_id': 'shared',
            'name': 'Shared (read only)',
            'color': null,
            'enabled': true,
            'read_only': true,
          },
          {
            'id': 'k3',
            'remote_id': 'holidays',
            'name': 'Holidays (off)',
            'color': null,
            'enabled': false,
            'read_only': false,
          },
        ],
        'GET /connections/c1/containers': [
          {
            'id': 'p1',
            'remote_id': '1',
            'name': 'Inbox',
            'parent_remote_id': null
          },
        ],
        'GET /connections/c1/labels': <Object?>[],
        ...extra,
      },
    );

Future<void> _rightClickAt(WidgetTester tester, Offset at) async {
  await tester.tapAt(at, buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

void main() {
  group('dragging an event', () {
    testWidgets('moves it and keeps its length', (tester) async {
      final api = _api();
      await pumpPlanner(tester, api);
      await dragTo(tester, find.byKey(const Key('block-entry-e1')),
          slotPoint(tester, wednesday, 14, 0));
      final body = api.where('PATCH /calendar/entries/e1').single.data! as Map;
      // The event was 09:00 to 10:30, so it is 14:00 to 15:30 now. The times
      // go as UTC (the test runs in UTC, so they read the same).
      final start = DateTime.parse('${body['start']}').toLocal();
      final end = DateTime.parse('${body['end']}').toLocal();
      expect(start, DateTime(2026, 11, 4, 14));
      expect(end, DateTime(2026, 11, 4, 15, 30));
      // The calendar loads again after the save.
      expect(api.where('GET /calendar').length, greaterThan(1));
    }, variant: _linux);

    testWidgets('can go to another day', (tester) async {
      final api = _api();
      await pumpPlanner(tester, api);
      await dragTo(tester, find.byKey(const Key('block-entry-e1')),
          slotPoint(tester, _thursday, 11, 30));
      final body = api.where('PATCH /calendar/entries/e1').single.data! as Map;
      expect(DateTime.parse('${body['start']}').toLocal(),
          DateTime(2026, 11, 5, 11, 30));
    }, variant: _linux);

    testWidgets('shows where it lands, with its own length and color',
        (tester) async {
      final api = _api();
      await pumpPlanner(tester, api);
      final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('block-entry-e1'))));
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveTo(slotPoint(tester, wednesday, 13, 5));
      await tester.pump(const Duration(milliseconds: 300));
      // 90 minutes from the 13:00 slot, not the one hour of a task.
      expect(
          tester.widget<Text>(find.byKey(const Key('drop-preview-time'))).data,
          '13:00 - 14:30');
      final preview = tester.widget<Container>(find.descendant(
          of: find.byKey(const Key('drop-preview')),
          matching: find.byType(Container)));
      final border = (preview.decoration! as BoxDecoration).border! as Border;
      expect(border.top.color, parseCalendarColor('#039be5'));
      await gesture.up();
      await settle(tester);
    }, variant: _linux);

    testWidgets('does nothing when it is dropped where it was', (tester) async {
      final api = _api();
      await pumpPlanner(tester, api);
      await dragTo(tester, find.byKey(const Key('block-entry-e1')),
          slotPoint(tester, wednesday, 9, 0));
      expect(api.where('PATCH /calendar/entries/e1'), isEmpty);
    }, variant: _linux);

    testWidgets('is not possible in a read-only calendar', (tester) async {
      final api = _api(extra: {
        'PATCH /calendar/entries/ro': _entryJson('ro'),
      });
      await pumpPlanner(tester, api);
      final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('block-entry-ro'))));
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveTo(slotPoint(tester, wednesday, 11, 0));
      await tester.pump(const Duration(milliseconds: 300));
      // No drag started: the calendar does not fade back, and no preview.
      expect(find.byKey(const Key('drop-preview')), findsNothing);
      await gesture.up();
      await settle(tester);
      expect(api.where('PATCH /calendar/entries/ro'), isEmpty);
    }, variant: _linux);

    testWidgets('is not possible for an all-day event', (tester) async {
      final api = _api();
      await pumpPlanner(tester, api);
      final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('allday-entry-day'))));
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveTo(slotPoint(tester, _thursday, 11, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('drop-preview')), findsNothing);
      await gesture.up();
      await settle(tester);
    }, variant: _linux);

    testWidgets('shows the refusal of the calendar app and keeps the event',
        (tester) async {
      final api = _api(extra: {
        'PATCH /calendar/entries/e1': const ApiFailure(
            422,
            'The calendar "Work" is read-only. Nothing was changed.',
            'invalid'),
      });
      await pumpPlanner(tester, api);
      await dragTo(tester, find.byKey(const Key('block-entry-e1')),
          slotPoint(tester, wednesday, 14, 0));
      expect(
          find.text('The calendar "Work" is read-only. Nothing was changed.'),
          findsOneWidget);
    }, variant: _linux);
  });

  group('a right click on an empty slot', () {
    testWidgets('offers a new event and a new task at that time',
        (tester) async {
      await pumpPlanner(tester, _api());
      await _rightClickAt(tester, slotPoint(tester, wednesday, 13, 20));
      expect(find.byKey(const Key('slot-new-event')), findsOneWidget);
      expect(find.byKey(const Key('slot-new-task')), findsOneWidget);
      // The time is the slot under the pointer (a quarter of an hour).
      expect(find.text('New event at 13:15'), findsOneWidget);
      expect(find.text('New task at 13:15'), findsOneWidget);
    });

    testWidgets('a new task starts with that day and time', (tester) async {
      await pumpPlanner(tester, _api());
      await _rightClickAt(tester, slotPoint(tester, wednesday, 13, 20));
      await tester.tap(find.byKey(const Key('slot-new-task')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-task-title')), findsOneWidget);
      expect(
          tester
              .widget<Text>(find.byKey(const Key('new-task-date-value')))
              .data,
          '2026-11-04');
      expect(
          tester
              .widget<Text>(find.byKey(const Key('new-task-time-value')))
              .data,
          '13:15');
    });

    testWidgets('a new event starts with that day and time', (tester) async {
      await pumpPlanner(tester, _api());
      await _rightClickAt(tester, slotPoint(tester, wednesday, 13, 20));
      await tester.tap(find.byKey(const Key('slot-new-event')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-event-dialog')), findsOneWidget);
      String value(String key) =>
          tester.widget<Text>(find.byKey(Key(key))).data!;
      expect(value('new-event-date-value'), '2026-11-04');
      expect(value('new-event-start-value'), '13:15');
      expect(value('new-event-end-value'), '14:15'); // one hour
    });

    testWidgets('creates the event in a calendar that can be changed',
        (tester) async {
      final api = _api();
      await pumpPlanner(tester, api);
      await _rightClickAt(tester, slotPoint(tester, wednesday, 13, 20));
      await tester.tap(find.byKey(const Key('slot-new-event')));
      await tester.pumpAndSettle();
      // Create stays off until there is a title.
      expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('new-event-create')))
              .onPressed,
          isNull);
      await tester.enterText(
          find.byKey(const Key('new-event-title')), 'Dentist');
      await tester.enterText(
          find.byKey(const Key('new-event-location')), 'Clinic');
      await tester.pump();
      await tester.tap(find.byKey(const Key('new-event-create')));
      await tester.pumpAndSettle();
      final body = api.where('POST /calendar/entries').single.data! as Map;
      expect(body['connection_id'], 'c2');
      expect(body['container_id'],
          'k1'); // the first calendar that is on and not read-only
      expect(body['title'], 'Dentist');
      expect(body['location'], 'Clinic');
      expect(body['all_day'], false);
      expect(DateTime.parse('${body['start']}').toLocal(),
          DateTime(2026, 11, 4, 13, 15));
      expect(DateTime.parse('${body['end']}').toLocal(),
          DateTime(2026, 11, 4, 14, 15));
      expect(find.byKey(const Key('new-event-dialog')), findsNothing);
      expect(find.text('Event added to Work.'), findsOneWidget);
      expect(api.where('GET /calendar').length, greaterThan(1));
    });

    testWidgets('lists only the calendars that are on and can be changed',
        (tester) async {
      await pumpPlanner(tester, _api());
      await _rightClickAt(tester, slotPoint(tester, wednesday, 13, 20));
      await tester.tap(find.byKey(const Key('slot-new-event')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-event-calendar')));
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsWidgets);
      expect(find.text('Shared (read only)'), findsNothing);
      expect(find.text('Holidays (off)'), findsNothing);
    });

    testWidgets('says so when no calendar can take the event', (tester) async {
      final api = _api(extra: {
        'GET /connections/c2/containers': <Object?>[
          {
            'id': 'k2',
            'remote_id': 'shared',
            'name': 'Shared',
            'enabled': true,
            'read_only': true,
          },
        ],
      });
      await pumpPlanner(tester, api);
      await _rightClickAt(tester, slotPoint(tester, wednesday, 13, 20));
      await tester.tap(find.byKey(const Key('slot-new-event')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-event-no-calendar')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('new-event-title')), 'x');
      await tester.pump();
      expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('new-event-create')))
              .onPressed,
          isNull);
    });

    testWidgets('an event that ends before it starts is refused',
        (tester) async {
      await pumpPlanner(tester, _api());
      // A click at 23:30: the end is capped at 23:59, still after the start.
      await _rightClickAt(tester, slotPoint(tester, wednesday, 23, 30));
      await tester.tap(find.byKey(const Key('slot-new-event')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-event-times-error')), findsNothing);
      await tester.enterText(find.byKey(const Key('new-event-title')), 'Late');
      await tester.pump();
      expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('new-event-create')))
              .onPressed,
          isNotNull);
    });

    testWidgets('shows the reason when the calendar app refuses',
        (tester) async {
      final api = _api(extra: {
        'POST /calendar/entries': const ApiFailure(
            502,
            'Work calendar cannot be reached. Nothing was changed.',
            'backend_unavailable'),
      });
      await pumpPlanner(tester, api);
      await _rightClickAt(tester, slotPoint(tester, wednesday, 13, 20));
      await tester.tap(find.byKey(const Key('slot-new-event')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('new-event-title')), 'x');
      await tester.pump();
      await tester.tap(find.byKey(const Key('new-event-create')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-event-error')), findsOneWidget);
      // The dialog stays, so nothing the user typed is lost.
      expect(find.byKey(const Key('new-event-dialog')), findsOneWidget);
    });

    testWidgets('a right click on a block opens no menu', (tester) async {
      await pumpPlanner(tester, _api());
      await tester.tap(find.byKey(const Key('block-entry-e1')),
          buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('slot-new-event')), findsNothing);
      expect(find.byKey(const Key('event-details')), findsNothing);
    });

    testWidgets('on the all-day row it offers an all-day event',
        (tester) async {
      final api = _api();
      await pumpPlanner(tester, api);
      await _rightClickAt(
          tester, tester.getCenter(find.byKey(const Key('allday-2026-11-04'))));
      expect(find.text('New event on 2026-11-04'), findsOneWidget);
      await tester.tap(find.byKey(const Key('slot-new-event')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<SwitchListTile>(
                  find.byKey(const Key('new-event-all-day')))
              .value,
          isTrue);
      expect(find.byKey(const Key('new-event-start')), findsNothing);
      await tester.enterText(find.byKey(const Key('new-event-title')), 'Away');
      await tester.pump();
      await tester.tap(find.byKey(const Key('new-event-create')));
      await tester.pumpAndSettle();
      final body = api.where('POST /calendar/entries').single.data! as Map;
      expect(body['all_day'], true);
      // The days of the user: local midnight of the day to local midnight of
      // the next day. The server turns them into dates.
      expect(
          DateTime.parse('${body['start']}').toLocal(), DateTime(2026, 11, 4));
      expect(DateTime.parse('${body['end']}').toLocal(), DateTime(2026, 11, 5));
    });

    testWidgets('on the all-day row a new task starts with the day only',
        (tester) async {
      await pumpPlanner(tester, _api());
      await _rightClickAt(
          tester, tester.getCenter(find.byKey(const Key('allday-2026-11-04'))));
      await tester.tap(find.byKey(const Key('slot-new-task')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const Key('new-task-date-value')))
              .data,
          '2026-11-04');
      expect(
          tester
              .widget<Text>(find.byKey(const Key('new-task-time-value')))
              .data,
          'All day');
    });
  });

  testWidgets('the event dialog fits a phone screen', (tester) async {
    await pumpPlanner(tester, _api());
    await _rightClickAt(tester, slotPoint(tester, wednesday, 13, 20));
    await tester.tap(find.byKey(const Key('slot-new-event')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tefteriLight, isNotNull);
  });
}
