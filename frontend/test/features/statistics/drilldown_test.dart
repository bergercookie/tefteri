import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/statistics/categories_card.dart';
import 'package:tefteri/features/statistics/drilldown_screen.dart';

import '../../support/fake_api.dart';
import 'stats_pump.dart';

final _day = DateTime(2026, 11, 4);

final _tasks = [
  statTaskJson('o1', 'Fix the gutter', category: 'off_plan', project: 'Home'),
  statTaskJson('o2', 'Call the plumber', category: 'off_plan', project: 'Home'),
  statTaskJson('m1', 'Take out the bins',
      category: 'maintenance', project: 'Chores'),
  statTaskJson('g1', 'Write the spec',
      category: 'goal_aligned', project: 'Website'),
  statTaskJson('h1', 'Old thing', category: 'hidden', project: 'Archive'),
];

Map<String, Object?> _routes() => weekRoutes(
    summary:
        statisticsJson(goalAligned: 1, maintenance: 1, offPlan: 2, hidden: 1),
    tasks: _tasks);

Widget _card() => CategoriesCard(period: 'week', day: _day);

void main() {
  testWidgets('a tap on a count opens the list with the right filter',
      (tester) async {
    final api = await pumpStats(tester, _routes(), _card(), prefs: hintsClosed);
    await tester.tap(find.byKey(const Key('count-off_plan')));
    await tester.pumpAndSettle();
    expect(find.byType(DrilldownScreen), findsOneWidget);
    final q = api.where('GET /statistics/tasks').last.query;
    expect(q['period'], 'week');
    expect(q['day'], '2026-11-02');
    expect(q['category'], 'off_plan');
    expect(find.text('Fix the gutter'), findsOneWidget);
    expect(find.text('Call the plumber'), findsOneWidget);
    expect(find.text('Take out the bins'), findsNothing);
    expect(find.byKey(const Key('drilldown-title')), findsOneWidget);
    expect(find.text('Off-plan'), findsWidgets);
  });

  testWidgets('a tap on a bar segment opens that category', (tester) async {
    final api = await pumpStats(tester, _routes(), _card(), prefs: hintsClosed);
    await tester.tap(find.byKey(const Key('bar-segment-maintenance')));
    await tester.pumpAndSettle();
    expect(api.where('GET /statistics/tasks').last.query['category'],
        'maintenance');
    expect(find.text('Take out the bins'), findsOneWidget);
    expect(find.text('Fix the gutter'), findsNothing);
  });

  testWidgets('a tap on the hidden line lists the hidden tasks',
      (tester) async {
    final api = await pumpStats(tester, _routes(), _card(), prefs: hintsClosed);
    await tester.tap(find.byKey(const Key('hidden-line')));
    await tester.pumpAndSettle();
    expect(api.where('GET /statistics/tasks').last.query['category'], 'hidden');
    expect(find.text('Old thing'), findsOneWidget);
    expect(find.textContaining('ignored projects'), findsWidgets);
  });

  testWidgets('back returns to the card', (tester) async {
    await pumpStats(tester, _routes(), _card(), prefs: hintsClosed);
    await tester.tap(find.byKey(const Key('count-goal_aligned')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('categories-card')), findsNothing);
    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('categories-card')), findsOneWidget);
  });

  testWidgets('the list says it is live', (tester) async {
    await pumpStats(tester, _routes(), _card(), prefs: hintsClosed);
    await tester.tap(find.byKey(const Key('count-off_plan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-note')), findsOneWidget);
    expect(find.textContaining('live list'), findsOneWidget);
  });

  testWidgets('the order can change to newest first', (tester) async {
    final api = await pumpStats(tester, _routes(), _card(), prefs: hintsClosed);
    await tester.tap(find.byKey(const Key('count-off_plan')));
    await tester.pumpAndSettle();
    // The list opens grouped by project.
    expect(api.where('GET /statistics/tasks').last.query['order'], 'project');
    expect(find.byKey(const Key('group-Home')), findsOneWidget);
    await tester.tap(find.byKey(const Key('order-newest')));
    await tester.pumpAndSettle();
    expect(api.where('GET /statistics/tasks').last.query['order'], 'newest');
    expect(find.byKey(const Key('group-Home')), findsNothing);
  });

  testWidgets('the screen can be used with the keyboard', (tester) async {
    final api = await pumpStats(tester, _routes(), _card(), prefs: hintsClosed);
    // The first stop is the first count; Enter opens its list.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(DrilldownScreen), findsOneWidget);
    expect(api.where('GET /statistics/tasks').last.query['category'],
        'goal_aligned');
    // The counts and the segments are buttons for a screen reader too.
    final handle = tester.ensureSemantics();
    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    final node =
        tester.getSemantics(find.byKey(const Key('count-maintenance')));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('a month opens with the month filter', (tester) async {
    final api = await pumpStats(
        tester,
        weekRoutes(
            summary: statisticsJson(
                period: 'month',
                start: '2026-11-01',
                end: '2026-12-01',
                offPlan: 2),
            tasks: _tasks),
        CategoriesCard(period: 'month', day: DateTime(2026, 11, 15)),
        prefs: hintsClosed);
    await tester.tap(find.byKey(const Key('count-off_plan')));
    await tester.pumpAndSettle();
    final q = api.where('GET /statistics/tasks').last.query;
    expect(q['period'], 'month');
    expect(q['day'], '2026-11-01');
  });

  testWidgets('a link that makes no sense shows a way back', (tester) async {
    await pumpStats(
        tester,
        _routes(),
        const DrilldownScreen(
            period: 'decade', day: '2026-11-02', category: null, order: 'x'),
        scroll: false);
    expect(find.text('This list cannot be opened.'), findsOneWidget);
  });
}
