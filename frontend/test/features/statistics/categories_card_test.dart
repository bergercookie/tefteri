import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/planning_models.dart';
import 'package:tefteri/features/statistics/categories_card.dart';

import '../../support/fake_api.dart';
import 'stats_pump.dart';

final _day = DateTime(2026, 11, 4);

Widget _card([String period = 'week']) =>
    CategoriesCard(period: period, day: _day);

Finder _in(String key, Finder matching) =>
    find.descendant(of: find.byKey(Key(key)), matching: matching);

void main() {
  testWidgets('shows three counts, the bar, the percentages and the counts',
      (tester) async {
    final api = await pumpStats(
      tester,
      weekRoutes(
          summary: statisticsJson(goalAligned: 12, maintenance: 5, offPlan: 3)),
      _card(),
      prefs: hintsClosed,
    );
    expect(api.where('GET /statistics').single.query,
        {'period': 'week', 'day': '2026-11-02'});
    expect(_in('count-goal_aligned', find.text('12')), findsOneWidget);
    expect(_in('count-goal_aligned', find.text('60%')), findsOneWidget);
    expect(_in('count-maintenance', find.text('5')), findsOneWidget);
    expect(_in('count-maintenance', find.text('25%')), findsOneWidget);
    expect(_in('count-off_plan', find.text('3')), findsOneWidget);
    expect(_in('count-off_plan', find.text('15%')), findsOneWidget);
    expect(find.byKey(const Key('proportion-bar')), findsOneWidget);
    expect(find.text('20 tasks completed'), findsOneWidget);
    // The card says it counts tasks, not time.
    expect(find.textContaining('hour'), findsNothing);
    expect(find.textContaining('minute'), findsNothing);
  });

  testWidgets('a category with no task still shows with a count of zero',
      (tester) async {
    await pumpStats(
        tester, weekRoutes(summary: statisticsJson(maintenance: 4)), _card(),
        prefs: hintsClosed);
    expect(_in('count-goal_aligned', find.text('0')), findsOneWidget);
    expect(_in('count-off_plan', find.text('0')), findsOneWidget);
    expect(_in('count-maintenance', find.text('100%')), findsOneWidget);
  });

  testWidgets('the quiet hidden line names the count, and is gone at zero',
      (tester) async {
    await pumpStats(tester,
        weekRoutes(summary: statisticsJson(goalAligned: 1, hidden: 4)), _card(),
        prefs: hintsClosed);
    expect(find.text('4 tasks in ignored projects are not counted'),
        findsOneWidget);
    await pumpStats(tester,
        weekRoutes(summary: statisticsJson(goalAligned: 1, hidden: 1)), _card(),
        prefs: hintsClosed);
    expect(find.text('1 task in an ignored project is not counted'),
        findsOneWidget);
    await pumpStats(tester,
        weekRoutes(summary: statisticsJson(goalAligned: 1, hidden: 0)), _card(),
        prefs: hintsClosed);
    expect(find.byKey(const Key('hidden-line')), findsNothing);
    expect(find.textContaining('ignored projects'), findsNothing);
  });

  testWidgets('the hidden line is not drawn in the bar or the three counts',
      (tester) async {
    await pumpStats(tester,
        weekRoutes(summary: statisticsJson(goalAligned: 2, hidden: 9)), _card(),
        prefs: hintsClosed);
    expect(find.text('2 tasks completed'), findsOneWidget);
    expect(find.byKey(const Key('bar-segment-hidden')), findsNothing);
  });

  testWidgets('shows when the data was last synced', (tester) async {
    await pumpStats(
        tester, weekRoutes(summary: statisticsJson(goalAligned: 1)), _card(),
        prefs: hintsClosed);
    final at = DateTime.parse('2026-11-04T12:30:00Z').toLocal();
    expect(find.text('Last synced ${dateKey(at)} ${hhmm(at)}'), findsOneWidget);
    expect(find.byKey(const Key('sync-failed')), findsNothing);
  });

  testWidgets('says so when no sync has run yet', (tester) async {
    await pumpStats(
        tester,
        weekRoutes(
            summary: statisticsJson(
                goalAligned: 1, lastSyncedAt: null, outcome: null)),
        _card(),
        prefs: hintsClosed);
    expect(find.text('Not synced yet'), findsOneWidget);
  });

  testWidgets('after a failed sync the last numbers stay and nothing is off',
      (tester) async {
    final api = await pumpStats(
        tester,
        weekRoutes(
            summary: statisticsJson(
                goalAligned: 6,
                maintenance: 2,
                outcome: 'unreachable',
                lastSyncedAt: '2026-11-03T08:00:00Z')),
        _card(),
        prefs: hintsClosed);
    expect(_in('count-goal_aligned', find.text('6')), findsOneWidget);
    expect(_in('count-maintenance', find.text('2')), findsOneWidget);
    expect(find.byKey(const Key('proportion-bar')), findsOneWidget);
    expect(find.byKey(const Key('sync-failed')), findsOneWidget);
    expect(find.textContaining('could not reach'), findsOneWidget);
    expect(find.textContaining('last numbers'), findsOneWidget);
    expect(find.textContaining('Last synced'), findsOneWidget);
    // The counts still open their lists.
    await tester.tap(find.byKey(const Key('count-goal_aligned')));
    await tester.pumpAndSettle();
    expect(api.where('GET /statistics/tasks'), isNotEmpty);
  });

  testWidgets('an expired sign-in says what to do', (tester) async {
    await pumpStats(
        tester,
        weekRoutes(
            summary: statisticsJson(goalAligned: 1, outcome: 'auth_expired')),
        _card(),
        prefs: hintsClosed);
    expect(find.textContaining('sign-in has expired'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sync-open-connections')));
    await tester.pumpAndSettle();
    expect(find.text('connections page'), findsOneWidget);
  });

  testWidgets('available: false shows the reason and no number',
      (tester) async {
    await pumpStats(
        tester, weekRoutes(summary: statisticsJson(available: false)), _card(),
        prefs: hintsClosed);
    expect(find.byKey(const Key('categories-unavailable')), findsOneWidget);
    expect(find.textContaining('weekly plan'), findsWidgets);
    expect(find.byKey(const Key('proportion-bar')), findsNothing);
    expect(find.byKey(const Key('count-goal_aligned')), findsNothing);
    expect(find.textContaining(RegExp(r'\d+%')), findsNothing);
  });

  testWidgets('a load error says what happened and offers to try again',
      (tester) async {
    final api = await pumpStats(
        tester,
        {
          'GET /statistics': const ApiFailure(
              502, 'The task app did not answer.', 'backend_unavailable'),
        },
        _card());
    expect(find.text('The task app did not answer.'), findsOneWidget);
    expect(find.textContaining('could not load'), findsOneWidget);
    await tester.tap(find.byKey(const Key('categories-retry')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(api.where('GET /statistics'), hasLength(2));
  });

  testWidgets('each term has one sentence at its first use and not again',
      (tester) async {
    await pumpStats(
        tester,
        weekRoutes(
            summary: statisticsJson(
                goalAligned: 2, offPlan: 3, unsorted: 1, hidden: 2)),
        _card());
    expect(find.byKey(const Key('term-hint-category-terms')), findsOneWidget);
    expect(find.textContaining('Goal-aligned: '), findsOneWidget);
    expect(find.textContaining('Maintenance: '), findsOneWidget);
    expect(find.textContaining('Off-plan: '), findsOneWidget);
    expect(find.textContaining('Unsorted: '), findsOneWidget);
    expect(find.textContaining('Hidden: '), findsOneWidget);
    // The user closes the main hint; it does not come back.
    await tester.tap(find.byKey(const Key('term-hint-close-category-terms')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('term-hint-category-terms')), findsNothing);
    expect(find.textContaining('Goal-aligned: '), findsNothing);
    expect(find.textContaining('Unsorted: '), findsNothing);
    expect(find.textContaining('Hidden: '), findsNothing);
    // A card built again on this device (the next page) leaves them out.
    await tester.pumpWidget(const SizedBox());
    await pumpStats(
        tester,
        weekRoutes(
            summary: statisticsJson(goalAligned: 2, unsorted: 1, hidden: 2)),
        _card(),
        prefs: hintsClosed);
    expect(find.byType(Card), findsNothing);
    expect(find.textContaining('Goal-aligned: '), findsNothing);
  });

  testWidgets(
      'the unsorted and hidden terms show only when they apply, in '
      'the same box as the other terms', (tester) async {
    await pumpStats(
        tester, weekRoutes(summary: statisticsJson(goalAligned: 2)), _card());
    expect(find.byKey(const Key('term-hint-category-terms')), findsOneWidget);
    expect(find.textContaining('Unsorted: '), findsNothing);
    expect(find.textContaining('Hidden: '), findsNothing);
    // One box, never one box per term.
    expect(find.byKey(const Key('term-hint-category-unsorted')), findsNothing);
    expect(find.byKey(const Key('term-hint-category-hidden')), findsNothing);
  });

  testWidgets('the week card says what goal-aligned means in one line',
      (tester) async {
    await pumpStats(
        tester, weekRoutes(summary: statisticsJson(goalAligned: 2)), _card(),
        prefs: hintsClosed);
    expect(
        find.text(
            'Goal-aligned means work in a milestone you committed to this week.'),
        findsOneWidget);
  });

  testWidgets('the month card has no helper line about a week', (tester) async {
    await pumpStats(
        tester,
        weekRoutes(
            summary: statisticsJson(
                period: 'month',
                start: '2026-11-01',
                end: '2026-12-01',
                goalAligned: 2)),
        _card('month'),
        prefs: hintsClosed);
    expect(find.textContaining('committed to this week'), findsNothing);
  });

  testWidgets('a month asks for the first day of the month', (tester) async {
    final api = await pumpStats(
        tester,
        weekRoutes(
            summary: statisticsJson(
                period: 'month',
                start: '2026-11-01',
                end: '2026-12-01',
                goalAligned: 2)),
        _card('month'),
        prefs: hintsClosed);
    expect(api.where('GET /statistics').single.query,
        {'period': 'month', 'day': '2026-11-01'});
  });

  testWidgets('a year asks for the first of January', (tester) async {
    final api = await pumpStats(
        tester,
        weekRoutes(
            summary: statisticsJson(
                period: 'year',
                start: '2026-01-01',
                end: '2027-01-01',
                goalAligned: 2)),
        _card('year'),
        prefs: hintsClosed);
    expect(api.where('GET /statistics').single.query,
        {'period': 'year', 'day': '2026-01-01'});
  });

  testWidgets('the unsorted note offers to label the projects', (tester) async {
    await pumpStats(tester,
        weekRoutes(summary: statisticsJson(offPlan: 4, unsorted: 3)), _card(),
        prefs: hintsClosed);
    expect(find.textContaining('3 of the off-plan tasks are unsorted'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('unsorted-label-projects')));
    await tester.pumpAndSettle();
    expect(find.text('projects page'), findsOneWidget);
  });

  testWidgets('the card does not use an alert tint', (tester) async {
    await pumpStats(
        tester, weekRoutes(summary: statisticsJson(goalAligned: 2)), _card(),
        prefs: hintsClosed);
    final scheme =
        Theme.of(tester.element(find.byKey(const Key('categories-card'))))
            .colorScheme;
    final boxes = tester
        .widgetList<DecoratedBox>(find.descendant(
            of: find.byKey(const Key('categories-card')),
            matching: find.byType(DecoratedBox)))
        .map((d) => d.decoration)
        .whereType<BoxDecoration>();
    for (final d in boxes) {
      expect(d.color, isNot(scheme.errorContainer));
    }
  });
}
