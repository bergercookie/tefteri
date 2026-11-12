import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'annual_fake.dart';

void main() {
  testWidgets(
      'the old goals are listed read only with parents and task '
      'counts', (tester) async {
    final api = await pumpAnnual(
        tester,
        AnnualServer().routes({
          'GET /goals/history': [
            legacyGoalJson('y1', 'Run a half marathon',
                periodType: 'year',
                periodStart: '2026-01-01',
                status: 'retired'),
            legacyGoalJson('m1', 'Run 100 km in November',
                parentId: 'y1', linkedTasks: 3),
            legacyGoalJson('w1', 'Run 25 km',
                periodType: 'week',
                periodStart: '2026-11-02',
                parentId: 'm1',
                status: 'done',
                linkedTasks: 1),
          ],
        }));
    await tapKey(tester, 'open-legacy-goals');
    expect(api.where('GET /goals/history'), hasLength(1));
    final view = find.byKey(const Key('legacy-goals'));
    expect(view, findsOneWidget);
    for (final id in ['y1', 'm1', 'w1']) {
      expect(find.byKey(Key('legacy-goal-$id')), findsOneWidget);
    }
    final month = find.byKey(const Key('legacy-goal-m1'));
    expect(
        find.descendant(of: month, matching: find.textContaining('Nov 2026')),
        findsOneWidget);
    expect(
        find.descendant(
            of: month, matching: find.textContaining('Run a half marathon')),
        findsOneWidget);
    expect(find.descendant(of: month, matching: find.textContaining('3 tasks')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('legacy-goal-w1')),
            matching: find.textContaining('1 task')),
        findsOneWidget);
    // Read only: no field, no menu, no edit, add or delete button.
    expect(find.descendant(of: view, matching: find.byType(TextField)),
        findsNothing);
    expect(
        find.descendant(
            of: view, matching: find.byType(PopupMenuButton<String>)),
        findsNothing);
    for (final word in ['Edit', 'Add', 'Delete', 'Remove']) {
      expect(find.descendant(of: view, matching: find.textContaining(word)),
          findsNothing,
          reason: word);
    }
  });

  testWidgets('no old goals shows an empty state', (tester) async {
    await pumpAnnual(
        tester, AnnualServer().routes({'GET /goals/history': <Object?>[]}));
    await tapKey(tester, 'open-legacy-goals');
    expect(find.byKey(const Key('legacy-goals-empty')), findsOneWidget);
  });
}
