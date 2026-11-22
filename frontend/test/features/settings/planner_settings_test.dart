import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/settings/planner_settings_card.dart';

import '../../support/fake_api.dart';

bool _on(WidgetTester tester) => tester
    .widget<SwitchListTile>(find.byKey(const Key('random-time-switch')))
    .value;

void main() {
  testWidgets('the switch is off by default and saves a change',
      (tester) async {
    var stored = false;
    final api = FakeApi({
      'GET /me/settings': (_) => {'random_time_on_date_drop': stored},
      'PATCH /me/settings': (o) {
        stored = (o.data as Map)['random_time_on_date_drop'] as bool;
        return {'random_time_on_date_drop': stored};
      },
    });
    await pumpWithApi(tester, api, const Scaffold(body: PlannerSettingsCard()));
    expect(_on(tester), isFalse);

    await tester.tap(find.byKey(const Key('random-time-switch')));
    await tester.pumpAndSettle();
    expect(api.where('PATCH /me/settings').single.data,
        {'random_time_on_date_drop': true});
    expect(_on(tester), isTrue); // reloaded from the server

    await tester.tap(find.byKey(const Key('random-time-switch')));
    await tester.pumpAndSettle();
    expect(_on(tester), isFalse);
  });

  testWidgets('a failed save shows the message and keeps the old value',
      (tester) async {
    final api = FakeApi({
      'GET /me/settings': {'random_time_on_date_drop': false},
      'PATCH /me/settings': const ApiFailure(500, 'Could not save.', 'error'),
    });
    await pumpWithApi(tester, api, const Scaffold(body: PlannerSettingsCard()));
    await tester.tap(find.byKey(const Key('random-time-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Could not save.'), findsOneWidget);
    expect(_on(tester), isFalse);
  });

  testWidgets('a load error is shown with a retry button', (tester) async {
    final api = FakeApi({});
    await pumpWithApi(tester, api, const Scaffold(body: PlannerSettingsCard()));
    expect(find.byKey(const Key('planner-settings-error')), findsOneWidget);
  });

  testWidgets('the card keeps a readable width on a wide window',
      (tester) async {
    final api = FakeApi({
      'GET /me/settings': {'random_time_on_date_drop': false},
    });
    // pumpWithApi uses a 1000 wide surface; make it wider than a laptop screen
    await pumpWithApi(tester, api, const Scaffold(body: PlannerSettingsCard()));
    tester.view.physicalSize = const Size(1800, 1400);
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byType(Card));
    expect(card.width, lessThanOrEqualTo(plannerSettingsCardWidth));
    expect(card.left, lessThan(40)); // sits at the left edge, not centered
  });

  testWidgets('the default reminder is 15 minutes and saves a change',
      (tester) async {
    var stored = 15;
    final api = FakeApi({
      'GET /me/settings': (_) => {
            'random_time_on_date_drop': false,
            'default_reminder_minutes': stored,
          },
      'PATCH /me/settings': (o) {
        stored = (o.data as Map)['default_reminder_minutes'] as int;
        return {
          'random_time_on_date_drop': false,
          'default_reminder_minutes': stored,
        };
      },
    });
    await pumpWithApi(tester, api, const Scaffold(body: PlannerSettingsCard()));
    DropdownButton<int> select() => tester.widget<DropdownButton<int>>(
        find.byKey(const Key('default-reminder-select')));
    expect(select().value, 15);

    await tester.tap(find.byKey(const Key('default-reminder-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 hour before').last);
    await tester.pumpAndSettle();

    // Only the changed setting is sent.
    expect(api.where('PATCH /me/settings').single.data,
        {'default_reminder_minutes': 60});
    expect(select().value, 60); // reloaded from the server
  });

  testWidgets('the event reminder is 15 minutes and saves a change by itself',
      (tester) async {
    var stored = 15;
    final api = FakeApi({
      'GET /me/settings': (_) => {
            'random_time_on_date_drop': false,
            'default_reminder_minutes': 15,
            'event_reminder_minutes': stored,
          },
      'PATCH /me/settings': (o) {
        stored = (o.data as Map)['event_reminder_minutes'] as int;
        return {
          'random_time_on_date_drop': false,
          'default_reminder_minutes': 15,
          'event_reminder_minutes': stored,
        };
      },
    });
    await pumpWithApi(tester, api, const Scaffold(body: PlannerSettingsCard()));
    DropdownButton<int> select(String key) =>
        tester.widget<DropdownButton<int>>(find.byKey(Key(key)));
    // The task and the event each have their own time, both 15 minutes.
    expect(select('default-reminder-select').value, 15);
    expect(select('event-reminder-select').value, 15);
    expect(find.text('Remind me of a task'), findsOneWidget);
    expect(find.text('Remind me of an event'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('event-reminder-select')));
    await tester.tap(find.byKey(const Key('event-reminder-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 minutes before').last);
    await tester.pumpAndSettle();

    expect(api.where('PATCH /me/settings').single.data,
        {'event_reminder_minutes': 30});
    expect(select('event-reminder-select').value, 30);
    expect(select('default-reminder-select').value, 15); // not changed
  });

  testWidgets('an offset that is not in the list is still shown',
      (tester) async {
    final api = FakeApi({
      'GET /me/settings': {
        'random_time_on_date_drop': false,
        'default_reminder_minutes': 45,
      },
    });
    await pumpWithApi(tester, api, const Scaffold(body: PlannerSettingsCard()));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DropdownButton<int>>(
                find.byKey(const Key('default-reminder-select')))
            .value,
        45);
    expect(find.text('45 minutes before'), findsOneWidget);
  });

  group('the calendar for new events', () {
    Map<String, Object?> containers() => {
          'GET /connections': [
            connectionJson('c2', 'calendar', 'Work calendar'),
          ],
          'GET /connections/c2/containers': [
            {'id': 'k1', 'name': 'Work', 'enabled': true, 'read_only': false},
            {'id': 'k2', 'name': 'Home', 'enabled': true, 'read_only': false},
            {'id': 'k3', 'name': 'Shared', 'enabled': true, 'read_only': true},
          ],
        };

    testWidgets('starts on last used, lists the calendars that can change',
        (tester) async {
      final api = FakeApi({
        ...containers(),
        'GET /me/settings': {
          'random_time_on_date_drop': false,
          'default_event_container_id': null,
        },
      });
      await pumpWithApi(
          tester, api, const Scaffold(body: PlannerSettingsCard()));
      await tester.pumpAndSettle();
      final select = find.byKey(const Key('default-event-calendar-select'));
      expect(tester.widget<DropdownButton<String?>>(select).value, isNull);
      expect(find.text('Last used'), findsOneWidget);
      await tester.tap(select);
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsWidgets);
      expect(find.text('Home'), findsWidgets);
      expect(find.text('Shared'), findsNothing); // read-only
    });

    testWidgets('saves the choice and saves null for last used',
        (tester) async {
      String? stored;
      final api = FakeApi({
        ...containers(),
        'GET /me/settings': (_) => {
              'random_time_on_date_drop': false,
              'default_event_container_id': stored,
            },
        'PATCH /me/settings': (o) {
          stored = (o.data as Map)['default_event_container_id'] as String?;
          return {
            'random_time_on_date_drop': false,
            'default_event_container_id': stored,
          };
        },
      });
      await pumpWithApi(
          tester, api, const Scaffold(body: PlannerSettingsCard()));
      await tester.pumpAndSettle();
      final select = find.byKey(const Key('default-event-calendar-select'));
      await tester.tap(select);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      expect(api.where('PATCH /me/settings').single.data,
          {'default_event_container_id': 'k2'});
      expect(tester.widget<DropdownButton<String?>>(select).value, 'k2');

      await tester.tap(select);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last used').last);
      await tester.pumpAndSettle();
      expect(api.where('PATCH /me/settings').last.data,
          {'default_event_container_id': null});
      expect(tester.widget<DropdownButton<String?>>(select).value, isNull);
    });
  });

  invitees();
}

