import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/annual_review/annual_review_screen.dart';

import '../../support/fake_api.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows goals, key results, the rule and the deadline line',
      (tester) async {
    final api = FakeApi({
      'GET /annual-review/2030': annualReviewJson(
        year: 2030,
        goals: [
          reviewGoalJson('g1', 'Run a marathon', keyResults: [
            reviewKeyResultJson('kr1', 'Kilometres in one run',
                start: 0,
                target: 42,
                last: 42,
                lastMonth: '2030-10',
                series: [
                  for (var m = 1; m <= 12; m++)
                    reviewSeriesJson('2030-${m.toString().padLeft(2, '0')}',
                        value: m == 10 ? 42 : null,
                        status: m == 10 ? 'stored' : 'missing'),
                ]),
          ]),
          reviewGoalJson('g2', 'Read more', keyResults: [
            reviewKeyResultJson('kr2', 'Books',
                start: 0,
                target: 12,
                outcome: 'missed',
                last: 8,
                lastMonth: '2030-09'),
          ]),
        ],
        yearNote: {
          'id': 'n1',
          'body': 'A year of learning.',
          'updated_at': '2030-12-31T10:00:00Z'
        },
      ),
      'GET /checklists/year/2030-01-01': {
        'items': const [],
      },
    });
    await pumpWithApi(tester, api, const AnnualReviewScreen(initialYear: 2030));
    expect(find.text('Year review'), findsWidgets);
    expect(find.text('2030'), findsOneWidget);
    expect(find.text('Run a marathon'), findsOneWidget);
    expect(find.text('Kilometres in one run'), findsOneWidget);
    expect(find.byKey(const Key('review-rule')), findsOneWidget);
    expect(find.byKey(const Key('key-result-outcome')), findsWidgets);
    expect(find.text('Hit'), findsOneWidget);
    expect(find.text('Missed'), findsOneWidget);
    expect(find.byKey(const Key('deadline-line')), findsWidgets);
    expect(find.byKey(const Key('series-strip')), findsWidgets);
    expect(find.byKey(const Key('year-split')), findsOneWidget);
    expect(find.byKey(const Key('next-year-card')), findsOneWidget);
    expect(find.text('A year of learning.'), findsOneWidget);
  });

  testWidgets('shows the empty states and keeps the checklist', (tester) async {
    final api = FakeApi({
      'GET /annual-review/2030': annualReviewJson(
        year: 2030,
        empty: {
          'reason': 'no_goals',
          'actions': ['open_annual_plan']
        },
        stored: 0,
        goals: const [],
      ),
      'GET /checklists/year/2030-01-01': {
        'items': [
          {'text': 'Write the review', 'checked': false}
        ],
      },
    });
    await pumpWithApi(tester, api, const AnnualReviewScreen(initialYear: 2030));
    expect(find.byKey(const Key('review-empty')), findsOneWidget);
    expect(find.text('Open annual planning'), findsOneWidget);
    expect(find.text('Annual checklist'), findsOneWidget);
  });

  testWidgets('a future year shows a quiet state', (tester) async {
    final api = FakeApi({
      'GET /annual-review/2033': annualReviewJson(
        year: 2033,
        state: 'future',
        empty: {
          'reason': 'future_year',
          'actions': ['open_annual_plan']
        },
      ),
      'GET /checklists/year/2033-01-01': {'items': const []},
    });
    await pumpWithApi(tester, api, const AnnualReviewScreen(initialYear: 2033));
    expect(find.text('This year has not started yet.'), findsOneWidget);
  });

  testWidgets('a failed load offers a retry', (tester) async {
    final api = FakeApi({});
    await pumpWithApi(tester, api, const AnnualReviewScreen(initialYear: 2030));
    expect(find.byKey(const Key('load-error')), findsOneWidget);
    expect(find.byKey(const Key('reload-button')), findsOneWidget);
  });
}
