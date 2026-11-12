import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/statistics/categories_card.dart';
import 'package:tefteri/theme/theme.dart';

import '../../support/fake_api.dart';
import 'stats_pump.dart';

final _day = DateTime(2026, 11, 4);

Map<String, Object?> _empty(String reason, String action,
        {String period = 'week'}) =>
    weekRoutes(
        summary: statisticsJson(
            period: period, empty: {'reason': reason, 'action': action}));

void main() {
  testWidgets('an empty period shows EmptyState, no bar and "Plan your week"',
      (tester) async {
    await pumpStats(tester, _empty('no_tasks', 'plan_week'),
        CategoriesCard(period: 'week', day: _day),
        prefs: hintsClosed);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('No tasks were completed this week.'), findsOneWidget);
    expect(find.byKey(const Key('proportion-bar')), findsNothing);
    expect(find.byKey(const Key('count-goal_aligned')), findsNothing);
    expect(find.text('Plan your week'), findsOneWidget);
    await tester.tap(find.text('Plan your week'));
    await tester.pumpAndSettle();
    expect(find.text('plan page'), findsOneWidget);
  });

  testWidgets('the empty message names the month and the year', (tester) async {
    await pumpStats(tester, _empty('no_tasks', 'plan_week', period: 'month'),
        CategoriesCard(period: 'month', day: _day),
        prefs: hintsClosed);
    expect(find.text('No tasks were completed this month.'), findsOneWidget);
    await pumpStats(tester, _empty('no_tasks', 'plan_week', period: 'year'),
        CategoriesCard(period: 'year', day: _day),
        prefs: hintsClosed);
    expect(find.text('No tasks were completed this year.'), findsOneWidget);
  });

  testWidgets('no labels: "Label your projects" opens the Projects page',
      (tester) async {
    await pumpStats(tester, _empty('no_labels', 'label_projects'),
        CategoriesCard(period: 'week', day: _day),
        prefs: hintsClosed);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.textContaining('No project has a label yet'), findsOneWidget);
    expect(find.byKey(const Key('proportion-bar')), findsNothing);
    await tester.tap(find.text('Label your projects'));
    await tester.pumpAndSettle();
    expect(find.text('projects page'), findsOneWidget);
  });

  testWidgets('the empty card still shows when it was last synced',
      (tester) async {
    await pumpStats(tester, _empty('no_tasks', 'plan_week'),
        CategoriesCard(period: 'week', day: _day),
        prefs: hintsClosed);
    expect(find.textContaining('Last synced'), findsOneWidget);
  });
}
