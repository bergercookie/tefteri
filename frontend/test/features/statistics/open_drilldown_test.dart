import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tefteri/features/statistics/open_drilldown_screen.dart';
import 'package:tefteri/features/statistics/open_work_card.dart';

import '../../support/fake_api.dart';

final _tasks = [
  openTaskJson('a1', 'Write the launch post',
      category: 'goal_aligned', project: 'Website'),
  openTaskJson('a2', 'Review the pricing page',
      category: 'goal_aligned', project: 'Website'),
  openTaskJson('m1', 'Renew the domain',
      category: 'maintenance', project: 'Chores'),
  openTaskJson('o1', 'Call the accountant', project: 'Home'),
];

FakeApi _api([Map<String, Object?> extra = const {}]) => FakeApi({
      'GET /statistics/open': openTasksJson(tasks: _tasks),
      'GET /statistics': statisticsJson(),
      ...extra,
    });

GoRouter _router() => GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: SingleChildScrollView(
              child: OpenWorkCard(day: DateTime(2026, 11, 4))),
        ),
      ),
      openStatisticsRoute(),
      GoRoute(path: '/week', builder: (_, __) => const Text('the week')),
    ]);

void main() {
  testWidgets('a count of the card opens only the tasks of that category',
      (tester) async {
    final api = _api();
    await pumpWithApi(tester, api, const SizedBox(), router: _router());
    await tester.tap(find.text('Maintenance').first);
    await tester.pumpAndSettle();
    // The list of one category, not the card.
    expect(find.byKey(const Key('open-work-card')), findsNothing);
    expect(find.text('Tasks still to do'), findsWidgets);
    expect(find.text('Renew the domain'), findsOneWidget);
    expect(find.text('Write the launch post'), findsNothing);
    expect(find.text('Call the accountant'), findsNothing);
    expect(find.byKey(const Key('open-complete-m1')), findsOneWidget);
    expect(find.byKey(const Key('open-complete-a1')), findsNothing);
  });

  testWidgets('a segment of the bar opens that category too', (tester) async {
    await pumpWithApi(tester, _api(), const SizedBox(), router: _router());
    await tester.tap(find.byKey(const Key('bar-segment-goal_aligned')));
    await tester.pumpAndSettle();
    expect(find.text('Write the launch post'), findsOneWidget);
    expect(find.text('Review the pricing page'), findsOneWidget);
    expect(find.text('Renew the domain'), findsNothing);
  });

  testWidgets('each of the three counts opens its own list', (tester) async {
    for (final (name, shown, hidden) in [
      ('Goal-aligned', 'Write the launch post', 'Call the accountant'),
      ('Off-plan', 'Call the accountant', 'Write the launch post'),
    ]) {
      await pumpWithApi(tester, _api(), const SizedBox(), router: _router());
      await tester.tap(find.text(name).first);
      await tester.pumpAndSettle();
      expect(find.text(shown), findsOneWidget, reason: name);
      expect(find.text(hidden), findsNothing, reason: name);
    }
  });

  testWidgets(
      'a task can be marked done from the list, and the list reads '
      'again', (tester) async {
    final api = _api({
      'POST /tasks/m1/complete': taskJson('m1', 'x', status: 'done'),
    });
    await pumpWithApi(tester, api, const SizedBox(), router: _router());
    await tester.tap(find.text('Maintenance').first);
    await tester.pumpAndSettle();
    final before = api.where('GET /statistics/open').length;
    await tester.tap(find.byKey(const Key('open-complete-m1')));
    await tester.pumpAndSettle();
    expect(api.where('POST /tasks/m1/complete'), hasLength(1));
    expect(api.where('GET /statistics/open').length, greaterThan(before));
  });

  testWidgets('a category with no task says so', (tester) async {
    final api = _api({
      'GET /statistics/open': openTasksJson(tasks: [_tasks.first]),
    });
    await pumpWithApi(tester, api, const SizedBox(), router: _router());
    await tester.tap(find.text('Off-plan').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-drilldown-empty')), findsOneWidget);
  });

  testWidgets('an address with an unknown category cannot be opened',
      (tester) async {
    final router = GoRouter(
        initialLocation: '/statistics/open?day=2026-11-04&category=nope',
        routes: [
          openStatisticsRoute(),
          GoRoute(path: '/week', builder: (_, __) => const Text('the week')),
        ]);
    await pumpWithApi(tester, _api(), const SizedBox(), router: router);
    expect(find.text('This list cannot be opened.'), findsOneWidget);
  });
}
