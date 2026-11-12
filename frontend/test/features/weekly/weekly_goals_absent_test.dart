import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/review/review_screen.dart';
import 'package:tefteri/features/weekly/weekly_screen.dart';

import '../../support/fake_api.dart';
import 'weekly_fake.dart';
import 'weekly_pump.dart';

/// "goal" or "goals" as a word, but not "goal-aligned" (a work category).
final _goalWord = RegExp(r'\bgoals?\b(?!-)', caseSensitive: false);

Finder _goalTexts() => find.byWidgetPredicate((w) {
      final s = w is Text
          ? (w.textSpan?.toPlainText() ?? w.data ?? '')
          : w is EditableText
              ? w.controller.text
              : null;
      return s != null && _goalWord.hasMatch(s);
    });

void main() {
  testWidgets('the weekly planning flow offers no goal in any step (SC-005)',
      (tester) async {
    final api =
        await pumpWeekly(tester, WeeklyServer(lookBack: sampleLookBack()));
    for (final step in WeeklyStep.values) {
      final check = find.byKey(Key('check-${step.name}'));
      if (check.evaluate().isEmpty) continue;
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(_goalTexts(), findsNothing, reason: step.name);
    }
    expect(
        api.requests.where(
            (r) => r.path.startsWith('/goals') || r.path.startsWith('/annual')),
        isEmpty);
  });

  for (final type in ['week', 'month']) {
    testWidgets('the review of a $type plan says "goals (history)"',
        (tester) async {
      final api = FakeApi({
        'GET /plans/p1/review': {
          'plan_id': 'p1',
          'plan_title': 'Old plan',
          'period_type': type,
          'period_start': type == 'week' ? '2026-10-05' : '2026-10-01',
          'period_end': type == 'week' ? '2026-10-12' : '2026-11-01',
          'period_ended': true,
          'generated_at': '2026-11-01T08:00:00Z',
          'planned_count': 2,
          'completed_count': 1,
          'items': [
            {
              'type': 'goal',
              'id': 'g1',
              'title': 'Run 25 km',
              'completed': true
            },
            {
              'type': 'task',
              'id': 't1',
              'title': 'Buy shoes',
              'completed': false
            },
          ],
          'carried_over': ['t1'],
          'retrospective': null,
        },
      });
      await pumpWithApi(tester, api, const ReviewScreen(planId: 'p1'));
      expect(find.text('1 of 2 goals (history) done'), findsOneWidget);
      expect(find.text('Goal (history)'), findsOneWidget);
      expect(find.text('Goal'), findsNothing);
    });
  }
}
