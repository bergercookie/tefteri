import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/year/year_screen.dart';

import '../../support/fake_api.dart';

const _path = 'GET /views/year/2026';

Map<String, Object?> _year() => periodJson(
      'year',
      '2026-01-01',
      '2027-01-01',
      goals: [
        goalJson('g1', 'Run a marathon', progress: 0.75),
        goalJson('g2', 'Read more', status: 'done', progress: 1),
      ],
      tasks: [taskJson('t1', 'Book race')],
    );

/// Two months of the year: the year counts are their sum.
final _months = [
  {
    'start': '2026-01-01',
    'end': '2026-02-01',
    'counts': categoryCountsJson(10, 4, 2),
    'hidden': 0,
  },
  {
    'start': '2026-02-01',
    'end': '2026-03-01',
    'counts': categoryCountsJson(5, 6, 8),
    'hidden': 3,
  },
];

Map<String, Object?> _stats() => statisticsJson(
      period: 'year',
      start: '2026-01-01',
      end: '2027-01-01',
      goalAligned: 15,
      maintenance: 10,
      offPlan: 10,
      hidden: 3,
      parts: _months,
    );

Future<void> _pump(WidgetTester tester, FakeApi api) {
  SharedPreferences.setMockInitialValues({});
  return pumpWithApi(tester, api, const YearScreen(initialYear: 2026));
}

void main() {
  testWidgets('shows year goals and progress; no events section',
      (tester) async {
    final api = FakeApi({_path: _year()});
    await _pump(tester, api);
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('Run a marathon'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    // Single tasks are not listed in the year view.
    expect(find.text('Book race'), findsNothing);
    expect(find.text('Tasks'), findsNothing);
    expect(find.text('Events'), findsNothing);
  });

  testWidgets('shows three counts and one bar, and no task list',
      (tester) async {
    final api = FakeApi({_path: _year(), 'GET /statistics': _stats()});
    await _pump(tester, api);
    expect(api.where('GET /statistics').single.query,
        {'period': 'year', 'day': '2026-01-01'});
    expect(find.byKey(const Key('categories-card')), findsOneWidget);
    expect(find.byKey(const Key('proportion-bar')), findsOneWidget);
    expect(api.where('GET /statistics/tasks'), isEmpty);
    expect(find.byKey(const Key('completed-group-off_plan')), findsNothing);
    // The existing sections still show.
    expect(find.text('Run a marathon'), findsOneWidget);
    // The year counts are the sum of the months.
    for (final k in ['goal_aligned', 'maintenance', 'off_plan']) {
      final sum = [for (final m in _months) (m['counts']! as Map)[k]! as int]
          .fold(0, (a, b) => a + b);
      expect(
          find.descendant(
              of: find.byKey(Key('count-$k')), matching: find.text('$sum')),
          findsOneWidget,
          reason: k);
    }
  });

  testWidgets('next year loads the next year view', (tester) async {
    final api = FakeApi({
      _path: _year(),
      'GET /views/year/2027': periodJson('year', '2027-01-01', '2028-01-01'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('next-period')));
    await tester.pumpAndSettle();
    expect(api.where('GET /views/year/2027'), hasLength(1));
    expect(find.text('2027'), findsOneWidget);
  });
}
