import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'annual_fake.dart';

Object? _suggestions(RequestOptions o) {
  final from = o.queryParameters['from_year'];
  if ('$from' == '2028') {
    return suggestionsJson(year: 2031, fromYear: 2028, hasPlan: false);
  }
  if ('$from' == '2029') {
    return suggestionsJson(year: 2031, fromYear: 2029, goals: [
      suggestedGoalJson('o9', 'Learn the piano'),
    ]);
  }
  return suggestionsJson(year: 2031, fromYear: 2030, goals: [
    suggestedGoalJson('o1', 'Get better at open source', keyResults: [
      suggestedKeyResultJson('okr1', 'Stars',
          start: 220,
          target: 500,
          deadline: '2031-12-31',
          themes: [
            {'project_id': 'p1', 'name': 'Open source'}
          ]),
    ]),
    // Its only key result was met: the goal is offered on its own.
    suggestedGoalJson('o2', 'Read more books'),
  ]);
}

Future<FakeApi> _pump(WidgetTester tester) => pumpAnnual(
    tester,
    AnnualServer(year: 2031, state: 'future')
        .routes({'GET /annual/2031/suggestions': _suggestions}),
    year: 2031);

void main() {
  testWidgets('"from year" defaults to the year before', (tester) async {
    final api = await _pump(tester);
    expect(find.byKey(const Key('seed-panel')), findsOneWidget);
    final field =
        tester.widget<TextField>(find.byKey(const Key('seed-from-year')));
    expect(field.controller!.text, '2030');
    expect(api.where('GET /annual/2031/suggestions').single.query,
        {'from_year': 2030});
    expect(find.byKey(const Key('seed-goal-o1')), findsOneWidget);
    expect(find.byKey(const Key('seed-kr-okr1')), findsOneWidget);
  });

  testWidgets('changing it rebuilds the suggestions', (tester) async {
    final api = await _pump(tester);
    await typeKey(tester, 'seed-from-year', '2029');
    expect(api.where('GET /annual/2031/suggestions').last.query,
        {'from_year': 2029});
    expect(find.byKey(const Key('seed-goal-o9')), findsOneWidget);
    expect(find.byKey(const Key('seed-goal-o1')), findsNothing);
  });

  testWidgets('a year with no plan says so and offers a blank plan',
      (tester) async {
    await _pump(tester);
    await typeKey(tester, 'seed-from-year', '2028');
    expect(find.text('2028 has no plan.'), findsOneWidget);
    await tapKey(tester, 'seed-blank');
    expect(find.byKey(const Key('seed-panel')), findsNothing);
    expect(find.byKey(const Key('annual-empty')), findsOneWidget);
  });

  testWidgets('a met key result is not offered, its goal is', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('seed-goal-o2')), findsOneWidget);
    expect(find.byKey(const Key('seed-copy-goal-o2')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('seed-goal-o2')),
            matching: find.textContaining('Accept')),
        findsNothing);
  });

  testWidgets(
      'accepting a key result opens it for editing; nothing is '
      'stored until Save', (tester) async {
    final api = await _pump(tester);
    await tapKey(tester, 'seed-accept-kr-okr1');
    expect(api.where('POST /annual/2031/goals/bulk'), isEmpty);
    final deadline = tester
        .widget<TextField>(find.byKey(const Key('draft-kr-deadline-o1-okr1')));
    expect(deadline.controller!.text, '2031-12-31');
    final start = tester
        .widget<TextField>(find.byKey(const Key('draft-kr-start-o1-okr1')));
    expect(start.controller!.text, '220');
    await typeKey(tester, 'draft-kr-start-o1-okr1', '250');
    await tapKey(tester, 'seed-save');
    final body = api.where('POST /annual/2031/goals/bulk').single.data! as Map;
    expect(body['seeded_from'], 2030);
    expect(body['goals'], [
      {
        'title': 'Get better at open source',
        'seeded_from_goal_id': 'o1',
        'key_results': [
          {
            'metric': 'Stars',
            'kind': 'number',
            'start_value': 250.0,
            'target': 500.0,
            'deadline': '2031-12-31',
            'update_source': 'manual',
            'theme_ids': ['p1'],
            'seeded_from_key_result_id': 'okr1',
          }
        ],
      }
    ]);
    expect(find.text('Get better at open source'), findsWidgets);
  });

  testWidgets('"Dismiss all" gives a blank plan', (tester) async {
    final api = await _pump(tester);
    await tapKey(tester, 'seed-copy-goal-o2');
    await tapKey(tester, 'seed-dismiss');
    expect(find.byKey(const Key('seed-panel')), findsNothing);
    expect(find.byKey(const Key('annual-empty')), findsOneWidget);
    expect(api.where('POST /annual/2031/goals/bulk'), isEmpty);
  });
}
