import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/weekly/weekly_card.dart';

import '../../support/fake_api.dart';
import 'weekly_fake.dart';

Map<String, Object?> _state(String week, {Map<String, Object?>? plan}) => {
      'week_start': week,
      'week_end': week,
      'plan': plan,
      'look_back': null,
    };

Map<String, Object?> _plan(String status, {int done = 0}) => {
      'id': 'p',
      'status': status,
      'committed_at': null,
      'retro_skipped': false,
      'max_projects': 3,
      'projects': [
        {
          'id': 'a',
          'name': 'Website',
          'created_here': false,
          'open_tasks': 3,
          'done_tasks': done,
          'scheduled_tasks': 2,
          'tasks': <Object?>[],
          'committed_tasks': [
            for (var i = 0; i < 4; i++)
              {
                'id': 't$i',
                'title': 'T',
                'planned_day': '2030-03-05',
                'done': i < done
              },
          ],
        },
      ],
    };

Future<FakeApi> _pump(WidgetTester tester, Map<String, Object?> routes,
    {required DateTime week, required DateTime today}) async {
  final api = FakeApi(routes);
  await pumpWithApi(tester, api,
      Scaffold(body: WeeklyPlanningCard(week: week, today: today)));
  return api;
}

void main() {
  // 2030-03-04 is a Monday.
  final monday = DateTime(2030, 3, 4);

  testWidgets('offers to start the plan of a week without one', (tester) async {
    await _pump(tester, {'GET /weekly/$weekKey': _state(weekKey)},
        week: monday, today: DateTime(2030, 3, 5));
    expect(find.text('Plan this week'), findsOneWidget);
    expect(find.text('Start planning'), findsOneWidget);
  });

  testWidgets('says that a plan is in progress', (tester) async {
    await _pump(
        tester, {'GET /weekly/$weekKey': _state(weekKey, plan: _plan('draft'))},
        week: monday, today: DateTime(2030, 3, 5));
    expect(find.text('Planning is in progress'), findsOneWidget);
    expect(find.text('Continue planning'), findsOneWidget);
    expect(find.textContaining('1 of 3 projects chosen'), findsOneWidget);
  });

  testWidgets('reports committed and done tasks of a committed plan',
      (tester) async {
    await _pump(
        tester,
        {
          'GET /weekly/$weekKey':
              _state(weekKey, plan: _plan('committed', done: 1))
        },
        week: monday,
        today: DateTime(2030, 3, 5));
    expect(find.text('This week is planned'), findsOneWidget);
    expect(
        find.text('1 project and 4 tasks committed, 1 done.'), findsOneWidget);
    expect(find.text('Open the plan'), findsOneWidget);
  });

  testWidgets('on a Sunday, an unplanned week offers the coming week',
      (tester) async {
    await _pump(
        tester,
        {
          'GET /weekly/$weekKey': _state(weekKey),
          'GET /weekly/2030-03-11': _state('2030-03-11'),
        },
        week: monday,
        today: DateTime(2030, 3, 10));
    expect(find.text('Plan next week'), findsOneWidget);
  });

  testWidgets(
      'on a Sunday, the card is about the coming week even when this '
      'week is planned', (tester) async {
    await _pump(
        tester,
        {
          'GET /weekly/$weekKey': _state(weekKey, plan: _plan('committed')),
          'GET /weekly/2030-03-11': _state('2030-03-11', plan: _plan('draft')),
        },
        week: monday,
        today: DateTime(2030, 3, 10));
    expect(find.text('Planning next week is in progress'), findsOneWidget);
    expect(find.text('This week is planned'), findsNothing);
  });

  testWidgets('from Monday to Thursday the card is about the shown week',
      (tester) async {
    await _pump(
        tester,
        {
          'GET /weekly/$weekKey': _state(weekKey, plan: _plan('committed')),
          'GET /weekly/2030-03-11': _state('2030-03-11'),
        },
        week: monday,
        today: DateTime(2030, 3, 7));
    expect(find.text('This week is planned'), findsOneWidget);
  });

  testWidgets('shows nothing when the state cannot be loaded', (tester) async {
    await _pump(tester, {}, week: monday, today: DateTime(2030, 3, 5));
    expect(find.byKey(const Key('weekly-card')), findsNothing);
  });
}
