import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/features/settings/calendar_chooser_dialog.dart';
import 'package:tefteri/features/settings/connections_screen.dart';

import '../../support/fake_api.dart';

Map<String, Object?> _cal(String id, String name,
        {String? color, bool enabled = false, bool readOnly = false}) =>
    {
      'id': id,
      'remote_id': 'r$id',
      'name': name,
      'color': color,
      'enabled': enabled,
      'read_only': readOnly,
      'parent_remote_id': null,
    };

final _calendars = [
  _cal('k1', 'Personal', color: '#ff0000', enabled: true),
  _cal('k2', 'Family', color: '#00ff00'),
  _cal('k3', 'Holidays', readOnly: true),
];

Future<void> _open(WidgetTester tester, FakeApi api,
    {Size size = const Size(1000, 2400)}) async {
  await pumpWithApi(
    tester,
    api,
    Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          key: const Key('open'),
          onPressed: () => showCalendarChooser(context, connectionId: 'c1'),
          child: const Text('open'),
        ),
      ),
    ),
  );
  tester.view.physicalSize = size;
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
}

Color _dot(WidgetTester tester, String id) {
  final box = tester.widget<Container>(find.byKey(Key('calendar-dot-$id')));
  return (box.decoration! as BoxDecoration).color!;
}

void main() {
  testWidgets('lists calendars with colors and read-only labels',
      (tester) async {
    await _open(
        tester, FakeApi({'GET /connections/c1/containers': _calendars}));
    expect(find.byKey(const Key('calendar-chooser')), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Read only'), findsOneWidget);
    expect(_dot(tester, 'k1'), const Color(0xFFFF0000));
    expect(_dot(tester, 'k2'), const Color(0xFF00FF00));
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const Key('calendar-option-k1')))
            .value,
        isTrue);
    expect(find.byKey(const Key('calendar-chooser-filter')), findsNothing);
  });

  testWidgets('Save is off until a change and sends the chosen ids',
      (tester) async {
    final api = FakeApi({
      'GET /connections/c1/containers': _calendars,
      'PUT /connections/c1/containers/enabled': {
        'containers': _calendars,
        'sync': {'outcome': 'ok'},
      },
    });
    await _open(tester, api);
    FilledButton save() => tester
        .widget<FilledButton>(find.byKey(const Key('calendar-chooser-save')));
    expect(save().onPressed, isNull);
    await tester.tap(find.byKey(const Key('calendar-option-k2')));
    await tester.pump();
    expect(save().onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('calendar-chooser-save')));
    await tester.pumpAndSettle();
    expect(api.where('PUT /connections/c1/containers/enabled').single.data, {
      'container_ids': ['k1', 'k2']
    });
    expect(find.byKey(const Key('calendar-chooser')), findsNothing);
  });

  testWidgets('a failed sync shows the reason', (tester) async {
    final api = FakeApi({
      'GET /connections/c1/containers': _calendars,
      'PUT /connections/c1/containers/enabled': {
        'containers': _calendars,
        'sync': {'outcome': 'failed', 'reason': 'unreachable', 'detail': 'x'},
      },
    });
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('calendar-option-k3')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('calendar-chooser-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('connection-sync-failed')), findsOneWidget);
    expect(
        find.textContaining('The service is not reachable.'), findsOneWidget);
  });

  testWidgets('shows an error and an empty state', (tester) async {
    await _open(tester, FakeApi({}));
    expect(find.text('Cannot load the calendars.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('calendar-chooser-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  });

  testWidgets('shows an empty state without calendars', (tester) async {
    await _open(tester, FakeApi({'GET /connections/c1/containers': []}));
    expect(find.text('This account has no calendars.'), findsOneWidget);
  });

  testWidgets('shows loading while the list loads', (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _Slow();
    await tester.pumpWidget(ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: const MaterialApp(
          home: Scaffold(body: CalendarChooserDialog(connectionId: 'c1'))),
    ));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
      'filters when there are more than 8 calendars, no overflow at 360 px',
      (tester) async {
    final many = [
      for (var i = 0; i < 10; i++)
        _cal('m$i', 'A very long calendar name number $i for a phone',
            readOnly: i.isEven),
    ];
    await _open(tester, FakeApi({'GET /connections/c1/containers': many}),
        size: const Size(360, 640));
    expect(find.byKey(const Key('calendar-chooser-filter')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('calendar-chooser-filter')), 'number 3');
    await tester.pump();
    expect(find.byKey(const Key('calendar-option-m3')), findsOneWidget);
    expect(find.byKey(const Key('calendar-option-m4')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('Connections screen', () {
    final conns = [
      {
        ...connectionJson('c1', 'calendar', 'Work'),
        'provider': 'google_calendar',
      },
      connectionJson('c2', 'tasks', 'Tasks'),
    ];
    final routes = <String, Object?>{
      'GET /connections': conns,
      'GET /sync/status': {'last_sync_at': null, 'results': []},
      'GET /connections/c1/containers': _calendars,
    };

    testWidgets('has the button and the count only for Google', (tester) async {
      await pumpWithApi(tester, FakeApi(routes), const ConnectionsScreen());
      expect(find.byKey(const Key('choose-calendars-c1')), findsOneWidget);
      expect(find.byKey(const Key('choose-calendars-c2')), findsNothing);
      expect(find.textContaining('1 of 3 calendars'), findsOneWidget);
      await tester.tap(find.byKey(const Key('choose-calendars-c1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar-chooser')), findsOneWidget);
    });

    testWidgets('opens the chooser once for the choose parameter',
        (tester) async {
      await pumpWithApi(
          tester, FakeApi(routes), const ConnectionsScreen(choose: 'c1'));
      expect(find.byKey(const Key('calendar-chooser')), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar-chooser-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar-chooser')), findsNothing);
    });
  });
}

class _Slow implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<List<int>>? s, Future<void>? c) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    return ResponseBody.fromString('[]', 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}
