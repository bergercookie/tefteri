@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/annual_review/annual_review_screen.dart';
import 'package:tefteri/theme/theme.dart';

import 'screenshot_helper.dart';

List<Object?> _series(int year) => [
      for (var m = 1; m <= 12; m++)
        reviewSeriesJson('$year-${m.toString().padLeft(2, '0')}',
            value: m <= 10 ? 120 + m * 28 : null,
            status: m <= 10 ? 'stored' : 'missing'),
    ];

Map<String, Object?> _api({String state = 'past', bool empty = false}) {
  const year = 2025;
  return annualReviewJson(
    year: year,
    state: state,
    goals: empty
        ? const []
        : [
            reviewGoalJson('g1', 'Get better at open source', keyResults: [
              reviewKeyResultJson('kr1', 'Stars on one repository',
                  start: 120,
                  target: 500,
                  outcome: 'hit',
                  last: 480,
                  lastMonth: '$year-11',
                  series: _series(year),
                  themes: [
                    reviewThemeJson('Open source',
                        hint: 'much_shipped_little_movement'),
                  ]),
              reviewKeyResultJson('kr2', 'Talks given',
                  start: 0,
                  target: 2,
                  outcome: 'missed',
                  last: 1,
                  lastMonth: '$year-09',
                  state: 'not_reached',
                  series: _series(year)),
            ]),
            reviewGoalJson('g2', 'Run a half marathon', status: 'retired'),
            reviewGoalJson('g3', 'Read more books', flags: [
              {
                'code': 'no_key_result',
                'actions': ['open_annual_plan']
              },
            ]),
          ],
    empty: empty
        ? {
            'reason': 'no_snapshots',
            'actions': ['open_annual_plan']
          }
        : null,
    stored: empty ? 0 : 8,
    yearNote: {
      'id': 'n1',
      'body': 'A year of learning and shipping.',
      'updated_at': '2026-01-02T10:00:00Z',
    },
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('past year with hit, missed and retired goals', (tester) async {
    final api = FakeApi({'GET /annual-review/2025': _api()});
    await pumpScreen(tester, api, const AnnualReviewScreen(initialYear: 2025),
        size: const Size(1100, 2400));
    await saveScreenshot('annual-review-past');
  });

  testWidgets('empty year', (tester) async {
    final api = FakeApi({
      'GET /annual-review/2025': _api(empty: true),
    });
    await pumpScreen(tester, api, const AnnualReviewScreen(initialYear: 2025),
        size: const Size(1100, 1400));
    await saveScreenshot('annual-review-empty');
  });

  testWidgets('year in progress', (tester) async {
    final api = FakeApi({
      'GET /annual-review/2025': _api(state: 'current'),
    });
    await pumpScreen(tester, api, const AnnualReviewScreen(initialYear: 2025),
        size: const Size(1100, 2400));
    await saveScreenshot('annual-review-current');
  });

  testWidgets('dark mode', (tester) async {
    final api = FakeApi({'GET /annual-review/2025': _api()});
    await pumpScreen(tester, api, const AnnualReviewScreen(initialYear: 2025),
        size: const Size(1100, 2400), theme: tefteriDark);
    await saveScreenshot('annual-review-dark');
  });
}