/// Lets a save and the reload that follows it finish.
Future<void> _saved(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void invitees() {
  group('standard invitees', () {
    FakeApi api(List<String> stored, {void Function(Object?)? onPatch}) =>
        FakeApi({
          'GET /me/settings': (_) => {
                'random_time_on_date_drop': false,
                'event_invitees': stored,
              },
          'PATCH /me/settings': (o) {
            final list =
                ((o.data as Map)['event_invitees'] as List).cast<String>();
            stored
              ..clear()
              ..addAll(list);
            onPatch?.call(list);
            return {
              'random_time_on_date_drop': false,
              'event_invitees': stored,
            };
          },
          'GET /connections': <Object?>[],
        });

    testWidgets('adds a person with Enter and saves the whole list',
        (tester) async {
      final fake = api(['sam@example.com']);
      await pumpWithApi(
          tester,
          fake,
          const Scaffold(
              body: SingleChildScrollView(child: PlannerSettingsCard())));
      expect(find.byKey(const Key('invitee-sam@example.com')), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('invitee-field')), ' kim@example.org ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _saved(tester);
      expect(fake.where('PATCH /me/settings').single.data, {
        'event_invitees': ['sam@example.com', 'kim@example.org']
      });
      expect(find.byKey(const Key('invitee-kim@example.org')), findsOneWidget);
    });

    testWidgets('refuses a text that is not an address', (tester) async {
      final fake = api([]);
      await pumpWithApi(
          tester,
          fake,
          const Scaffold(
              body: SingleChildScrollView(child: PlannerSettingsCard())));
      expect(find.byKey(const Key('invitees-empty')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('invitee-field')), 'sam');
      await tester.tap(find.byKey(const Key('invitee-add')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Type an e-mail address'), findsOneWidget);
      expect(fake.where('PATCH /me/settings'), isEmpty);
    });

    testWidgets('removes a person with the cross of the chip', (tester) async {
      final fake = api(['sam@example.com', 'kim@example.org']);
      await pumpWithApi(
          tester,
          fake,
          const Scaffold(
              body: SingleChildScrollView(child: PlannerSettingsCard())));
      await tester.tap(find.descendant(
          of: find.byKey(const Key('invitee-sam@example.com')),
          matching: find.byIcon(Icons.clear)));
      await _saved(tester);
      expect(fake.where('PATCH /me/settings').single.data, {
        'event_invitees': ['kim@example.org']
      });
    });

    testWidgets('a repeat of an address is not added twice', (tester) async {
      final fake = api(['sam@example.com']);
      await pumpWithApi(
          tester,
          fake,
          const Scaffold(
              body: SingleChildScrollView(child: PlannerSettingsCard())));
      await tester.enterText(
          find.byKey(const Key('invitee-field')), 'Sam@Example.com');
      await tester.tap(find.byKey(const Key('invitee-add')));
      await tester.pumpAndSettle();
      expect(fake.where('PATCH /me/settings'), isEmpty);
    });
  });
}
