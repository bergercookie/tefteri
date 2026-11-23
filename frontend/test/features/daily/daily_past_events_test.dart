import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/daily/daily_providers.dart';
import 'package:tefteri/features/daily/daily_screen.dart';

import '../../support/fake_api.dart';

/// An event on 2026-11-01. Times are local, like the clock of the test.
Map<String, Object?> _event(String id, int startHour, int endHour,
        {int startMinute = 0, int endMinute = 0}) =>
    {
      'id': id,
      'connection_id': 'c2',
      'title': 'Event $id',
      'start': DateTime(2026, 11, 1, startHour, startMinute)
          .toUtc()
          .toIso8601String(),
      'end':
          DateTime(2026, 11, 1, endHour, endMinute).toUtc().toIso8601String(),
      'all_day': false,
      'location': '',
      'sync_state': 'synced',
    };

Map<String, Object?> _allDay(String id, int day) => {
      'id': id,
      'connection_id': 'c2',
      'title': 'All day $id',
      'start': DateTime(2026, 11, day).toUtc().toIso8601String(),
      'end': DateTime(2026, 11, day + 1).toUtc().toIso8601String(),
      'all_day': true,
      'location': '',
      'sync_state': 'synced',
    };

FakeApi _api(List<Map<String, Object?>> events, {String day = '2026-11-01'}) =>
    FakeApi({
      'GET /views/day/$day': {
        'date': day,
        'entries': events,
        'tasks': <Object?>[],
        'note': null,
      },
      'GET /connections': <Object?>[],
    });

/// A clock that the test can move.
class _Clock {
  _Clock(this.now);
  DateTime now;
}

Future<_Clock> _pump(
  WidgetTester tester,
  List<Map<String, Object?>> events, {
  required DateTime now,
  DateTime? start,
  Size size = const Size(800, 500),
}) async {
  final clock = _Clock(now);
  await pumpWithApi(
    tester,
    _api(events),
    DailyScreen(initialDate: start ?? DateTime(2026, 11, 1)),
    overrides: [dailyClockProvider.overrideWithValue(() => clock.now)],
    size: size,
  );
  await tester.pumpAndSettle();
  // The minute timer runs while today is shown; the tree goes away at the end.
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  return clock;
}

double _top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

/// The scrollable of the list of the day (the shell has others).
final _list = find
    .descendant(
        of: find.byKey(const Key('day-list')),
        matching: find.byType(Scrollable))
    .first;

