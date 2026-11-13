import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/weekly/weekly_screen.dart';

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
}
