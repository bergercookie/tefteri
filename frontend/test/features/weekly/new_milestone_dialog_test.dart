import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'weekly_fake.dart';
import 'weekly_pump.dart';

WeeklyServer _server() => WeeklyServer(projects: [
      WeeklyServer.project('tA', 'Open source', kind: 'theme'),
      WeeklyServer.project('tB', 'Home', kind: 'theme'),
    ])
      ..themes = [
        WeeklyServer.theme('tA', 'Open source'),
        WeeklyServer.theme('tB', 'Home'),
      ];

Future<void> _open(WidgetTester tester) => tapKey(tester, 'new-milestone');

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pump();
}

String _typed(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

void main() {
  testWidgets('asks for a name and a done-state and gives an example',
      (tester) async {
    await pumpWeekly(tester, _server());
    await _open(tester);
    expect(find.byKey(const Key('new-milestone-dialog')), findsOneWidget);
    expect(find.byKey(const Key('milestone-name')), findsOneWidget);
    expect(find.byKey(const Key('milestone-done-state')), findsOneWidget);
    expect(find.textContaining('ship the login flow'), findsOneWidget);
    expect(find.text('Under theme'), findsOneWidget);
  });

  testWidgets('an empty done-state shows the hint and keeps what was typed',
      (tester) async {
    final api = await pumpWeekly(tester, _server());
    await _open(tester);
    await _type(tester, 'milestone-name', 'Login flow');
    await tapKey(tester, 'milestone-create');
    expect(find.byKey(const Key('milestone-done-hint')), findsOneWidget);
    expect(find.textContaining('Say when this milestone is finished'),
        findsOneWidget);
    expect(_typed(tester, 'milestone-name'), 'Login flow');
    expect(find.byKey(const Key('new-milestone-dialog')), findsOneWidget);
    // The task app is not called.
    expect(api.where('POST /weekly/$weekKey/milestones'), isEmpty);
    // A blank done-state counts as empty.
    await _type(tester, 'milestone-done-state', '   ');
    await tapKey(tester, 'milestone-create');
    expect(api.where('POST /weekly/$weekKey/milestones'), isEmpty);
  });

  testWidgets('a refused request shows the reason and keeps the text',
      (tester) async {
    await pumpWeekly(tester, _server(), extra: {
      'POST /weekly/$weekKey/milestones': const ApiFailure(
          502,
          'Your task app refused to create the project. Nothing was created.',
          'backend_unavailable'),
    });
    await _open(tester);
    await _type(tester, 'milestone-name', 'Login flow');
    await _type(tester, 'milestone-done-state', 'Users sign in');
    await tapKey(tester, 'milestone-create');
    expect(find.byKey(const Key('milestone-error')), findsOneWidget);
    expect(find.textContaining('Nothing was created'), findsOneWidget);
    expect(_typed(tester, 'milestone-name'), 'Login flow');
    expect(_typed(tester, 'milestone-done-state'), 'Users sign in');
    // Nothing was added to the plan.
    expect(find.byKey(const Key('new-milestone-dialog')), findsOneWidget);
    await tapKey(tester, 'milestone-cancel');
    expect(find.byKey(const Key('chosen-pp-new1')), findsNothing);
  });

  testWidgets('success adds the milestone to the plan', (tester) async {
    final api = await pumpWeekly(tester, _server());
    await _open(tester);
    await tester.tap(find.byKey(const Key('milestone-theme')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    await _type(tester, 'milestone-name', '  Beds  ');
    await _type(tester, 'milestone-done-state', ' The beds are planted ');
    await tapKey(tester, 'milestone-create');
    expect(api.where('POST /weekly/$weekKey/milestones').single.data, {
      'parent_id': 'tB',
      'name': 'Beds',
      'done_state': 'The beds are planted',
    });
    expect(find.byKey(const Key('new-milestone-dialog')), findsNothing);
    expect(find.byKey(const Key('chosen-pp-new1')), findsOneWidget);
    expect(find.text('Done when: The beds are planted'), findsWidgets);
    expect(textKey('chosen-count', '1 milestone chosen'), findsOneWidget);
  });

  testWidgets('the milestone of a theme row starts under that theme',
      (tester) async {
    final api = await pumpWeekly(tester, _server());
    await tapKey(tester, 'new-milestone-tA');
    await _type(tester, 'milestone-name', 'Launch');
    await _type(tester, 'milestone-done-state', 'It is live');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
        (api.where('POST /weekly/$weekKey/milestones').single.data
            as Map)['parent_id'],
        'tA');
  });

  testWidgets('a new milestone waits for tasks and picks them up',
      (tester) async {
    final server = _server();
    final api =
        await pumpWeekly(tester, server, poll: const Duration(seconds: 5));
    await tapKey(tester, 'new-milestone');
    await _type(tester, 'milestone-name', 'Launch');
    await _type(tester, 'milestone-done-state', 'It is live');
    await tapKey(tester, 'milestone-create');
    expect(find.byKey(const Key('no-tasks-pp-new1')), findsOneWidget);
    expect(find.byKey(const Key('open-project-pp-new1')), findsOneWidget);
    expect(find.text('No open tasks yet'), findsOneWidget);
    // Tasks are added in the task app. The next poll shows them.
    (server.projects.last['tasks']! as List)
      ..add({'id': 'new1-t1', 'title': 'Write copy'})
      ..add({'id': 'new1-t2', 'title': 'Pick fonts'});
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('no-tasks-pp-new1')), findsNothing);
    expect(find.text('2 open tasks'), findsWidgets);
    expect(api.where('POST /weekly/$weekKey/refresh'), isNotEmpty);
  });
}