void main() {
  testWidgets('an event that is over is grayed out, the others are not',
      (tester) async {
    await _pump(
      tester,
      [
        _event('over', 8, 9),
        _event('now', 9, 12), // it is 10:00: on now
        _event('next', 14, 15),
        _allDay('today', 1),
      ],
      now: DateTime(2026, 11, 1, 10),
    );
    expect(find.byKey(const Key('entry-past-over')), findsOneWidget);
    expect(find.byKey(const Key('entry-past-now')), findsNothing);
    expect(find.byKey(const Key('entry-past-next')), findsNothing);
    // An all-day event of today is not over.
    expect(find.byKey(const Key('entry-past-today')), findsNothing);
    expect(
        tester
            .widget<Opacity>(find.byKey(const Key('entry-past-over')))
            .opacity,
        lessThan(1));
  });

  testWidgets('an event that ends at this minute is over', (tester) async {
    await _pump(tester, [_event('a', 9, 10)], now: DateTime(2026, 11, 1, 10));
    expect(find.byKey(const Key('entry-past-a')), findsOneWidget);
  });

  testWidgets('every event of a day that has passed is grayed out',
      (tester) async {
    await _pump(
      tester,
      [_event('a', 15, 16), _allDay('b', 1)],
      now: DateTime(2026, 11, 5, 9), // four days later
    );
    expect(find.byKey(const Key('entry-past-a')), findsOneWidget);
    expect(find.byKey(const Key('entry-past-b')), findsOneWidget);
  });

  testWidgets('no event of a day to come is grayed out', (tester) async {
    await _pump(
      tester,
      [_event('a', 8, 9), _allDay('b', 1)],
      now: DateTime(2026, 10, 30, 12), // two days before
    );
    expect(find.byType(Opacity), findsNothing);
  });

  group('the start of the list on today', () {
    final many = [
      for (var h = 6; h < 24; h++) _event('e$h', h, h + 1 > 23 ? 23 : h + 1),
    ];

    Future<double> offset(WidgetTester tester) async =>
        tester.state<ScrollableState>(_list).position.pixels;

    testWidgets('starts at the next event, with the earlier ones scrolled away',
        (tester) async {
      await _pump(tester, many, now: DateTime(2026, 11, 1, 14, 30));
      // 14:30: the event of 14:00 to 15:00 is on, and it is the first that is
      // not over.
      final scroll = _top(tester, find.byKey(const Key('day-list')));
      expect(await offset(tester), greaterThan(0));
      expect(_top(tester, find.byKey(const Key('entry-e14'))) - scroll,
          lessThan(12)); // padding only
      // The events that are over are above the top of the list.
      expect(
          _top(tester, find.byKey(const Key('entry-e13'))), lessThan(scroll));
      expect(_top(tester, find.byKey(const Key('entry-e6'))), lessThan(scroll));
      // The events to come are below it.
      expect(_top(tester, find.byKey(const Key('entry-e15'))),
          greaterThan(_top(tester, find.byKey(const Key('entry-e14')))));
    });

    testWidgets('the next event is the first even when none is on',
        (tester) async {
      await _pump(tester, many, now: DateTime(2026, 11, 1, 14, 59, 30));
      final scroll = _top(tester, find.byKey(const Key('day-list')));
      // 14:59: the event of 14:00 is on until 15:00.
      expect(_top(tester, find.byKey(const Key('entry-e14'))) - scroll,
          lessThan(12));
      // Later, at 15:00, the event of 14:00 is over and 15:00 is on.
      expect(find.byKey(const Key('entry-past-e13')), findsOneWidget);
    });

    testWidgets('does not scroll at the start of the day', (tester) async {
      await _pump(tester, many, now: DateTime(2026, 11, 1, 5)); // before all
      expect(await offset(tester), 0);
      expect(find.byKey(const Key('entry-past-e6')), findsNothing);
    });

    testWidgets('starts at the tasks when every event is over', (tester) async {
      await _pump(tester, many, now: DateTime(2026, 11, 1, 23, 50));
      final scroll = _top(tester, find.byKey(const Key('day-list')));
      expect(await offset(tester), greaterThan(0));
      expect(_top(tester, find.text('Tasks')) - scroll, lessThan(12));
      expect(
          _top(tester, find.byKey(const Key('entry-e22'))), lessThan(scroll));
    });

    testWidgets('does not scroll on another day', (tester) async {
      // Looking at a past day, it is still the list from the top.
      await _pump(tester, many,
          now: DateTime(2026, 11, 5, 12), start: DateTime(2026, 11, 1));
      expect(await offset(tester), 0);
    });

    testWidgets('does not jump again when the day loads again', (tester) async {
      final clock = _Clock(DateTime(2026, 11, 1, 14, 30));
      final api = FakeApi({
        'GET /views/day/2026-11-01': {
          'date': '2026-11-01',
          'entries': many,
          'tasks': <Object?>[],
          'note': null,
        },
        'GET /connections': <Object?>[],
        'POST /notes/daily/2026-11-01/append': <String, Object?>{},
      });
      await pumpWithApi(
        tester,
        api,
        DailyScreen(initialDate: DateTime(2026, 11, 1)),
        overrides: [dailyClockProvider.overrideWithValue(() => clock.now)],
        size: const Size(800, 500),
      );
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(_list);
      expect(scrollable.position.pixels, greaterThan(0));
      // The user goes to the note, at the end of the page.
      await tester.ensureVisible(find.byKey(const Key('note-field')));
      await tester.pumpAndSettle();
      final where = scrollable.position.pixels;
      // A note makes the day load again.
      await tester.enterText(find.byKey(const Key('note-field')), 'Hello');
      await tester.tap(find.byKey(const Key('note-append-button')));
      await tester.pumpAndSettle();
      expect(api.where('GET /views/day/2026-11-01'), hasLength(2));
      // The list stays where the user is. It does not go back to the event.
      expect(scrollable.position.pixels, where);
    });

    testWidgets('the button Today brings the list to the next event',
        (tester) async {
      // Start on the day before, which is shown from the top.
      final clock = _Clock(DateTime(2026, 11, 1, 14, 30));
      await pumpWithApi(
        tester,
        FakeApi({
          'GET /views/day/2026-10-31': {
            'date': '2026-10-31',
            'entries': <Object?>[],
            'tasks': <Object?>[],
            'note': null,
          },
          'GET /views/day/2026-11-01': {
            'date': '2026-11-01',
            'entries': many,
            'tasks': <Object?>[],
            'note': null,
          },
          'GET /connections': <Object?>[],
        }),
        DailyScreen(initialDate: DateTime(2026, 10, 31)),
        overrides: [dailyClockProvider.overrideWithValue(() => clock.now)],
        size: const Size(800, 500),
      );
      await tester.pumpAndSettle();
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await tester.tap(find.byKey(const Key('today-button')));
      await tester.pumpAndSettle();
      final scroll = _top(tester, find.byKey(const Key('day-list')));
      expect(await offset(tester), greaterThan(0));
      expect(_top(tester, find.byKey(const Key('entry-e14'))) - scroll,
          lessThan(12));
    });
  });

  testWidgets('an event fades when its time passes, without a reload',
      (tester) async {
    final clock = await _pump(tester, [_event('a', 9, 10)],
        now: DateTime(2026, 11, 1, 9, 30));
    expect(find.byKey(const Key('entry-past-a')), findsNothing);
    clock.now = DateTime(2026, 11, 1, 10, 1);
    await tester.pump(const Duration(minutes: 1));
    expect(find.byKey(const Key('entry-past-a')), findsOneWidget);
  });
}
