import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weekly_fake.dart';
import 'weekly_pump.dart';

void main() {
  testWidgets('the expected switch of a recommit is sent with the answer',
      (tester) async {
    final s = WeeklyServer(lookBack: sampleLookBack());
    final api = await pumpWeekly(tester, s, extra: {
      'POST /weekly/reviews/old1': reviewAnswer(),
    });
    // Not offered before a recommit is chosen, and not for the other choices.
    expect(find.byKey(const Key('expected-op2')), findsNothing);
    await tapKey(tester, 'decision-park-op2');
    expect(find.byKey(const Key('expected-op2')), findsNothing);
    await tapKey(tester, 'decision-recommit-op2');
    expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('expected-op2')))
            .value,
        isFalse);
    expect(find.textContaining('does not trigger the re-scope hint'),
        findsOneWidget);
    await tapKey(tester, 'expected-op2');
    await tapKey(tester, 'save-look-back');
    final answers = (api.where('POST /weekly/reviews/old1').single.data!
        as Map)['projects'] as List;
    expect(answers[1], {
      'plan_project_id': 'op2',
      'decision': 'recommit',
      'expected': true,
      'mark_done': false,
      'archive': false,
    });
  });

  testWidgets('the expected marker is not sent for another choice',
      (tester) async {
    final s = WeeklyServer(lookBack: sampleLookBack());
    final api = await pumpWeekly(tester, s, extra: {
      'POST /weekly/reviews/old1': reviewAnswer(),
    });
    await tapKey(tester, 'decision-recommit-op2');
    await tapKey(tester, 'expected-op2');
    await tapKey(tester, 'decision-park-op2');
    await tapKey(tester, 'save-look-back');
    final answers = (api.where('POST /weekly/reviews/old1').single.data!
        as Map)['projects'] as List;
    expect((answers[1] as Map)['expected'], isFalse);
    expect((answers[1] as Map)['decision'], 'park');
  });

  testWidgets('the nudge shows in the review result and never blocks',
      (tester) async {
    final s = WeeklyServer(lookBack: sampleLookBack());
    await pumpWeekly(tester, s, extra: {
      'POST /weekly/reviews/old1': (o) {
        s.lookBack = sampleLookBack(reviewed: true);
        return reviewAnswer(notices: [
          'Next week\'s plan was committed. It is a draft again, so that '
              'Garden can be added.',
        ], nudges: [
          {'milestone_id': 'm-op2', 'name': 'Garden'},
        ]);
      },
    });
    await tapKey(tester, 'decision-recommit-op2');
    await tapKey(tester, 'save-look-back');
    expect(find.byKey(const Key('review-result')), findsOneWidget);
    expect(find.byKey(const Key('result-nudge-m-op2')), findsOneWidget);
    expect(
        find.textContaining('shrink it, split it or close it'), findsOneWidget);
    expect(find.byKey(const Key('review-notice')), findsOneWidget);
    expect(find.textContaining('It is a draft again'), findsOneWidget);
    // The way on is open.
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('step-next')))
            .onPressed,
        isNotNull);
  });

  testWidgets('no nudge and no result card when nothing needs one',
      (tester) async {
    final s = WeeklyServer(lookBack: sampleLookBack());
    await pumpWeekly(tester, s, extra: {
      'POST /weekly/reviews/old1': (o) {
        s.lookBack = sampleLookBack(reviewed: true);
        return reviewAnswer();
      },
    });
    await tapKey(tester, 'save-look-back');
    expect(find.byKey(const Key('review-result')), findsNothing);
  });

  testWidgets(
      'the review card shows the nudge for a milestone that needs '
      'rescoping', (tester) async {
    final s = WeeklyServer(
        lookBack: sampleLookBack(projects: [
      lookBackProject('op2', 'Garden', needsRescope: true, rollover: 2),
    ]));
    await pumpWeekly(tester, s);
    expect(find.byKey(const Key('look-rescope-op2')), findsOneWidget);
    expect(find.text('Rolled over 2 times'), findsOneWidget);
  });

  testWidgets('the picker shows the nudge and committing is not blocked',
      (tester) async {
    final s = WeeklyServer(projects: [
      WeeklyServer.project('tA', 'Open source', kind: 'theme'),
      WeeklyServer.project('m1', 'Login flow',
          tasks: 1,
          theme: 'tA',
          themeName: 'Open source',
          rollover: 2,
          needsRescope: true),
    ])
      ..themes = [WeeklyServer.theme('tA', 'Open source')];
    final api = await pumpWeekly(tester, s);
    expect(find.byKey(const Key('rescope-m1')), findsOneWidget);
    expect(
        find.textContaining('shrink it, split it or close it'), findsOneWidget);
    await tapKey(tester, 'add-m1');
    // Also shown on the card of the week, and the plan can still be committed.
    expect(find.byKey(const Key('rescope-pp-m1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('check-finish')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('summary-rescope-pp-m1')), findsOneWidget);
    await tapKey(tester, 'commit');
    expect(api.where('POST /weekly/$weekKey/commit'), hasLength(1));
  });
}
