import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'weekly_fake.dart';
import 'weekly_pump.dart';

/// Two themes with milestones, one empty theme, a milestone with no theme and
/// an unsorted project.
WeeklyServer _server({bool focus = false}) {
  final s = WeeklyServer(projects: [
    WeeklyServer.project('tA', 'Open source', kind: 'theme'),
    WeeklyServer.project('tB', 'Home', kind: 'theme'),
    WeeklyServer.project('tC', 'Reading', kind: 'theme'),
    WeeklyServer.project('m1', 'Login flow',
        tasks: 2,
        theme: 'tA',
        themeName: 'Open source',
        doneState: 'Users sign in with a passkey',
        inFocus: false),
    WeeklyServer.project('m2', 'Garden beds',
        tasks: 1,
        theme: 'tB',
        themeName: 'Home',
        doneState: 'The beds are planted',
        state: 'parked',
        rollover: 1,
        inFocus: true),
    WeeklyServer.project('m3', 'Loose milestone', tasks: 3),
    WeeklyServer.project('u1', 'Old idea', tasks: 4, kind: 'unsorted'),
  ]);
  s.focusKnown = focus;
  s.themes = [
    WeeklyServer.theme('tA', 'Open source', inFocus: focus ? false : null),
    WeeklyServer.theme('tB', 'Home', inFocus: focus ? true : null),
    WeeklyServer.theme('tC', 'Reading', inFocus: focus ? false : null),
  ];
  return s;
}

