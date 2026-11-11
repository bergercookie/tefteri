import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tefteri/features/weekly/look_back_step.dart';

import 'weekly_fake.dart';
import 'weekly_pump.dart';

/// The plain text of the `Text.rich` or `Text` widgets under [key].
String _plain(WidgetTester tester, String key) => tester
    .widgetList<Text>(
        find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)))
    .map((t) => t.textSpan?.toPlainText() ?? t.data ?? '')
    .join(' ');

Future<void> _pump(WidgetTester tester, Map<String, Object?> summary,
    {List<Map<String, Object?>>? projects}) async {
  await pumpWeekly(
      tester,
      WeeklyServer(
          lookBack: sampleLookBack(summary: summary, projects: projects)));
}

void main() {
  testWidgets(
      'shows tasks done out of committed and milestones finished out '
      'of committed', (tester) async {
    await _pump(tester, sampleSummary());
    expect(find.byKey(const Key('review-summary')), findsOneWidget);
    expect(_plain(tester, 'review-tasks'), contains('5 of 7'));
    expect(_plain(tester, 'review-tasks'), contains('tasks done'));
    expect(_plain(tester, 'review-milestones'), contains('1 of 2'));
    expect(
        _plain(tester, 'review-milestones'), contains('milestones finished'));
  });

  testWidgets('the summary comes before the milestone cards', (tester) async {
    await _pump(tester, sampleSummary());
    expect(topOf(tester, 'review-summary'),
        lessThan(topOf(tester, 'look-project-op1')));
  });

  testWidgets('shows the pace per day', (tester) async {
    await _pump(tester, sampleSummary());
    expect(find.byKey(const Key('review-pace')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('pace-2030-02-26'))).data,
        '2');
    expect(tester.widget<Text>(find.byKey(const Key('pace-2030-02-27'))).data,
        '0');
  });

  testWidgets('shows the focus share when focus data exists', (tester) async {
    await _pump(tester, sampleSummary(focusShare: 0.6));
    expect(find.byKey(const Key('review-focus')), findsOneWidget);
    expect(
        find.textContaining('60% of the tasks you finished'), findsOneWidget);
  });

  testWidgets('shows no focus share without focus data', (tester) async {
    await _pump(tester, sampleSummary());
    expect(find.byKey(const Key('review-focus')), findsNothing);
    expect(find.textContaining('focus themes'), findsNothing);
  });

  testWidgets('a week with nothing committed shows a note and no ratio',
      (tester) async {
    await _pump(
        tester,
        sampleSummary(
            committed: 0,
            done: 0,
            milestones: 0,
            milestonesDone: 0,
            note: 'Nothing was committed that week.'),
        projects: []);
    expect(find.byKey(const Key('review-note')), findsOneWidget);
    expect(find.text('Nothing was committed that week.'), findsOneWidget);
    expect(find.byKey(const Key('review-tasks')), findsNothing);
    expect(find.byKey(const Key('review-milestones')), findsNothing);
    expect(find.byKey(const Key('review-pace')), findsNothing);
    expect(find.byKey(const Key('review-focus')), findsNothing);
    // The empty week can still be saved.
    expect(find.byKey(const Key('save-look-back')), findsOneWidget);
    expect(find.byKey(const Key('look-no-milestones')), findsOneWidget);
  });

  testWidgets('the review has no goal text anywhere', (tester) async {
    await _pump(tester, sampleSummary(focusShare: 0.4));
    // The app's navigation has a Goals tab; the review itself has no goal.
    final goals = find.descendant(
        of: find.byType(LookBackStep),
        matching: find.byWidgetPredicate((w) =>
            w is Text &&
            (w.textSpan?.toPlainText() ?? w.data ?? '')
                .toLowerCase()
                .contains('goal')));
    expect(find.byType(LookBackStep), findsOneWidget);
    expect(goals, findsNothing);
    expect(find.byType(TextField), findsOneWidget); // only the reflection
  });
}
