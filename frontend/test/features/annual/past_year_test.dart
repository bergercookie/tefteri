import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'annual_fake.dart';

AnnualServer _past() => AnnualServer(year: 2029, state: 'past', goals: [
      annualGoalJson('g1', 'Get fit', keyResults: [
        keyResultJson('kr1', 'Runs',
            deadline: '2029-12-31',
            links: [linkJson('p1', 'Health')],
            flags: [flagJson('overdue')]),
        keyResultJson('kr2', 'Swims',
            deadline: '2029-12-31', status: 'retired'),
      ]),
    ])
      ..retiredGoals.add(annualGoalJson('g2', 'Old goal', status: 'retired'));

void main() {
  testWidgets('a past year is read only, with a quiet note; values stay',
      (tester) async {
    final api = await pumpAnnual(
        tester,
        _past().routes({
          'POST /annual/key-results/kr1/values': {'id': 'v1', 'value': 3},
        }),
        year: 2029);
    expect(find.byKey(const Key('past-year-note')), findsOneWidget);
    for (final key in [
      'add-goal',
      'write-first-goal',
      'goal-menu-g1',
      'add-kr-g1',
      'kr-menu-kr1',
      'restore-kr-kr2',
      'restore-goal-g2',
      'open-suggestions',
      'seed-panel',
    ]) {
      expect(find.byKey(Key(key)), findsNothing, reason: key);
    }
    expect(find.byKey(const Key('retired-kr-kr2')), findsOneWidget);
    expect(find.byKey(const Key('retired-goal-g2')), findsOneWidget);
    // The overdue flag offers only the value entry.
    expect(
        find.byKey(const Key('flag-action-update_value-kr1')), findsOneWidget);
    await tapKey(tester, 'kr-value-btn-kr1');
    await typeKey(tester, 'value-field', '3');
    await tapKey(tester, 'value-save');
    expect(api.where('POST /annual/key-results/kr1/values'), hasLength(1));
  });

  testWidgets('a past year with no goals has no write action', (tester) async {
    await pumpAnnual(tester, AnnualServer(year: 2029, state: 'past').routes(),
        year: 2029);
    expect(find.byKey(const Key('annual-empty')), findsOneWidget);
    expect(find.byKey(const Key('write-first-goal')), findsNothing);
    expect(find.byKey(const Key('seed-panel')), findsNothing);
  });
}
