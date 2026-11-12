import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/daily/daily_screen.dart';
import 'package:tefteri/core/periods.dart';
import 'package:tefteri/features/month/month_screen.dart';
import 'package:tefteri/features/planner/planner_screen.dart';
import 'package:tefteri/features/week/week_screen.dart';
import 'package:tefteri/features/year/year_screen.dart';
import 'package:tefteri/core/planning_models.dart';

import 'features/planner/planner_helpers.dart';
import 'support/fake_api.dart';
import 'features/month/month_fake.dart';

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  final now = DateTime.now();

  testWidgets('Week: Today returns to the current week', (tester) async {
    await pumpWithApi(
        tester, FakeApi({}), WeekScreen(initialDate: DateTime(2020, 3, 4)));
    expect(_text(tester, 'period-label'), 'Week of 2020-03-02');
    await tester.tap(find.byKey(const Key('today-button')));
    await tester.pumpAndSettle();
    expect(
        _text(tester, 'period-label'), 'Week of ${dateKey(weekStartOf(now))}');
  });

  testWidgets('Month: Today returns to the current month', (tester) async {
    final oldMonth = MonthFakeApi(
      month: '2020-03',
      plan: monthlyJson(month: '2020-03', state: 'past', focusKnown: false),
    );
    final currentMonth =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    oldMonth.routes['GET /monthly/$currentMonth'] =
        monthlyJson(month: currentMonth, state: 'current', focusKnown: false);
    oldMonth.routes['GET /monthly/$currentMonth/themes'] = monthlyPickerJson();
    oldMonth.routes['GET /monthly/$currentMonth/suggestions'] =
        monthlySuggestionsJson(fromMonth: null);
    await pumpWithApi(
        tester, oldMonth, MonthScreen(initialDate: DateTime(2020, 3, 4)));
    expect(_text(tester, 'period-label'), '${monthName(3)} 2020');
    await tester.tap(find.byKey(const Key('today-button')));
    await tester.pumpAndSettle();
    expect(
        _text(tester, 'period-label'), '${monthName(now.month)} ${now.year}');
  });

  testWidgets('Year: Today returns to the current year', (tester) async {
    await pumpWithApi(tester, FakeApi({}), const YearScreen(initialYear: 2020));
    expect(_text(tester, 'period-label'), '2020');
    await tester.tap(find.byKey(const Key('today-button')));
    await tester.pumpAndSettle();
    expect(_text(tester, 'period-label'), '${now.year}');
  });

  testWidgets('Day: Today returns to the current day', (tester) async {
    await pumpWithApi(
        tester, FakeApi({}), DailyScreen(initialDate: DateTime(2020, 3, 4)));
    expect(find.text('2020-03-04'), findsOneWidget);
    await tester.tap(find.byKey(const Key('today-button')));
    await tester.pumpAndSettle();
    expect(find.text(dateKey(now)), findsOneWidget);
    expect(find.text('2020-03-04'), findsNothing);
  });

  testWidgets('Planner: Today shows the week of today and loads it',
      (tester) async {
    final api = plannerApi();
    await pumpWithApi(
        tester, api, PlannerScreen(initialDate: DateTime(2020, 3, 4)));
    expect(_text(tester, 'week-label'), 'Week of 2020-03-02');
    await tester.tap(find.byKey(const Key('today-button')));
    await settle(tester);
    expect(_text(tester, 'week-label'), 'Week of ${dateKey(weekStartOf(now))}');
    expect(api.where('GET /calendar').last.query['from'],
        weekStartOf(now).toUtc().toIso8601String());
  });

  testWidgets('Planner: Today scrolls the grid to the current time',
      (tester) async {
    final fixed = DateTime(2026, 11, 4, 15, 0);
    await pumpWithApi(tester, plannerApi(),
        PlannerScreen(initialDate: DateTime(2026, 10, 14), clock: () => fixed));
    // another week: the grid shows the morning, the red line is not there
    expect(find.byKey(const Key('now-indicator')), findsNothing);
    await tester.tap(find.byKey(const Key('today-button')));
    await settle(tester);
    final grid = tester.getRect(find.byKey(const Key('time-grid')));
    final line = tester.getCenter(find.byKey(const Key('now-indicator')));
    expect(grid.contains(line), isTrue);
  });

  testWidgets('Today does nothing harmful when already on today',
      (tester) async {
    await pumpWithApi(tester, FakeApi({}), YearScreen(initialYear: now.year));
    await tester.tap(find.byKey(const Key('today-button')));
    await tester.pumpAndSettle();
    expect(_text(tester, 'period-label'), '${now.year}');
  });
}
