@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/review/plan_history_screen.dart';
import 'package:tefteri/features/review/review_screen.dart';

import 'fixtures.dart';
import 'screenshot_helper.dart';

final _review = {
  'plan_id': 'p1',
  'plan_title': 'October: get back in shape',
  'period_type': 'month',
  'period_start': '2026-10-01',
  'period_end': '2026-11-01',
  'period_ended': true,
  'generated_at': '2026-11-01T08:00:00Z',
  'planned_count': 5,
  'completed_count': 3,
  'items': [
    {'type': 'goal', 'id': 'g1', 'title': 'Read 2 books', 'completed': true},
    {'type': 'goal', 'id': 'g2', 'title': 'Run 80 km', 'completed': false},
    {
      'type': 'task',
      'id': 't1',
      'title': 'Buy running shoes',
      'completed': true
    },
    {
      'type': 'task',
      'id': 't2',
      'title': 'Join a running club',
      'completed': false
    },
    {
      'type': 'task',
      'id': 't3',
      'title': 'Finish the second book',
      'completed': true
    },
  ],
  'carried_over': ['g2', 't2'],
  'retrospective': noteJson('n7', 'Retrospective: October: get back in shape',
      kind: 'retrospective',
      context: null,
      body: 'Reading went well. Running stopped after the second week.\n'
          'Next month: run in the morning, before work.'),
};

void main() {
  testWidgets('plan history', (tester) async {
    final api = FakeApi({
      'GET /reviews/history': [
        {
          'plan_id': 'p2',
          'title': 'November',
          'period_type': 'month',
          'period_start': '2026-11-01',
          'period_end': '2026-12-01',
          'period_ended': false,
          'review': null,
        },
        {
          'plan_id': 'p1',
          'title': 'October: get back in shape',
          'period_type': 'month',
          'period_start': '2026-10-01',
          'period_end': '2026-11-01',
          'period_ended': true,
          'review': {
            'generated_at': '2026-11-01T08:00:00Z',
            'planned_count': 5,
            'completed_count': 3,
            'has_retrospective': true,
          },
        },
        {
          'plan_id': 'p0',
          'title': '2026 resolutions',
          'period_type': 'year',
          'period_start': '2026-01-01',
          'period_end': '2027-01-01',
          'period_ended': false,
          'review': null,
        },
      ],
    });
    await pumpScreen(tester, api, const PlanHistoryScreen());
    await saveScreenshot('review-history');
  });

  testWidgets('review and retrospective', (tester) async {
    final api = FakeApi({'GET /plans/p1/review': _review});
    await pumpScreen(tester, api, const ReviewScreen(planId: 'p1'),
        size: const Size(1100, 1150));
    await saveScreenshot('review');
  });
}