void main() {
  testWidgets(
      'milestones are grouped under their theme, then no theme and '
      'unsorted', (tester) async {
    await pumpWeekly(tester, _server());
    expect(find.byKey(const Key('group-th-tA')), findsOneWidget);
    expect(find.byKey(const Key('group-th-tB')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('group-th-tA')),
            matching: find.byKey(const Key('candidate-m1'))),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('group-th-tB')),
            matching: find.byKey(const Key('candidate-m2'))),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('group-no-theme')),
            matching: find.byKey(const Key('candidate-m3'))),
        findsOneWidget);
    expect(find.text('No theme'), findsOneWidget);
    // The done-state is shown with the milestone.
    expect(
        find.text('Done when: Users sign in with a passkey'), findsOneWidget);
    // Unsorted projects say that picking one labels it milestone.
    expect(
        find.descendant(
            of: find.byKey(const Key('group-unsorted')),
            matching: find.byKey(const Key('candidate-u1'))),
        findsOneWidget);
    expect(find.byKey(const Key('unsorted-hint')), findsOneWidget);
    expect(find.textContaining('labels it milestone'), findsOneWidget);
  });

  testWidgets('picking an unsorted project sends it like any other',
      (tester) async {
    final api = await pumpWeekly(tester, _server());
    await tapKey(tester, 'add-u1');
    expect(api.where('POST /weekly/$weekKey/projects').single.data,
        {'container_id': 'u1'});
    expect(find.byKey(const Key('chosen-pp-u1')), findsOneWidget);
  });

  testWidgets('a parked milestone is marked and its rollover count shows',
      (tester) async {
    await pumpWeekly(tester, _server());
    expect(find.byKey(const Key('parked-m2')), findsOneWidget);
    expect(find.text('Parked'), findsOneWidget);
    expect(find.text('Rolled over once'), findsOneWidget);
    expect(find.byKey(const Key('parked-m1')), findsNothing);
  });

  testWidgets('a committed milestone says so and cannot be added twice',
      (tester) async {
    final s = _server()..chosen.add('m1');
    final api = await pumpWeekly(tester, s);
    await openStep(tester, 'projects');
    expect(
        find.descendant(
            of: find.byKey(const Key('chosen-mark-m1')),
            matching: find.text('Already committed')),
        findsOneWidget);
    expect(find.byKey(const Key('add-m1')), findsNothing);
    expect(api.where('POST /weekly/$weekKey/projects'), isEmpty);
  });

  testWidgets('an open decision shows a reminder that does not block',
      (tester) async {
    final s = _server();
    s.projects.firstWhere((p) => p['id'] == 'm3')['decision_open'] = true;
    final api = await pumpWeekly(tester, s);
    expect(find.byKey(const Key('decision-open-m3')), findsOneWidget);
    expect(find.byKey(const Key('decision-open-m1')), findsNothing);
    await tapKey(tester, 'add-m3');
    expect(api.where('POST /weekly/$weekKey/projects'), hasLength(1));
    expect(s.chosen, ['m3']);
  });

  testWidgets('an empty theme offers to create a milestone', (tester) async {
    await pumpWeekly(tester, _server());
    expect(find.byKey(const Key('empty-theme-th-tC')), findsOneWidget);
    expect(find.byKey(const Key('create-milestone-tC')), findsOneWidget);
    // The theme with milestones has no such line.
    expect(find.byKey(const Key('empty-theme-th-tA')), findsNothing);
    await tapKey(tester, 'create-milestone-tC');
    expect(find.byKey(const Key('new-milestone-dialog')), findsOneWidget);
    // The dialog starts under the theme that was tapped.
    final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const Key('milestone-theme')));
    expect(dropdown.initialValue, 'tC');
  });

  testWidgets(
      'an empty picker explains theme and milestone and offers a '
      'first step', (tester) async {
    await pumpWeekly(tester, WeeklyServer(projects: []));
    expect(find.byKey(const Key('no-projects')), findsOneWidget);
    expect(
        find.textContaining('A theme is a long-running home'), findsOneWidget);
    expect(find.textContaining('A milestone is a small project'), findsWidgets);
    expect(find.text('Label a project as theme'), findsOneWidget);
    expect(find.text('Create a theme'), findsOneWidget);
    await tapKey(tester, 'label-a-theme');
    expect(find.text('projects page'), findsOneWidget);
  });

  testWidgets(
      'with focus data the focus themes come first and are '
      'highlighted', (tester) async {
    await pumpWeekly(tester, _server(focus: true));
    // Home is in focus: it is listed before Open source, which comes first
    // without focus data.
    expect(
        topOf(tester, 'group-th-tB'), lessThan(topOf(tester, 'group-th-tA')));
    expect(find.byKey(const Key('focus-badge-th-tB')), findsOneWidget);
    expect(find.byKey(const Key('focus-badge-th-tA')), findsNothing);
    expect(find.byKey(const Key('focus-badge-th-tC')), findsNothing);
  });

  testWidgets(
      'without focus data nothing is highlighted and the order is '
      'the server\'s', (tester) async {
    await pumpWeekly(tester, _server());
    expect(find.byKey(const Key('focus-badge-th-tA')), findsNothing);
    expect(find.byKey(const Key('focus-badge-th-tB')), findsNothing);
    expect(
        topOf(tester, 'group-th-tA'), lessThan(topOf(tester, 'group-th-tB')));
  });

  testWidgets('searching narrows the groups', (tester) async {
    await pumpWeekly(tester, _server());
    await tester.enterText(find.byKey(const Key('project-search')), 'login');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('candidate-m1')), findsOneWidget);
    expect(find.byKey(const Key('candidate-m2')), findsNothing);
    expect(find.byKey(const Key('group-th-tC')), findsNothing);
    await tester.enterText(find.byKey(const Key('project-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('no-match')), findsOneWidget);
  });

  testWidgets('the picker still works when the themes cannot be read',
      (tester) async {
    await pumpWeekly(tester, _server(), extra: {
      'GET /weekly/$weekKey/themes':
          const ApiFailure(502, 'The task app is down.', 'backend_unavailable'),
    });
    expect(find.byKey(const Key('candidate-m1')), findsOneWidget);
    expect(find.byKey(const Key('group-th-tA')), findsOneWidget);
  });
}
