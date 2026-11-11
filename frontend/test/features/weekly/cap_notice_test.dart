import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weekly_fake.dart';
import 'weekly_pump.dart';

WeeklyServer _server({bool focus = false}) {
  final s = WeeklyServer(projects: [
    WeeklyServer.project('tA', 'Open source', kind: 'theme'),
    WeeklyServer.project('tB', 'Home', kind: 'theme'),
    for (var i = 1; i <= 4; i++)
      WeeklyServer.project('m$i', 'Milestone $i',
          tasks: 1,
          theme: i == 4 ? 'tB' : 'tA',
          themeName: i == 4 ? 'Home' : 'Open source',
          inFocus: i != 4),
  ]);
  s.focusKnown = focus;
  s.themes = [
    WeeklyServer.theme('tA', 'Open source', inFocus: focus ? true : null),
    WeeklyServer.theme('tB', 'Home', inFocus: focus ? false : null),
  ];
  return s;
}

void main() {
  testWidgets(
      'the fourth milestone shows a quiet warning and the commit '
      'still works', (tester) async {
    final s = _server();
    final api = await pumpWeekly(tester, s);
    for (final id in ['m1', 'm2', 'm3']) {
      await tapKey(tester, 'add-$id');
    }
    expect(find.byKey(const Key('cap-notice')), findsNothing);
    await tapKey(tester, 'add-m4');
    // Nothing is refused.
    expect(s.chosen, ['m1', 'm2', 'm3', 'm4']);
    expect(find.byKey(const Key('cap-notice')), findsOneWidget);
    expect(find.textContaining('You chose 4 milestones'), findsOneWidget);
    expect(find.textContaining('usually holds up to 3'), findsOneWidget);
    // The warning is not an error banner and the next step is open.
    expect(find.byKey(const Key('error-banner')), findsNothing);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('step-next')))
            .onPressed,
        isNotNull);
    await openStep(tester, 'finish');
    expect(find.byKey(const Key('cap-notice')), findsOneWidget);
    await tapKey(tester, 'commit');
    expect(api.where('POST /weekly/$weekKey/commit'), hasLength(1));
    expect(find.byKey(const Key('committed-note')), findsOneWidget);
  });

  testWidgets('removing one hides the warning', (tester) async {
    final s = _server()..chosen.addAll(['m1', 'm2', 'm3', 'm4']);
    s.started = true;
    await pumpWeekly(tester, s);
    await openStep(tester, 'projects');
    expect(find.byKey(const Key('cap-notice')), findsOneWidget);
    await tapKey(tester, 'remove-pp-m4');
    expect(find.byKey(const Key('cap-notice')), findsNothing);
    expect(textKey('chosen-count', '3 milestones chosen'), findsOneWidget);
  });

  testWidgets('a milestone under a non-focus theme shows "outside focus"',
      (tester) async {
    final s = _server(focus: true)..chosen.addAll(['m1', 'm4']);
    await pumpWeekly(tester, s);
    await openStep(tester, 'projects');
    expect(
        find.descendant(
            of: find.byKey(const Key('chosen-pp-m4')),
            matching: find.byKey(const Key('outside-focus'))),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('chosen-pp-m1')),
            matching: find.byKey(const Key('outside-focus'))),
        findsNothing);
    expect(find.text('Outside focus'), findsWidgets);
  });

  testWidgets('without focus data no milestone is tagged', (tester) async {
    final s = _server()..chosen.addAll(['m1', 'm4']);
    await pumpWeekly(tester, s);
    await openStep(tester, 'projects');
    expect(find.byKey(const Key('outside-focus')), findsNothing);
    expect(find.text('Outside focus'), findsNothing);
  });
}
