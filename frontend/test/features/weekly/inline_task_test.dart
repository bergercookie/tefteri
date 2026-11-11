import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'weekly_fake.dart';
import 'weekly_pump.dart';

WeeklyServer _server({int tasks = 0}) => WeeklyServer(projects: [
      WeeklyServer.project('m1', 'Login flow',
          tasks: tasks, doneState: 'Users sign in with a passkey'),
    ])
      ..chosen.add('m1');

void main() {
  testWidgets('an empty milestone shows an empty state with an add field',
      (tester) async {
    await pumpWeekly(tester, _server());
    await openStep(tester, 'tasks');
    expect(find.byKey(const Key('no-tasks-msg-pp-m1')), findsOneWidget);
    expect(find.byKey(const Key('add-task-field-pp-m1')), findsOneWidget);
    expect(find.byKey(const Key('add-task-pp-m1')), findsOneWidget);
    // The done-state of the milestone is shown here too.
    expect(
        find.text('Done when: Users sign in with a passkey'), findsOneWidget);
  });

  testWidgets('an added task appears and has no day yet', (tester) async {
    final api = await pumpWeekly(tester, _server());
    await openStep(tester, 'tasks');
    await tester.enterText(
        find.byKey(const Key('add-task-field-pp-m1')), '  Draw the screens ');
    await tapKey(tester, 'add-task-pp-m1');
    expect(api.where('POST /weekly/$weekKey/projects/pp-m1/tasks').single.data,
        {'title': 'Draw the screens'});
    expect(find.byKey(const Key('task-m1-t1')), findsOneWidget);
    expect(find.text('Draw the screens'), findsOneWidget);
    // It is not committed until it has a day.
    expect(textKey('day-progress', '0 of 1 task have a day'), findsOneWidget);
    expect(find.text('1 task still without a day.'), findsOneWidget);
    expect(find.byKey(const Key('no-tasks-msg-pp-m1')), findsNothing);
    // The field stays for the next task, and is empty again.
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('add-task-field-pp-m1')))
            .controller!
            .text,
        isEmpty);
    // A day makes it part of the week.
    await tapKey(tester, 'day-m1-t1-2030-03-06');
    expect(textKey('day-progress', '1 of 1 task have a day'), findsOneWidget);
  });

  testWidgets('a task can be added to a milestone that has tasks',
      (tester) async {
    final api = await pumpWeekly(tester, _server(tasks: 1));
    await openStep(tester, 'tasks');
    expect(find.byKey(const Key('no-tasks-msg-pp-m1')), findsNothing);
    await tester.enterText(
        find.byKey(const Key('add-task-field-pp-m1')), 'Write tests');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
        api.where('POST /weekly/$weekKey/projects/pp-m1/tasks'), hasLength(1));
    expect(find.byKey(const Key('task-m1-t2')), findsOneWidget);
  });

  testWidgets('a refused task shows why and keeps the text', (tester) async {
    await pumpWeekly(tester, _server(), extra: {
      'POST /weekly/$weekKey/projects/pp-m1/tasks': const ApiFailure(
          502,
          'Your task app did not answer. No task was created.',
          'backend_unavailable'),
    });
    await openStep(tester, 'tasks');
    await tester.enterText(
        find.byKey(const Key('add-task-field-pp-m1')), 'Draw the screens');
    await tapKey(tester, 'add-task-pp-m1');
    expect(find.byKey(const Key('add-task-error-pp-m1')), findsOneWidget);
    expect(find.textContaining('No task was created'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('add-task-field-pp-m1')))
            .controller!
            .text,
        'Draw the screens');
  });

  testWidgets('the project step has the field in its empty notice too',
      (tester) async {
    final api = await pumpWeekly(tester, _server());
    await openStep(tester, 'projects');
    expect(find.byKey(const Key('no-tasks-pp-m1')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('add-task-field-pp-m1')), 'Draw the screens');
    await tapKey(tester, 'add-task-pp-m1');
    expect(
        api.where('POST /weekly/$weekKey/projects/pp-m1/tasks'), hasLength(1));
    expect(find.byKey(const Key('no-tasks-pp-m1')), findsNothing);
  });

  testWidgets('tasks that were not picked show under "Not this week"',
      (tester) async {
    final s = _server(tasks: 2);
    final api = await pumpWeekly(tester, s);
    await openStep(tester, 'tasks');
    expect(find.byKey(const Key('parked-section')), findsNothing);
    expect(find.byTooltip('Not this week'), findsNWidgets(2));
    expect(find.byTooltip('Park for later'), findsNothing);
    await tapKey(tester, 'task-park-m1-t1');
    expect(api.where('PUT /weekly/$weekKey/tasks/m1-t1/parked').single.data,
        {'parked': true});
    expect(find.text('Not this week (1)'), findsOneWidget);
    expect(find.textContaining('Parked ('), findsNothing);
    await tapKey(tester, 'parked-toggle');
    expect(find.textContaining('Not committed this week'), findsOneWidget);
    expect(find.byKey(const Key('parked-m1-t1')), findsOneWidget);
    await tapKey(tester, 'task-unpark-m1-t1');
    expect(find.byKey(const Key('task-m1-t1')), findsOneWidget);
  });
}
