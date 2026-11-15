import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/core/auth_controller.dart';
import 'package:tefteri/core/event_input.dart';
import 'package:tefteri/core/shortcuts/app_shortcuts.dart';
import 'package:tefteri/core/shortcuts/keymap.dart';
import 'package:tefteri/features/planner/new_event_dialog.dart';

import '../support/fake_api.dart';

class _Auth extends AuthController {
  _Auth(super.ref, {required bool signedIn}) {
    state = AuthState(signedIn: signedIn);
  }
}

late FakeApi _api;

Map<String, Object?> _routes({String? defaultCalendar}) => {
      'GET /connections': [
        connectionJson('c1', 'calendar', 'Work account'),
      ],
      'GET /connections/c1/containers': [
        {'id': 'k1', 'name': 'Home', 'enabled': true, 'read_only': false},
        {'id': 'k2', 'name': 'Work', 'enabled': true, 'read_only': false},
      ],
      'GET /me/settings': {
        'random_time_on_date_drop': false,
        'default_event_container_id': defaultCalendar,
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
    };

Future<void> _pump(WidgetTester tester,
    {bool signedIn = true, String? defaultCalendar, String route = '/'}) async {
  final router = GoRouter(initialLocation: route, routes: [
    for (final path in ['/', '/week', '/daily'])
      GoRoute(
        path: path,
        builder: (_, __) => const Scaffold(
            body:
                Column(children: [Text('page'), TextField(key: Key('field'))])),
      ),
  ]);
  _api = FakeApi(_routes(defaultCalendar: defaultCalendar));
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = _api;
  final container = ProviderContainer(overrides: [
    dioProvider.overrideWithValue(dio),
    authControllerProvider
        .overrideWith((ref) => _Auth(ref, signedIn: signedIn)),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppShortcuts(router: router, child: child!),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _shiftN(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyN, character: 'N');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, {String? defaultCalendar}) async {
  await _pump(tester, defaultCalendar: defaultCalendar);
  await _shiftN(tester);
  expect(find.byKey(const Key('new-event-dialog')), findsOneWidget);
}

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pump();
}

bool _canCreate(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const Key('new-event-create')))
        .onPressed !=
    null;

Map<Object?, Object?> _created() =>
    _api.where('POST /calendar/entries').single.data! as Map;

DateTime _at(Map<Object?, Object?> body, String field) =>
    DateTime.parse('${body[field]}').toLocal();

void main() {
  test('Shift+N is in the keymap and does not clash with N', () {
    final s = appShortcuts.firstWhere((s) => s.keys == 'Shift+N');
    expect(s.description, 'Schedule a new calendar event');
    expect(s.intent, isA<NewEventIntent>());
    expect(appShortcuts.where((s) => s.intent is NewTaskIntent), hasLength(1));
  });

  testWidgets('Shift+N opens the new event dialog from every page',
      (tester) async {
    for (final route in ['/', '/week', '/daily']) {
      await _pump(tester, route: route);
      await _shiftN(tester);
      expect(find.byKey(const Key('new-event-dialog')), findsOneWidget,
          reason: route);
      expect(find.byKey(const Key('new-task-dialog')), findsNothing);
    }
  });

  testWidgets('plain N still opens the task dialog', (tester) async {
    await _pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN, character: 'n');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-task-dialog')), findsOneWidget);
    expect(find.byKey(const Key('new-event-dialog')), findsNothing);
  });

  testWidgets('Shift+N typed in a text field is a letter', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    await _shiftN(tester);
    expect(find.byKey(const Key('new-event-dialog')), findsNothing);
  });

  testWidgets('Shift+N does nothing while signed out', (tester) async {
    await _pump(tester, signedIn: false);
    await _shiftN(tester);
    expect(find.byKey(const Key('new-event-dialog')), findsNothing);
  });

  testWidgets('the help overlay lists Shift+N', (tester) async {
    await _pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shortcut-Shift+N')), findsOneWidget);
    expect(find.text('Schedule a new calendar event'), findsOneWidget);
  });

  testWidgets('it starts on the next full hour for one hour', (tester) async {
    await _open(tester);
    final start = parseTime(_text(tester, 'new-event-start'))!;
    expect(start.minute, 0);
    expect(parseDay(_text(tester, 'new-event-date')), isNotNull);
    expect(_text(tester, 'new-event-length'), '1h');
  });

  group('typing', () {
    testWidgets('YYYYMMDD sets the day and keeps the time', (tester) async {
      await _open(tester);
      final time = _text(tester, 'new-event-start');
      await _type(tester, 'new-event-date', '20271224');
      expect(_text(tester, 'new-event-start'), time);
      await _type(tester, 'new-event-title', 'Party');
      await tester.tap(find.byKey(const Key('new-event-create')));
      await tester.pumpAndSettle();
      final start = _at(_created(), 'start');
      expect(
          DateTime(start.year, start.month, start.day), DateTime(2027, 12, 24));
      expect(formatTime(TimeOfDay.fromDateTime(start)), time);
    });

    testWidgets('YYYYMMDDTHHmm in the day field sets the time too',
        (tester) async {
      await _open(tester);
      await _type(tester, 'new-event-date', '20271224T1845');
      expect(_text(tester, 'new-event-date'), '2027-12-24');
      expect(_text(tester, 'new-event-start'), '18:45');
    });

    testWidgets('YYYYMMDDTHHmm in the time field sets the day too',
        (tester) async {
      await _open(tester);
      await _type(tester, 'new-event-start', '20271224T0730');
      expect(_text(tester, 'new-event-date'), '2027-12-24');
      expect(_text(tester, 'new-event-start'), '07:30');
    });

    testWidgets('the time, the length and the end follow what is typed',
        (tester) async {
      await _open(tester);
      await _type(tester, 'new-event-date', '20271224');
      await _type(tester, 'new-event-start', '2230');
      await _type(tester, 'new-event-length', '1h30');
      expect(find.text('Ends 2027-12-24 00:00'), findsNothing);
      expect(find.text('Ends 2027-12-25 00:00'), findsOneWidget);
      await _type(tester, 'new-event-title', 'Late');
      await tester.tap(find.byKey(const Key('new-event-create')));
      await tester.pumpAndSettle();
      final body = _created();
      expect(_at(body, 'start'), DateTime(2027, 12, 24, 22, 30));
      expect(_at(body, 'end'), DateTime(2027, 12, 25));
    });

    testWidgets('a value that is not valid shows the format and stops Add',
        (tester) async {
      await _open(tester);
      await _type(tester, 'new-event-title', 'x');
      expect(_canCreate(tester), isTrue);
      await _type(tester, 'new-event-date', '20271399');
      expect(find.text('Type the day as YYYYMMDD'), findsOneWidget);
      expect(_canCreate(tester), isFalse);
      await _type(tester, 'new-event-date', '20271224');
      await _type(tester, 'new-event-start', '2575');
      expect(find.text('Type the time as HHmm'), findsOneWidget);
      expect(_canCreate(tester), isFalse);
      await _type(tester, 'new-event-start', '0900');
      await _type(tester, 'new-event-length', 'soon');
      expect(find.textContaining('Type minutes or hours'), findsOneWidget);
      expect(_canCreate(tester), isFalse);
      await _type(tester, 'new-event-length', '45m');
      expect(_canCreate(tester), isTrue);
    });

    testWidgets('a typed value is written in the standard form on leaving',
        (tester) async {
      await _open(tester);
      await _type(tester, 'new-event-start', '930');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(_text(tester, 'new-event-start'), '09:30');
    });

    testWidgets('all day hides the time and the length', (tester) async {
      await _open(tester);
      await tester.tap(find.byKey(const Key('new-event-all-day')));
      await tester.pump();
      expect(find.byKey(const Key('new-event-start')), findsNothing);
      expect(find.byKey(const Key('new-event-length')), findsNothing);
      await _type(tester, 'new-event-date', '20271224');
      await _type(tester, 'new-event-title', 'Away');
      await tester.tap(find.byKey(const Key('new-event-create')));
      await tester.pumpAndSettle();
      final body = _created();
      expect(body['all_day'], true);
      expect(_at(body, 'start'), DateTime(2027, 12, 24));
      expect(_at(body, 'end'), DateTime(2027, 12, 25));
    });
  });

  group('pickers', () {
    testWidgets('the day picker fills the day field', (tester) async {
      await _open(tester);
      await _type(tester, 'new-event-date', '20271224');
      await tester.tap(find.byKey(const Key('new-event-date-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('25'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(_text(tester, 'new-event-date'), '2027-12-25');
    });

    testWidgets('the time picker fills the time field', (tester) async {
      await _open(tester);
      await _type(tester, 'new-event-start', '0915');
      await tester.tap(find.byKey(const Key('new-event-start-pick')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(_text(tester, 'new-event-start'), '09:15');
    });

    testWidgets('the length button offers common lengths', (tester) async {
      await _open(tester);
      await tester.tap(find.byKey(const Key('new-event-length-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-event-length-2h')));
      await tester.pumpAndSettle();
      expect(_text(tester, 'new-event-length'), '2h');
    });
  });

  group('the calendar', () {
    String? chosen(WidgetTester tester) => tester
        .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('new-event-calendar')))
        .initialValue;

    testWidgets('starts in the first calendar when nothing is chosen',
        (tester) async {
      await _open(tester);
      expect(chosen(tester), 'k1');
    });

    testWidgets('starts in the calendar chosen in the settings',
        (tester) async {
      await _open(tester, defaultCalendar: 'k2');
      expect(chosen(tester), 'k2');
      await _type(tester, 'new-event-title', 'Dentist');
      await tester.tap(find.byKey(const Key('new-event-create')));
      await tester.pumpAndSettle();
      expect(_created()['container_id'], 'k2');
    });

    testWidgets(
        'the setting wins over the last used calendar, which wins '
        'over the first', (tester) async {
      await _pump(tester, defaultCalendar: 'k1');
      final container =
          ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(lastEventCalendarProvider.notifier).state = 'k2';
      await _shiftN(tester);
      expect(chosen(tester), 'k1');
    });

    testWidgets('the last used calendar is the start when nothing is chosen',
        (tester) async {
      await _pump(tester);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(lastEventCalendarProvider.notifier).state = 'k2';
      await _shiftN(tester);
      expect(chosen(tester), 'k2');
    });

    testWidgets('a setting that names a calendar that is gone is ignored',
        (tester) async {
      await _open(tester, defaultCalendar: 'gone');
      expect(chosen(tester), 'k1');
    });
  });
}
