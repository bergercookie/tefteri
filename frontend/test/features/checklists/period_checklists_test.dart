import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/month/month_screen.dart';
import 'package:tefteri/features/weekly/weekly_api.dart';
import 'package:tefteri/features/weekly/weekly_screen.dart';
import 'package:tefteri/features/annual_review/annual_review_screen.dart';

import '../../support/fake_api.dart';
import '../weekly/weekly_fake.dart';
import '../month/month_fake.dart';

Map<String, Object?> _list(
        String kind, String start, List<(String, bool)> items) =>
    {
      'period_type': kind,
      'period_start': start,
      'items': [
        for (final (t, c) in items) {'text': t, 'checked': c},
      ],
      'done': items.where((i) => i.$2).length,
      'total': items.length,
    };

String _summary(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('checklist-summary'))).data!;

Future<FakeApi> _pumpWeekly(WidgetTester tester, Map<String, Object?> checklist,
    {double width = 1100}) async {
  final server = WeeklyServer();
  final api = FakeApi({
    ...server.allRoutes(),
    'GET /checklists/week/$weekKey': checklist,
    'PUT /checklists/week/$weekKey/items': (o) {
      final b = o.data as Map;
      return _list('week', weekKey, [
        for (final i in ['Clear the inbox', 'Check goals'])
          (i, i == b['text'] ? b['checked'] as bool : false),
      ]);
    },
  });
  await pumpWithApi(
    tester,
    api,
    WeeklyPlanningScreen(initialDate: DateTime(2030, 3, 6)),
    overrides: [weeklyPollIntervalProvider.overrideWithValue(null)],
  );
  if (width != 1100) {
    tester.view.physicalSize = Size(width, 2400);
    await tester.pumpAndSettle();
  }
  return api;
}

void main() {
  group('weekly planning', () {
    testWidgets('the checklist is next to the steps and ticks the planned week',
        (tester) async {
      final api = await _pumpWeekly(
          tester,
          _list('week', weekKey,
              [('Clear the inbox', false), ('Check goals', true)]));
      // The steps and the user's list are both on the screen, on every step.
      expect(find.text('Steps'), findsOneWidget);
      expect(find.byKey(const Key('check-projects')), findsOneWidget);
      expect(find.byKey(const Key('planning-checklist-week')), findsOneWidget);
      expect(find.text('Weekly checklist'), findsOneWidget);
      expect(_summary(tester), '1 of 2 done');

      await tester.tap(find.byKey(const Key('checklist-item-0')));
      await tester.pumpAndSettle();
      expect(api.where('PUT /checklists/week/$weekKey/items').single.data,
          {'text': 'Clear the inbox', 'checked': true});
      expect(_summary(tester), '1 of 2 done');
    });

    testWidgets('it stays when the user goes to another step', (tester) async {
      await _pumpWeekly(
          tester, _list('week', weekKey, [('Clear the inbox', false)]));
      await tester.tap(find.byKey(const Key('check-tasks')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('planning-checklist-week')), findsOneWidget);
      expect(find.text('Clear the inbox'), findsOneWidget);
    });

    testWidgets('without a list there is a hint to make one', (tester) async {
      await _pumpWeekly(tester, _list('week', weekKey, []));
      expect(find.byKey(const Key('checklist-hint')), findsOneWidget);
      expect(find.byKey(const Key('checklist-create')), findsOneWidget);
    });

    testWidgets('on a narrow screen it folds away above the step',
        (tester) async {
      await _pumpWeekly(
          tester, _list('week', weekKey, [('Clear the inbox', false)]),
          width: 560);
      expect(find.byKey(const Key('planning-checklist-week')), findsOneWidget);
      expect(_summary(tester), '0 of 1 done');
      expect(find.text('Clear the inbox'), findsNothing);
      await tester.tap(find.byKey(const Key('checklist-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Clear the inbox'), findsOneWidget);
    });

    testWidgets('a broken checklist does not break the planning',
        (tester) async {
      final server = WeeklyServer();
      await pumpWithApi(
        tester,
        FakeApi(
            {...server.allRoutes()}), // no /checklists route: it answers 404
        WeeklyPlanningScreen(initialDate: DateTime(2030, 3, 6)),
        overrides: [weeklyPollIntervalProvider.overrideWithValue(null)],
      );
      expect(find.byKey(const Key('check-projects')), findsOneWidget);
      expect(find.byKey(const Key('checklist-error')), findsOneWidget);
    });
  });

  group('month and year', () {
    testWidgets('the month page shows the monthly checklist', (tester) async {
      final api = MonthFakeApi(
        month: '2026-11',
        plan:
            monthlyJson(month: '2026-11', state: 'current', focusKnown: false),
        suggestions: monthlySuggestionsJson(fromMonth: null),
      );
      api.routes['GET /checklists/month/2026-11-01'] = _list(
          'month', '2026-11-01', [('Pay the bills', true), ('Archive', false)]);
      await pumpWithApi(
          tester, api, MonthScreen(initialDate: DateTime(2026, 11, 14)));
      expect(find.text('Monthly checklist'), findsOneWidget);
      expect(_summary(tester), '1 of 2 done');
      expect(find.text('Pay the bills'), findsOneWidget);
    });

    testWidgets(
        'the year page shows the annual checklist and a hint without one',
        (tester) async {
      final api = FakeApi({
        'GET /annual-review/2026': annualReviewJson(year: 2026),
        'GET /checklists/year/2026-01-01': _list('year', '2026-01-01', []),
      });
      await pumpWithApi(
          tester, api, const AnnualReviewScreen(initialYear: 2026));
      expect(find.text('Annual checklist'), findsOneWidget);
      expect(find.byKey(const Key('checklist-hint')), findsOneWidget);
      expect(find.textContaining('You have no annual checklist yet'),
          findsOneWidget);
    });

    testWidgets('moving to the next month loads that month\'s clean list',
        (tester) async {
      final api = MonthFakeApi(
        month: '2026-11',
        plan:
            monthlyJson(month: '2026-11', state: 'current', focusKnown: false),
        suggestions: monthlySuggestionsJson(fromMonth: null),
      );
      api.routes.addAll({
        'GET /monthly/2026-12':
            monthlyJson(month: '2026-12', state: 'future', focusKnown: false),
        'GET /monthly/2026-12/themes': monthlyPickerJson(),
        'GET /monthly/2026-12/suggestions':
            monthlySuggestionsJson(fromMonth: null),
        'GET /checklists/month/2026-11-01':
            _list('month', '2026-11-01', [('Pay the bills', true)]),
        'GET /checklists/month/2026-12-01':
            _list('month', '2026-12-01', [('Pay the bills', false)]),
      });
      await pumpWithApi(
          tester, api, MonthScreen(initialDate: DateTime(2026, 11, 14)));
      expect(_summary(tester), 'Done');
      await tester.tap(find.byKey(const Key('next-period')));
      await tester.pumpAndSettle();
      expect(api.where('GET /checklists/month/2026-12-01'), hasLength(1));
      expect(_summary(tester), '0 of 1 done');
    });
  });
}
