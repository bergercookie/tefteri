import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tefteri/features/trends/trends_screen.dart';

import '../../support/fake_api.dart';

/// Five finished weeks at 60%, then a good week, then the running one.
List<Map<String, Object?>> _weeks() => [
      for (final d in ['2030-01-07', '2030-01-14', '2030-01-21', '2030-01-28'])
        weekMetricsJson(d,
            committed: 10,
            committedDone: 6,
            goalAligned: 6,
            offPlan: 4,
            milestonesCommitted: 2,
            milestonesDone: 1,
            themes: 1),
      weekMetricsJson('2030-02-04',
          committed: 10,
          committedDone: 9,
          goalAligned: 12,
          maintenance: 1,
          offPlan: 1,
          milestonesCommitted: 2,
          milestonesDone: 2,
          milestonesFinished: 3,
          themes: 2),
      weekMetricsJson('2030-02-11',
          finished: false, committed: 8, committedDone: 2, goalAligned: 2),
    ];

GoRouter _router() => GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const TrendsScreen()),
      GoRoute(path: '/week', builder: (_, __) => const Text('the week')),
    ]);

void main() {
  testWidgets('shows the weeks as charts and a table, and says no time',
      (tester) async {
    final api = FakeApi({'GET /weekly/trends': trendsJson(_weeks())});
    await pumpWithApi(tester, api, const SizedBox(), router: _router());
    expect(api.where('GET /weekly/trends').single.query, {'weeks': 12});
    expect(find.text('Trends'), findsWidgets);
    expect(
        find.textContaining('Tefteri does not measure time'), findsOneWidget);
    expect(find.byKey(const Key('stacked-bars')), findsOneWidget);
    expect(find.byKey(const Key('completion-bars')), findsOneWidget);
    expect(find.byKey(const Key('numbers-table')), findsOneWidget);
    // Every week has a row of exact numbers, the running week marked.
    for (final d in ['2030-01-07', '2030-02-04']) {
      expect(find.text(d), findsOneWidget, reason: d);
    }
    expect(find.text('2030-02-11 (so far)'), findsOneWidget);
    expect(find.text('9 of 10'), findsOneWidget);
    expect(find.text('90%'), findsWidgets);
  });

  testWidgets('compares the last finished week, not the running one',
      (tester) async {
    await pumpWithApi(tester,
        FakeApi({'GET /weekly/trends': trendsJson(_weeks())}), const SizedBox(),
        router: _router());
    expect(find.byKey(const Key('trend-lines')), findsOneWidget);
    expect(find.textContaining('week of 2030-02-04'), findsOneWidget);
    // Completion went from 60% to 90%: up, and the words say so.
    expect(
        tester
            .widget<Text>(find.byKey(const Key('trend-direction-completion')))
            .data,
        'UP');
    expect(find.textContaining('30 points higher than'), findsOneWidget);
    expect(find.textContaining('Tasks completed: 14'), findsOneWidget);
    expect(
        find.textContaining('Goal-aligned share of the work'), findsOneWidget);
  });

  testWidgets('says there are too few weeks instead of guessing',
      (tester) async {
    final weeks = [
      weekMetricsJson('2030-01-28',
          committed: 10, committedDone: 6, goalAligned: 6, offPlan: 4),
      weekMetricsJson('2030-02-04',
          committed: 10, committedDone: 9, goalAligned: 9, offPlan: 1),
    ];
    await pumpWithApi(tester,
        FakeApi({'GET /weekly/trends': trendsJson(weeks)}), const SizedBox(),
        router: _router());
    expect(find.byKey(const Key('trend-not-enough')), findsOneWidget);
    expect(find.byKey(const Key('trend-direction-completion')), findsNothing);
    // The weeks are still shown.
    expect(find.byKey(const Key('numbers-table')), findsOneWidget);
  });

  testWidgets('the range asks for more weeks', (tester) async {
    final api = FakeApi({'GET /weekly/trends': trendsJson(_weeks())});
    await pumpWithApi(tester, api, const SizedBox(), router: _router());
    await tester.tap(find.text('26 weeks'));
    await tester.pumpAndSettle();
    expect(api.where('GET /weekly/trends').last.query, {'weeks': 26});
  });

  testWidgets('with no week that has numbers it says so', (tester) async {
    final empty = [
      weekMetricsJson('2030-01-28'),
      weekMetricsJson('2030-02-04', finished: false),
    ];
    await pumpWithApi(tester,
        FakeApi({'GET /weekly/trends': trendsJson(empty)}), const SizedBox(),
        router: _router());
    expect(find.byKey(const Key('trends-empty')), findsOneWidget);
    expect(find.byKey(const Key('stacked-bars')), findsNothing);
  });

  testWidgets('a failed load shows the message and a retry', (tester) async {
    final api = FakeApi({
      'GET /weekly/trends':
          const ApiFailure(502, 'The server is busy.', 'unavailable'),
    });
    await pumpWithApi(tester, api, const SizedBox(), router: _router());
    expect(find.text('The server is busy.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trends-retry')));
    await tester.pumpAndSettle();
    expect(api.where('GET /weekly/trends').length, greaterThan(1));
  });
}
