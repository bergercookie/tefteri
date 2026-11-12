import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/month/month_screen.dart';

import '../../support/fake_api.dart';

const _path = 'GET /views/month/2026-11-01';

Map<String, Object?> _month() => periodJson(
      'month',
      '2026-11-01',
      '2026-12-01',
      goals: [
        goalJson('g1', 'Launch site',
            periodType: 'month', periodStart: '2026-11-01', progress: 0.25),
      ],
      tasks: [taskJson('t1', 'Draft copy')],
      entries: [
        {
          'id': 'e1',
          'connection_id': 'c2',
          'title': 'Team standup',
          'start': DateTime(2026, 11, 3, 10).toUtc().toIso8601String(),
          'end': null,
          'all_day': false,
          'sync_state': 'synced',
        },
      ],
    );

/// Three days of the month: the month counts are their sum.
final _parts = [
  {
    'start': '2026-11-01',
    'end': '2026-11-02',
    'counts': categoryCountsJson(2, 1, 0),
    'hidden': 0,
  },
  {
    'start': '2026-11-02',
    'end': '2026-11-03',
    'counts': categoryCountsJson(3, 0, 1),
    'hidden': 1,
  },
  {
    'start': '2026-11-03',
    'end': '2026-11-04',
    'counts': categoryCountsJson(1, 2, 2),
    'hidden': 0,
  },
];

Map<String, Object?> _stats() => statisticsJson(
      period: 'month',
      start: '2026-11-01',
      end: '2026-12-01',
      goalAligned: 6,
      maintenance: 3,
      offPlan: 3,
      hidden: 1,
      parts: _parts,
    );

Future<void> _pump(WidgetTester tester, FakeApi api) {
  SharedPreferences.setMockInitialValues({});
  return pumpWithApi(
      tester, api, MonthScreen(initialDate: DateTime(2026, 11, 15)));
}

void main() {
  testWidgets('shows month goals and progress, but no single tasks',
      (tester) async {
    final api = FakeApi({_path: _month()});
    await _pump(tester, api);
    expect(find.text('Nov 2026'), findsOneWidget);
    expect(find.text('Launch site'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byKey(const Key('goal-progress-g1')))
            .value,
        0.25);
    // The month view does not list single tasks.
    expect(find.text('Draft copy'), findsNothing);
    expect(find.text('Tasks'), findsNothing);
    expect(find.byKey(const Key('no-tasks')), findsNothing);
  });

  testWidgets('shows three counts and one bar, and no task list',
      (tester) async {
    final api = FakeApi({
      _path: _month(),
      'GET /statistics': _stats(),
      'GET /statistics/tasks': fakeStatisticsTasks([
        statTaskJson('x1', 'Hidden in the card'),
      ]),
    });
    await _pump(tester, api);
    expect(api.where('GET /statistics').single.query,
        {'period': 'month', 'day': '2026-11-01'});
    expect(find.byKey(const Key('categories-card')), findsOneWidget);
    expect(find.byKey(const Key('proportion-bar')), findsOneWidget);
    expect(find.byKey(const Key('count-goal_aligned')), findsOneWidget);
    expect(find.byKey(const Key('count-maintenance')), findsOneWidget);
    expect(find.byKey(const Key('count-off_plan')), findsOneWidget);
    // No task list: the tasks load only after a tap.
    expect(api.where('GET /statistics/tasks'), isEmpty);
    expect(find.text('Hidden in the card'), findsNothing);
    expect(find.byKey(const Key('completed-group-off_plan')), findsNothing);
    // The existing sections still show.
    expect(find.text('Launch site'), findsOneWidget);
  });

  testWidgets('the counts equal the sum of the parts', (tester) async {
    final api = FakeApi({_path: _month(), 'GET /statistics': _stats()});
    await _pump(tester, api);
    int sum(String k) => [
          for (final p in _parts) (p['counts']! as Map)[k]! as int,
        ].fold(0, (a, b) => a + b);
    for (final k in ['goal_aligned', 'maintenance', 'off_plan']) {
      expect(
          find.descendant(
              of: find.byKey(Key('count-$k')),
              matching: find.text('${sum(k)}')),
          findsOneWidget,
          reason: k);
    }
  });

  testWidgets('does not list the events of the month', (tester) async {
    await _pump(tester, FakeApi({_path: _month()}));
    expect(find.text('Launch site'), findsOneWidget);
    // The list was long and no help in a monthly overview.
    expect(find.text('Events'), findsNothing);
    expect(find.text('Team standup'), findsNothing);
    expect(find.byKey(const Key('no-events')), findsNothing);
    expect(find.byKey(const Key('entry-e1')), findsNothing);
  });

  testWidgets('next month loads the first day of December', (tester) async {
    final api = FakeApi({
      _path: _month(),
      'GET /views/month/2026-12-01':
          periodJson('month', '2026-12-01', '2027-01-01'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('next-period')));
    await tester.pumpAndSettle();
    expect(api.where('GET /views/month/2026-12-01'), hasLength(1));
    expect(find.text('Dec 2026'), findsOneWidget);
  });
}
