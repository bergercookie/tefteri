import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tefteri/features/annual/annual_models.dart';
import 'package:tefteri/features/period/task_goal_picker.dart';

import '../../support/fake_api.dart';

class _Host extends StatelessWidget {
  const _Host(this.onPicked);

  final void Function(AnnualGoal?) onPicked;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: TextButton(
          key: const Key('open'),
          onPressed: () async =>
              onPicked(await showTaskGoalPicker(context, year: 2030)),
          child: const Text('open'),
        ),
      );
}

void main() {
  testWidgets('offers only the active goals of the current annual plan',
      (tester) async {
    AnnualGoal? picked;
    final api = FakeApi({
      'GET /annual/2030': annualPlanJson(goals: [
        annualGoalJson('a1', 'Get better at open source'),
        annualGoalJson('a2', 'Run a half marathon'),
      ], retiredGoals: [
        annualGoalJson('a3', 'Learn Rust', status: 'retired'),
      ]),
    });
    await pumpWithApi(tester, api, _Host((g) => picked = g));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(api.where('GET /annual/2030'), hasLength(1));
    expect(find.byKey(const Key('link-goal-a1')), findsOneWidget);
    expect(find.byKey(const Key('link-goal-a2')), findsOneWidget);
    expect(find.byKey(const Key('link-goal-a3')), findsNothing);
    expect(api.requests.where((r) => r.path.startsWith('/goals')), isEmpty);
    await tester.tap(find.byKey(const Key('link-goal-a2')));
    await tester.pumpAndSettle();
    expect(picked?.id, 'a2');
  });

  testWidgets('with no goal it shows an empty state that links to the plan',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => _Host((_) {})),
      GoRoute(
          path: '/annual',
          builder: (_, s) => Text('annual ${s.uri.queryParameters['year']}')),
    ]);
    addTearDown(router.dispose);
    final api = FakeApi({'GET /annual/2030': annualPlanJson()});
    await pumpWithApi(tester, api, const SizedBox.shrink(), router: router);
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-goal-empty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-annual-plan')));
    await tester.pumpAndSettle();
    expect(find.text('annual 2030'), findsOneWidget);
  });
}
