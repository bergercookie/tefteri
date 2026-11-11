import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/projects/projects_models.dart';

import 'weekly_fake.dart';
import 'weekly_pump.dart';

WeeklyServer _server() => WeeklyServer(projects: [
      WeeklyServer.project('tA', 'Open source', kind: 'theme'),
      WeeklyServer.project('m1', 'Login flow',
          tasks: 2,
          theme: 'tA',
          themeName: 'Open source',
          doneState: 'Users sign in with a passkey',
          inFocus: false),
    ])
      ..focusKnown = true
      ..themes = [WeeklyServer.theme('tA', 'Open source', inFocus: false)];

void main() {
  testWidgets('the picker explains its words once and the hint can be closed',
      (tester) async {
    await pumpWeekly(tester, _server());
    // Folded to one line at first.
    expect(
        find.byKey(const Key('term-hint-open-weekly-picker')), findsOneWidget);
    expect(find.byKey(const Key('term-hint-weekly-picker')), findsNothing);
    await tapKey(tester, 'term-hint-open-weekly-picker');
    expect(find.byKey(const Key('term-hint-weekly-picker')), findsOneWidget);
    for (final w in ['Milestone', 'Done-state', 'Committed', 'Parked']) {
      expect(find.textContaining('$w: ', findRichText: true), findsOneWidget,
          reason: w);
    }
    await tapKey(tester, 'term-hint-close-weekly-picker');
    expect(find.byKey(const Key('term-hint-weekly-picker')), findsNothing);
    expect(find.byKey(const Key('term-hint-open-weekly-picker')), findsNothing);
  });

  testWidgets('outside focus is explained where it first shows',
      (tester) async {
    final s = _server()..chosen.add('m1');
    await pumpWeekly(tester, s);
    await openStep(tester, 'projects');
    expect(find.byKey(const Key('outside-focus')), findsOneWidget);
    await tapKey(tester, 'term-hint-open-weekly-outside-focus');
    expect(
        find.textContaining('not one of the themes you chose for this month',
            findRichText: true),
        findsOneWidget);
  });

  testWidgets('the review explains rollover and decide later', (tester) async {
    await pumpWeekly(tester, WeeklyServer(lookBack: sampleLookBack()));
    await tapKey(tester, 'term-hint-open-weekly-review');
    expect(
        find.textContaining('Rollover: ', findRichText: true), findsOneWidget);
    expect(find.textContaining('Decide later: ', findRichText: true),
        findsOneWidget);
  });

  test('a connection reports whether its task app can move tasks', () {
    ConnectionProjects conn(Map<String, Object?> caps) =>
        ConnectionProjects.fromJson({
          'connection_id': 'c1',
          'name': 'Vikunja',
          'capabilities': caps,
          'projects': const <Object?>[],
        });
    expect(conn({'rename': true, 'move_tasks': true}).canMoveTasks, isTrue);
    expect(conn({'rename': true}).canMoveTasks, isFalse);
  });

  for (final dark in [false, true]) {
    testWidgets('every step fits a phone in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      final s = _server()
        ..chosen.add('m1')
        ..days['m1-t1'] = '2030-03-05';
      s.lookBack = sampleLookBack(projects: [
        lookBackProject('op2', 'Garden, with a very long name that keeps going',
            doneState: 'A long sentence that says when the milestone is done',
            needsRescope: true,
            rollover: 2),
        lookBackProject('op3', 'Loose milestone', theme: null),
      ]);
      await pumpWeekly(tester, s,
          size: const Size(360, 800),
          brightness: dark ? Brightness.dark : Brightness.light);
      for (final step in ['lookBack', 'projects', 'tasks', 'finish']) {
        await openStep(tester, step);
        expect(tester.takeException(), isNull, reason: step);
      }
    });
  }
}
