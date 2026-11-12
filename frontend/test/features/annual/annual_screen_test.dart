import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/theme/theme.dart';

import '../../support/fake_api.dart';
import 'annual_fake.dart';

Map<String, Object?> _threeKeyResults() =>
    annualGoalJson('g1', 'Get fit', keyResults: [
      for (var i = 1; i <= 3; i++)
        keyResultJson('kr$i', 'Metric $i', links: [linkJson('p1', 'Health')]),
    ]);

void main() {
  testWidgets('a year with no goals shows an empty state with one action',
      (tester) async {
    await pumpAnnual(tester, AnnualServer().routes());
    expect(find.byKey(const Key('annual-empty')), findsOneWidget);
    final empty = find.byType(EmptyState);
    expect(empty, findsOneWidget);
    expect(
        find.descendant(
            of: empty,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)),
        findsOneWidget);
    expect(find.byKey(const Key('write-first-goal')), findsOneWidget);
    expect(find.text('Annual plan'), findsWidgets);
    expect(find.byKey(const Key('year-label')), findsOneWidget);
  });

  testWidgets('add a goal, then a key result; the current value is the start',
      (tester) async {
    final server = AnnualServer();
    final api = await pumpAnnual(tester, server.routes());
    await tapKey(tester, 'write-first-goal');
    await typeKey(tester, 'goal-title-field', 'Get better at open source');
    await tapKey(tester, 'goal-title-save');
    final bulk = api.where('POST /annual/2030/goals/bulk').single.data! as Map;
    expect((bulk['goals'] as List).single,
        {'title': 'Get better at open source', 'key_results': <Object?>[]});
    expect(find.text('Get better at open source'), findsOneWidget);
    final id = server.goals.single['id'];

    await tapKey(tester, 'add-kr-$id');
    await typeKey(tester, 'kr-metric', 'Stars on the main repository');
    await typeKey(tester, 'kr-start', '120');
    await typeKey(tester, 'kr-target', '500');
    await typeKey(tester, 'kr-deadline', '2030-12-31');
    await tapKey(tester, 'kr-save');
    final sent =
        api.where('POST /annual/goals/$id/key-results').single.data! as Map;
    expect(sent['metric'], 'Stars on the main repository');
    expect(sent['start_value'], 120);
    expect(sent['target'], 500);
    expect(sent['deadline'], '2030-12-31');
    expect(sent['update_source'], 'manual');
    expect(find.byKey(const Key('kr-form')), findsNothing);
    expect(find.text('Stars on the main repository'), findsOneWidget);
    final kr = (server.goals.single['key_results'] as List).single as Map;
    expect(find.byKey(Key('kr-value-${kr['id']}')), findsOneWidget);
    expect(find.text('120 of 500'), findsOneWidget);
  });

  testWidgets('a goal without a key result shows a quiet note and saves',
      (tester) async {
    final server =
        AnnualServer(goals: [annualGoalJson('g1', 'Read more books')]);
    final api = await pumpAnnual(tester, server.routes());
    expect(find.byKey(const Key('flag-no_key_result-g1')), findsOneWidget);
    expect(
        find.textContaining('needs at least one key result'), findsOneWidget);
    // Another goal can still be saved.
    await tapKey(tester, 'add-goal');
    await typeKey(tester, 'goal-title-field', 'Sleep better');
    await tapKey(tester, 'goal-title-save');
    expect(api.where('POST /annual/2030/goals/bulk'), hasLength(1));
    expect(find.text('Sleep better'), findsOneWidget);
  });

  testWidgets('the fourth key result is refused with the limit message',
      (tester) async {
    final server = AnnualServer(goals: [_threeKeyResults()]);
    final api = await pumpAnnual(tester, server.routes());
    await tapKey(tester, 'add-kr-g1');
    expect(find.byKey(const Key('kr-form')), findsNothing);
    expect(find.text('A goal can have three key results. Retire one first.'),
        findsOneWidget);
    expect(api.where('POST /annual/goals/g1/key-results'), isEmpty);
  });

  testWidgets('the server limit answer shows the same message', (tester) async {
    final server = AnnualServer(goals: [
      annualGoalJson('g1', 'Get fit', keyResults: [
        keyResultJson('kr1', 'Runs', links: [linkJson('p1', 'Health')]),
      ])
    ])
      ..keyResultFailure = const ApiFailure(
          409,
          'A goal can have three key results. Retire one first.',
          'key_result_limit');
    await pumpAnnual(tester, server.routes());
    await tapKey(tester, 'add-kr-g1');
    await typeKey(tester, 'kr-metric', 'Swims');
    await typeKey(tester, 'kr-start', '0');
    await typeKey(tester, 'kr-target', '10');
    await typeKey(tester, 'kr-deadline', '2030-06-30');
    await tapKey(tester, 'kr-save');
    expect(find.byKey(const Key('kr-form')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('kr-error'))).data,
        'A goal can have three key results. Retire one first.');
  });

  testWidgets(
      'a target equal to the start and a deadline outside the year '
      'show a message on the field', (tester) async {
    final server = AnnualServer(goals: [annualGoalJson('g1', 'Get fit')]);
    final api = await pumpAnnual(tester, server.routes());
    await tapKey(tester, 'add-kr-g1');
    await typeKey(tester, 'kr-metric', 'Runs');
    await typeKey(tester, 'kr-start', '5');
    await typeKey(tester, 'kr-target', '5');
    await typeKey(tester, 'kr-deadline', '2030-12-31');
    await tapKey(tester, 'kr-save');
    expect(find.text('The target must differ from the start value.'),
        findsOneWidget);
    await typeKey(tester, 'kr-target', '50');
    await typeKey(tester, 'kr-deadline', '2031-01-15');
    await tapKey(tester, 'kr-save');
    expect(find.text('The deadline must fall in 2030.'), findsOneWidget);
    await typeKey(tester, 'kr-start', 'many');
    await tapKey(tester, 'kr-save');
    expect(find.text('The start value must be a number.'), findsOneWidget);
    expect(api.where('POST /annual/goals/g1/key-results'), isEmpty);
  });

  testWidgets('the old criteria text fills the metric of a new key result',
      (tester) async {
    final server = AnnualServer(goals: [
      annualGoalJson('g1', 'Get better at open source',
          criteria: 'Two talks and 100 stars')
    ]);
    await pumpAnnual(tester, server.routes());
    expect(find.textContaining('Two talks and 100 stars'), findsOneWidget);
    await tapKey(tester, 'use-criteria-g1');
    final field = tester.widget<TextField>(find.byKey(const Key('kr-metric')));
    expect(field.controller!.text, 'Two talks and 100 stars');
  });

  group('each term is explained once, at its first use', () {
    Future<void> expectOnce(
        WidgetTester tester, String term, Future<void> Function() open) async {
      await open();
      expect(find.byKey(Key('annual-hint-$term')), findsOneWidget,
          reason: term);
      await tapKey(tester, 'annual-hint-close-$term');
      expect(find.byKey(Key('annual-hint-$term')), findsNothing);
    }

    testWidgets('planning year, key result, automatic', (tester) async {
      final server = AnnualServer(goals: [annualGoalJson('g1', 'Get fit')]);
      await pumpAnnual(tester, server.routes());
      await expectOnce(tester, 'planningYear', () async {});
      await expectOnce(tester, 'keyResult', () => tapKey(tester, 'add-kr-g1'));
      await expectOnce(tester, 'automatic', () async {});
      await tapKey(tester, 'kr-cancel');
      // Closed hints stay closed.
      await tapKey(tester, 'add-kr-g1');
      expect(find.byKey(const Key('annual-hint-keyResult')), findsNothing);
      expect(find.byKey(const Key('annual-hint-automatic')), findsNothing);
      expect(find.byKey(const Key('annual-hint-planningYear')), findsNothing);
    });

    testWidgets('theme project and retire', (tester) async {
      final server = AnnualServer(goals: [
        annualGoalJson('g1', 'Get fit', keyResults: [
          keyResultJson('kr1', 'Runs', links: [linkJson('p1', 'Health')]),
        ])
      ], themes: themesJson(themes: [themeJson('p1', 'Health')]));
      await pumpAnnual(
          tester,
          server.routes({
            'POST /annual/key-results/kr1/retire': {
              'effect': {'key_results_retired': 1, 'links_ended': 1},
            },
          }));
      await expectOnce(tester, 'themeProject',
          () => menu(tester, 'kr-menu-kr1', 'Link themes'));
      await tapKey(tester, 'themes-cancel');
      await expectOnce(
          tester, 'retire', () => menu(tester, 'kr-menu-kr1', 'Retire'));
    });

    testWidgets('unmet', (tester) async {
      await pumpAnnual(
          tester,
          AnnualServer(year: 2031, state: 'future').routes({
            'GET /annual/2031/suggestions': suggestionsJson(goals: [
              suggestedGoalJson('o1', 'Get fit', keyResults: [
                suggestedKeyResultJson('okr1', 'Runs'),
              ]),
            ]),
          }),
          year: 2031);
      await expectOnce(tester, 'unmet', () async {});
    });
  });

  testWidgets('the year switch loads the next year', (tester) async {
    final api = await pumpAnnual(
        tester,
        AnnualServer().routes({
          'GET /annual/2031': annualPlanJson(year: 2031, state: 'future'),
          'GET /annual/2031/suggestions':
              suggestionsJson(year: 2031, fromYear: 2030, hasPlan: false),
        }));
    await tapKey(tester, 'next-year');
    expect(api.where('GET /annual/2031'), hasLength(1));
    expect(
        find.descendant(
            of: find.byKey(const Key('year-label')),
            matching: find.text('2031')),
        findsOneWidget);
  });
}
