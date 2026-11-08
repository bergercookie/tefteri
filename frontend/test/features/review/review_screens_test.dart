import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/review/plan_history_screen.dart';
import 'package:tefteri/features/review/review_screen.dart';

import '../../support/fake_api.dart';

Map<String, Object?> _review({Map<String, Object?>? retrospective}) => {
      'plan_id': 'p1',
      'plan_title': 'October',
      'period_type': 'month',
      'period_start': '2026-10-01',
      'period_end': '2026-11-01',
      'period_ended': true,
      'generated_at': '2026-11-01T08:00:00Z',
      'planned_count': 3,
      'completed_count': 1,
      'items': [
        {
          'type': 'goal',
          'id': 'g1',
          'title': 'Read 2 books',
          'completed': true
        },
        {'type': 'goal', 'id': 'g2', 'title': 'Run 100 km', 'completed': false},
        {'type': 'task', 'id': 't1', 'title': 'Buy shoes', 'completed': false},
      ],
      'carried_over': ['g2', 't1'],
      'retrospective': retrospective,
    };

Map<String, Object?> _note(String body) => {
      'id': 'n1',
      'connection_id': 'c3',
      'kind': 'retrospective',
      'title': 'Retrospective: October',
      'body': body,
      'note_date': null,
      'context': null,
      'effective_context': 'life',
      'sync_state': 'synced',
    };

final _history = [
  {
    'plan_id': 'p2',
    'title': 'Next year',
    'period_type': 'year',
    'period_start': '2027-01-01',
    'period_end': '2028-01-01',
    'period_ended': false,
    'review': null,
  },
  {
    'plan_id': 'p1',
    'title': 'October',
    'period_type': 'month',
    'period_start': '2026-10-01',
    'period_end': '2026-11-01',
    'period_ended': true,
    'review': {
      'generated_at': '2026-11-01T08:00:00Z',
      'planned_count': 3,
      'completed_count': 1,
      'has_retrospective': true,
    },
  },
];

void main() {
  group('plan history', () {
    testWidgets('lists plans with their review state', (tester) async {
      final api = FakeApi({'GET /reviews/history': _history});
      await pumpWithApi(tester, api, const PlanHistoryScreen());
      expect(find.text('Next year'), findsOneWidget);
      expect(find.text('2027 - In progress.'), findsOneWidget);
      expect(find.text('Oct 2026 - 1 of 3 done - retrospective saved'),
          findsOneWidget);
    });

    testWidgets('new plan posts the chosen period', (tester) async {
      final api = FakeApi({
        'GET /reviews/history': <Object?>[],
        'POST /plans': const NoContent(),
      });
      await pumpWithApi(
          tester, api, PlanHistoryScreen(today: DateTime(2026, 11, 4)));
      expect(find.textContaining('No plans yet'), findsOneWidget);
      await tester.tap(find.byKey(const Key('new-plan')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('plan-title')), 'November');
      await tester.tap(find.byKey(const Key('plan-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Month').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan-save')));
      await tester.pumpAndSettle();
      expect(api.where('POST /plans').single.data, {
        'period_type': 'month',
        'period_start': '2026-11-01',
        'title': 'November',
      });
      expect(api.where('GET /reviews/history'), hasLength(2));
    });

    test('plan periods start with future ones and hold the current one', () {
      final weeks = planPeriods('week', DateTime(2026, 11, 4));
      expect(weeks.first.start, '2026-11-16');
      expect(weeks.map((w) => w.start), contains('2026-11-02'));
      final months = planPeriods('month', DateTime(2026, 11, 4));
      expect(months.first.start, '2027-01-01');
      expect(months.map((m) => m.start), contains('2025-11-01'));
      expect(
          planPeriods('year', DateTime(2026, 11, 4)).first.start, '2027-01-01');
    });
  });

  group('review', () {
    testWidgets('shows planned versus done and carried-over items',
        (tester) async {
      final api = FakeApi({'GET /plans/p1/review': _review()});
      await pumpWithApi(tester, api, const ReviewScreen(planId: 'p1'));
      expect(find.text('October'), findsOneWidget);
      expect(find.text('1 of 3 planned goals done'), findsOneWidget);
      expect(
          tester
              .widget<LinearProgressIndicator>(
                  find.byKey(const Key('review-progress')))
              .value,
          closeTo(1 / 3, 0.001));
      expect(find.text('Carried over (2)'), findsOneWidget);
      expect(find.byKey(const Key('carried-g2')), findsOneWidget);
      expect(find.byKey(const Key('carried-t1')), findsOneWidget);
      expect(find.byKey(const Key('carried-g1')), findsNothing);
    });

    testWidgets('update review asks for a new computation', (tester) async {
      final api = FakeApi({'GET /plans/p1/review': _review()});
      await pumpWithApi(tester, api, const ReviewScreen(planId: 'p1'));
      await tester.tap(find.byKey(const Key('review-refresh')));
      await tester.pumpAndSettle();
      expect(api.where('GET /plans/p1/review').map((r) => r.query['refresh']),
          contains('true'));
    });

    testWidgets('saves the retrospective to the notes app', (tester) async {
      final api = FakeApi({
        'GET /plans/p1/review': _review(),
        'PUT /plans/p1/review/retrospective':
            _review(retrospective: _note('Good month.')),
      });
      await pumpWithApi(tester, api, const ReviewScreen(planId: 'p1'));
      await tester.enterText(
          find.byKey(const Key('retro-field')), 'Good month.');
      await tester.tap(find.byKey(const Key('retro-save')));
      await tester.pumpAndSettle();
      expect(api.where('PUT /plans/p1/review/retrospective').single.data,
          {'body': 'Good month.'});
      expect(
          find.text('Retrospective saved to your notes app.'), findsOneWidget);
    });

    testWidgets('loads a saved retrospective into the editor', (tester) async {
      final api = FakeApi(
          {'GET /plans/p1/review': _review(retrospective: _note('Earlier.'))});
      await pumpWithApi(tester, api, const ReviewScreen(planId: 'p1'));
      expect(find.text('Earlier.'), findsOneWidget);
      expect(find.byKey(const Key('retro-saved')), findsOneWidget);
    });

    testWidgets('a failed save names the cause and keeps the text',
        (tester) async {
      final api = FakeApi({
        'GET /plans/p1/review': _review(),
        'PUT /plans/p1/review/retrospective': const ApiFailure(
            502,
            'Trilium cannot be reached. Nothing was changed.',
            'backend_unavailable'),
      });
      await pumpWithApi(tester, api, const ReviewScreen(planId: 'p1'));
      await tester.enterText(find.byKey(const Key('retro-field')), 'Draft');
      await tester.tap(find.byKey(const Key('retro-save')));
      await tester.pumpAndSettle();
      expect(find.text('Trilium cannot be reached. Nothing was changed.'),
          findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
    });
  });
}
