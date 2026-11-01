import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/context_filter.dart';
import 'package:tefteri/features/calendar/calendar_screen.dart';
import 'package:tefteri/features/daily/daily_screen.dart';

import '../support/fake_api.dart';

void main() {
  test('queryParameters uses the enum name', () {
    expect(ContextFilter.all.queryParameters, {'context': 'all'});
    expect(ContextFilter.life.queryParameters, {'context': 'life'});
    expect(ContextFilter.work.queryParameters, {'context': 'work'});
  });

  testWidgets('marker shows only when context is null', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          ContextMarker(itemContext: null),
          ContextMarker(itemContext: 'work'),
        ]),
      ),
    ));
    expect(find.byKey(const Key('unclassified-marker')), findsOneWidget);
    expect(find.text('Unclassified'), findsOneWidget);
  });

  testWidgets('daily view reloads with the selected context', (tester) async {
    final api = FakeApi({
      'GET /views/day/2026-11-01': {
        'date': '2026-11-01',
        'entries': [],
        'tasks': [],
        'note': null,
      },
      'GET /connections': [],
    });
    await pumpWithApi(
        tester, api, DailyScreen(initialDate: DateTime(2026, 11, 1)));
    await tester.tap(find.text('work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('life'));
    await tester.pumpAndSettle();
    final seen = api
        .where('GET /views/day/2026-11-01')
        .map((r) => r.query['context'])
        .toList();
    expect(seen, ['all', 'work', 'life']);
  });

  testWidgets('calendar view reloads with the selected context',
      (tester) async {
    final api = FakeApi({'GET /calendar': [], 'GET /tasks': []});
    await pumpWithApi(
        tester, api, CalendarScreen(initialDate: DateTime(2026, 11, 4)));
    await tester.tap(find.text('work'));
    await tester.pumpAndSettle();
    expect(api.where('GET /calendar').map((r) => r.query['context']),
        ['all', 'work']);
    expect(api.where('GET /tasks').map((r) => r.query['context']),
        ['all', 'work']);
  });
}
