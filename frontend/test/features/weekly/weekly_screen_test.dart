import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/weekly/weekly_api.dart';
import 'package:tefteri/features/weekly/weekly_screen.dart';

import '../../support/fake_api.dart';
import 'weekly_fake.dart';

final _anyDay = DateTime(2030, 3, 6);

Future<(FakeApi, WeeklyServer)> _pump(
  WidgetTester tester, {
  WeeklyServer? server,
  Duration? poll,
}) async {
  final s = server ?? WeeklyServer();
  final api = FakeApi({
    ...s.allRoutes(),
    'GET /views/week/$weekKey':
        periodJson('week', weekKey, '2030-03-11', entries: [
      {
        'id': 'e1',
        'connection_id': 'c2',
        'title': 'Standup',
        'start': DateTime(2030, 3, 5, 10).toUtc().toIso8601String(),
        'end': null,
        'all_day': false,
        'context': 'work',
        'sync_state': 'synced',
      },
    ]),
  });
  await pumpWithApi(
    tester,
    api,
    WeeklyPlanningScreen(initialDate: _anyDay),
    overrides: [weeklyPollIntervalProvider.overrideWithValue(poll)],
  );
  return (api, s);
}

/// The text with [key] that reads [data] (the checklist repeats some counts).
Finder _text(String key, String data) => find
    .byWidgetPredicate((w) => w is Text && w.key == Key(key) && w.data == data);

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starts at the first open step and lists the checklist',
      (tester) async {
    await _pump(tester);
    expect(find.text('Week of 4 Mar'), findsOneWidget);
    for (final s in WeeklyStep.values) {
      expect(find.byKey(Key('check-${s.name}')), findsOneWidget);
      expect(
          find.byKey(
              Key('${s == WeeklyStep.lookBack ? 'done' : 'open'}-${s.name}')),
          findsOneWidget);
    }
    // Nothing to look back on: the look-back counts as settled, so the
    // session opens at the project step.
    expect(find.byKey(const Key('done-lookBack')), findsOneWidget);
    expect(find.text('Choose up to 3 projects'), findsOneWidget);
    expect(_text('chosen-count', '0 of 3 chosen'), findsOneWidget);
    expect(find.byKey(const Key('checklist-progress')), findsOneWidget);
    expect(find.text('1 of 4 done'), findsOneWidget);
  });

  testWidgets('chooses at most three projects', (tester) async {
    final (api, server) = await _pump(tester);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('step-next')))
            .onPressed,
        isNull);
    expect(find.byKey(const Key('step-hint')), findsOneWidget);
    for (final id in ['p4', 'p1', 'p2']) {
      await _tap(tester, 'add-$id');
    }
    expect(server.chosen, ['p4', 'p1', 'p2']);
    expect(_text('chosen-count', '3 of 3 chosen'), findsOneWidget);
    expect(find.text('3 open tasks'), findsWidgets);
    // Full: the remaining Add button and the subproject button are off.
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('add-p3')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('new-subproject')))
            .onPressed,
        isNull);
    expect(api.where('POST /weekly/$weekKey/projects'), hasLength(3));
    // Removing one makes room again.
    await _tap(tester, 'remove-pp-p1');
    expect(_text('chosen-count', '2 of 3 chosen'), findsOneWidget);
    expect(find.byKey(const Key('add-p1')), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('add-p1')))
            .onPressed,
        isNotNull);
  });

  testWidgets('a project that the server refuses shows its message',
      (tester) async {
    final s = WeeklyServer()..chosen.add('p1');
    final api = FakeApi({
      ...s.allRoutes(),
      'POST /weekly/$weekKey/projects':
          const ApiFailure(422, 'Choose at most 3 projects.', 'invalid'),
    });
    await pumpWithApi(tester, api, WeeklyPlanningScreen(initialDate: _anyDay),
        overrides: [weeklyPollIntervalProvider.overrideWithValue(null)]);
    await _tap(tester, 'check-projects');
    await _tap(tester, 'add-p2');
    expect(find.text('Choose at most 3 projects.'), findsOneWidget);
    expect(_text('chosen-count', '1 of 3 chosen'), findsOneWidget);
  });

  testWidgets('a new subproject waits for tasks and picks them up',
      (tester) async {
    final (api, server) = await _pump(tester, poll: const Duration(seconds: 5));
    await _tap(tester, 'new-subproject');
    await tester.enterText(find.byKey(const Key('subproject-name')), 'Launch');
    await _tap(tester, 'subproject-create');
    final body =
        api.where('POST /weekly/$weekKey/subprojects').single.data! as Map;
    expect(body['name'], 'Launch');
    expect(body['parent_id'], 'p1'); // the first project is the default parent
    expect(_text('chosen-count', '1 of 3 chosen'), findsOneWidget);
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

  testWidgets('a subproject can be created under a chosen parent row',
      (tester) async {
    final (api, _) = await _pump(tester);
    await _tap(tester, 'sub-p2');
    await tester.enterText(
        find.byKey(const Key('subproject-name')), '  Beds  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final body =
        api.where('POST /weekly/$weekKey/subprojects').single.data! as Map;
    expect(body, {'parent_id': 'p2', 'name': 'Beds'});
  });

  testWidgets('searching narrows the project list', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('project-search')), 'gar');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('candidate-p2')), findsOneWidget);
    expect(find.byKey(const Key('candidate-p1')), findsNothing);
    await tester.enterText(find.byKey(const Key('project-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('no-match')), findsOneWidget);
  });

  testWidgets('carried-over tasks are shown next to their project',
      (tester) async {
    final s = WeeklyServer();
    s.projects[1]['carried'] = 2;
    await _pump(tester, server: s);
    expect(find.byKey(const Key('carried-p2')), findsOneWidget);
    expect(find.text('2 carried over from last week'), findsOneWidget);
  });

  testWidgets('tasks get a day, lose it again, and spread evenly',
      (tester) async {
    final s = WeeklyServer()..chosen.addAll(['p1', 'p2']);
    final (api, _) = await _pump(tester, server: s);
    await _tap(tester, 'check-tasks');
    expect(_text('day-progress', '0 of 3 tasks have a day'), findsOneWidget);
    expect(find.text('1 event'), findsOneWidget); // the standup on Tuesday
    await _tap(tester, 'day-p1-t1-2030-03-06');
    expect(api.where('PUT /tasks/p1-t1/schedule').single.data,
        {'date': '2030-03-06'});
    expect(_text('day-progress', '1 of 3 tasks have a day'), findsOneWidget);
    expect(find.byKey(const Key('strip-tasks-2030-03-06')), findsOneWidget);
    expect(
        (tester.widget<Text>(find.byKey(const Key('strip-tasks-2030-03-06'))))
            .data,
        '1');
    // Tapping the chosen day takes it away.
    await _tap(tester, 'day-p1-t1-2030-03-06');
    expect(api.where('DELETE /tasks/p1-t1/schedule'), hasLength(1));
    expect(_text('day-progress', '0 of 3 tasks have a day'), findsOneWidget);
    await _tap(tester, 'spread');
    expect(api.where('POST /weekly/$weekKey/spread'), hasLength(1));
    expect(_text('day-progress', '3 of 3 tasks have a day'), findsOneWidget);
    expect(find.byKey(const Key('spread')), findsNothing);
    expect(find.byKey(const Key('done-tasks')), findsOneWidget);
  });

  testWidgets('a task can be marked done from the planning page',
      (tester) async {
    final s = WeeklyServer()..chosen.add('p1');
    final (api, _) = await _pump(tester, server: s);
    await _tap(tester, 'check-tasks');
    expect(find.byKey(const Key('task-p1-t1')), findsOneWidget);
    await _tap(tester, 'task-done-p1-t1');
    expect(api.where('POST /tasks/p1-t1/complete'), hasLength(1));
    expect(find.byKey(const Key('task-p1-t1')), findsNothing);
    expect(find.byKey(const Key('task-p1-t2')), findsOneWidget);
    expect(_text('day-progress', '0 of 1 task have a day'), findsOneWidget);
  });

  testWidgets('a task can be edited from the planning page', (tester) async {
    final s = WeeklyServer()..chosen.add('p1');
    final (api, _) = await _pump(tester, server: s);
    await _tap(tester, 'check-tasks');
    await _tap(tester, 'task-edit-p1-t1');
    expect(find.byKey(const Key('task-edit-title')), findsOneWidget);
    expect(api.where('GET /tasks/p1-t1'), isNotEmpty);
    // Closing the pop-up reads the week again.
    final before = api.where('GET /weekly/$weekKey').length;
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(api.where('GET /weekly/$weekKey').length, greaterThan(before));
  });

  testWidgets('a parked task leaves the plan and can be put back',
      (tester) async {
    final s = WeeklyServer()..chosen.add('p1');
    final (api, _) = await _pump(tester, server: s);
    await _tap(tester, 'check-tasks');
    expect(find.byKey(const Key('parked-section')), findsNothing);
    await _tap(tester, 'task-park-p1-t1');
    expect(api.where('PUT /weekly/$weekKey/tasks/p1-t1/parked').single.data,
        {'parked': true});
    // Out of the list and the counts, in the closed section at the end.
    expect(find.byKey(const Key('task-p1-t1')), findsNothing);
    expect(_text('day-progress', '0 of 1 task have a day'), findsOneWidget);
    expect(find.text('Parked (1)'), findsOneWidget);
    expect(find.byKey(const Key('parked-p1-t1')), findsNothing);
    // The spread leaves it alone.
    await _tap(tester, 'spread');
    expect(s.days.containsKey('p1-t1'), isFalse);
    // Open the section and put the task back.
    await _tap(tester, 'parked-toggle');
    expect(find.byKey(const Key('parked-p1-t1')), findsOneWidget);
    await _tap(tester, 'task-unpark-p1-t1');
    expect(api.where('PUT /weekly/$weekKey/tasks/p1-t1/parked').last.data,
        {'parked': false});
    expect(find.byKey(const Key('parked-section')), findsNothing);
    expect(find.byKey(const Key('task-p1-t1')), findsOneWidget);
  });

  testWidgets('a task with a stale day says when it was due', (tester) async {
    final s = WeeklyServer()..chosen.add('p2');
    s.projects[1]['tasks'] = [
      {'id': 'p2-t1', 'title': 'Old task'},
    ];
    Map<String, Object?> stale(RequestOptions _) {
      final st = s.state();
      final plan = st['plan']! as Map<String, Object?>;
      final project = (plan['projects']! as List).first as Map<String, Object?>;
      ((project['tasks']! as List).first as Map<String, Object?>)['due_day'] =
          '2030-02-26';
      return st;
    }

    final api = FakeApi({
      ...s.allRoutes(),
      'GET /weekly/$weekKey': stale,
      'POST /weekly/$weekKey/refresh': stale,
    });
    await pumpWithApi(tester, api, WeeklyPlanningScreen(initialDate: _anyDay),
        overrides: [weeklyPollIntervalProvider.overrideWithValue(null)]);
    await _tap(tester, 'check-tasks');
    expect(find.text('Was due Tue 26 Feb'), findsOneWidget);
  });

  testWidgets('the summary groups the planned tasks by project and commits',
      (tester) async {
    final s = WeeklyServer()
      ..chosen.addAll(['p1', 'p4'])
      ..days.addAll({
        'p1-t1': '2030-03-05',
        'p1-t2': '2030-03-07',
        'p4-t1': '2030-03-06',
      });
    final (api, _) = await _pump(tester, server: s);
    await _tap(tester, 'check-finish');
    expect(find.text('Your week'), findsOneWidget);
    expect(find.byKey(const Key('total-projects')), findsOneWidget);
    expect(
        (tester.widget<Text>(find
                .descendant(
                    of: find.byKey(const Key('total-tasks')),
                    matching: find.byType(Text))
                .first))
            .data,
        '3');
    expect(find.text('2 tasks'), findsOneWidget); // Website
    expect(find.text('1 task'), findsOneWidget); // Inbox
    expect(find.text('Website task 1'), findsOneWidget);
    expect(find.text('Tue 5 Mar'), findsOneWidget);
    // Two Inbox tasks have no day: the user is told.
    expect(find.byKey(const Key('unscheduled-warning')), findsOneWidget);
    expect(
        find.text(
            '2 open tasks in these projects have no day. They are not part of this week\'s plan.'),
        findsOneWidget);
    await _tap(tester, 'commit');
    expect(api.where('POST /weekly/$weekKey/commit'), hasLength(1));
    expect(find.byKey(const Key('committed-note')), findsOneWidget);
    expect(find.byKey(const Key('done-finish')), findsOneWidget);
    // A committed plan can be opened again.
    await _tap(tester, 'change-plan');
    expect(api.where('POST /weekly/$weekKey/reopen'), hasLength(1));
    expect(find.byKey(const Key('commit')), findsOneWidget);
  });

  testWidgets('a committed plan reports what was committed and what is done',
      (tester) async {
    final s = WeeklyServer()
      ..chosen.add('p1')
      ..status = 'committed'
      ..days.addAll({'p1-t1': '2030-03-05', 'p1-t2': '2030-03-06'})
      ..doneTasks.add('p1-t9');
    await _pump(tester, server: s);
    await _tap(tester, 'check-finish');
    Text counter(String key) => tester.widget<Text>(find
        .descendant(of: find.byKey(Key(key)), matching: find.byType(Text))
        .first);
    // Two tasks are still open and one was finished since the commit.
    expect(counter('total-tasks').data, '3');
    expect(counter('total-done').data, '1');
    expect(find.text('Finished task'), findsOneWidget);
    expect(find.text('Website task 1'), findsOneWidget);
  });

  testWidgets('committing needs at least one planned task', (tester) async {
    final s = WeeklyServer()..chosen.add('p1');
    await _pump(tester, server: s);
    await _tap(tester, 'check-finish');
    expect(
        tester.widget<FilledButton>(find.byKey(const Key('commit'))).onPressed,
        isNull);
    expect(find.byKey(const Key('commit-hint')), findsOneWidget);
  });

  testWidgets('a committed plan cannot be edited from the project step',
      (tester) async {
    final s = WeeklyServer()
      ..chosen.add('p1')
      ..status = 'committed'
      ..days['p1-t1'] = '2030-03-05';
    await _pump(tester, server: s);
    await _tap(tester, 'check-projects');
    expect(find.byKey(const Key('change-plan')), findsOneWidget);
    expect(find.byKey(const Key('remove-pp-p1')), findsNothing);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('add-p2')))
            .onPressed,
        isNull);
  });

  testWidgets('the week can be changed', (tester) async {
    final (api, _) = await _pump(tester);
    await tester.tap(find.byKey(const Key('next-period')));
    await tester.pumpAndSettle();
    expect(find.text('Week of 11 Mar'), findsOneWidget);
    expect(api.where('GET /weekly/2030-03-11'), hasLength(1));
  });

  testWidgets('a load failure offers a retry', (tester) async {
    final api = FakeApi({
      'GET /weekly/$weekKey':
          const ApiFailure(502, 'The server is down.', 'backend_unavailable'),
    });
    await pumpWithApi(tester, api, WeeklyPlanningScreen(initialDate: _anyDay),
        overrides: [weeklyPollIntervalProvider.overrideWithValue(null)]);
    expect(find.text('The server is down.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reload-button')));
    await tester.pumpAndSettle();
    expect(api.where('GET /weekly/$weekKey'), hasLength(2));
  });

  testWidgets('every step fits a phone screen', (tester) async {
    final server = WeeklyServer(lookBack: sampleLookBack())
      ..chosen.addAll(['p1', 'p2'])
      ..days['p1-t1'] = '2030-03-05';
    server.projects.add(WeeklyServer.project(
        'p5', 'A project with a very long name that keeps going',
        tasks: 1));
    server.chosen.add('p5');
    await _pump(tester, server: server);
    tester.view.physicalSize = const Size(360, 900);
    await tester.pumpAndSettle();
    expect(find.textContaining('Step 1 of 4'), findsOneWidget);
    for (final step in WeeklyStep.values) {
      await tester.tap(find.byKey(Key('check-${step.name}')));
      await tester.pumpAndSettle();
      expect(find.text('Step ${step.index + 1} of 4: ${step.title}'),
          findsOneWidget);
      final e = tester.takeException();
      if (e is FlutterError) debugPrint(e.toStringDeep());
      expect(e, isNull, reason: step.name);
    }
  });

  group('archive', () {
    testWidgets('a project is archived after a confirmation', (tester) async {
      final (api, server) = await _pump(tester);
      await _tap(tester, 'check-projects');
      await _tap(tester, 'archive-p3');
      expect(find.byKey(const Key('archive-confirm')), findsOneWidget);
      expect(find.text('Archive "Taxes"?'), findsOneWidget);
      // Nothing happens until the user agrees.
      expect(api.where('POST /connections/c1/containers/p3/archive'), isEmpty);
      await _tap(tester, 'archive-cancel');
      expect(find.byKey(const Key('candidate-p3')), findsOneWidget);
      await _tap(tester, 'archive-p3');
      await _tap(tester, 'archive-yes');
      expect(api.where('POST /connections/c1/containers/p3/archive'),
          hasLength(1));
      expect(server.projects.any((p) => p['id'] == 'p3'), isFalse);
      expect(find.byKey(const Key('candidate-p3')), findsNothing);
      expect(find.byKey(const Key('candidate-p1')), findsOneWidget);
    });

    testWidgets('archiving a chosen project takes it out of the week',
        (tester) async {
      final s = WeeklyServer()..chosen.add('p1');
      await _pump(tester, server: s);
      await _tap(tester, 'check-projects');
      expect(find.byKey(const Key('chosen-pp-p1')), findsOneWidget);
      await _tap(tester, 'archive-p1');
      await _tap(tester, 'archive-yes');
      expect(find.byKey(const Key('chosen-pp-p1')), findsNothing);
      expect(find.byKey(const Key('candidate-p1')), findsNothing);
    });

    testWidgets('a refusal is shown and the project stays', (tester) async {
      final s = WeeklyServer();
      final api = FakeApi({
        ...s.allRoutes(),
        'POST /connections/c1/containers/p3/archive': const ApiFailure(
            422,
            '"Taxes" is part of a plan that you have not looked back at yet.',
            'invalid'),
      });
      await pumpWithApi(tester, api, WeeklyPlanningScreen(initialDate: _anyDay),
          overrides: [weeklyPollIntervalProvider.overrideWithValue(null)]);
      await _tap(tester, 'check-projects');
      await _tap(tester, 'archive-p3');
      await _tap(tester, 'archive-yes');
      expect(
          find.textContaining('have not looked back at yet'), findsOneWidget);
      expect(find.byKey(const Key('candidate-p3')), findsOneWidget);
    });

    testWidgets('the look-back can archive a project when it is saved',
        (tester) async {
      final s = WeeklyServer(lookBack: sampleLookBack());
      final api = FakeApi({
        ...s.allRoutes(),
        'POST /weekly/reviews/old1': {
          'entries': <Object?>[],
          'totals': {
            'weeks': 0,
            'committed_projects': 0,
            'done_projects': 0,
            'committed_tasks': 0,
            'done_tasks': 0,
          },
        },
      });
      await pumpWithApi(tester, api, WeeklyPlanningScreen(initialDate: _anyDay),
          overrides: [weeklyPollIntervalProvider.overrideWithValue(null)]);
      // Off by default, and offered for a finished project too.
      expect(
          tester
              .widget<SwitchListTile>(find.byKey(const Key('archive-op1')))
              .value,
          isFalse);
      await _tap(tester, 'archive-op1');
      expect(
          tester
              .widget<SwitchListTile>(find.byKey(const Key('archive-op1')))
              .value,
          isTrue);
      await _tap(tester, 'save-look-back');
      final body = api.where('POST /weekly/reviews/old1').single.data! as Map;
      final answers = body['projects'] as List;
      expect((answers[0] as Map)['archive'], isTrue);
      expect((answers[1] as Map)['archive'], isFalse);
      // Archiving happens on the server; nothing is archived by this tap alone.
      expect(api.where('POST /connections/c1/containers/op1/archive'), isEmpty);
    });
  });

  group('look back', () {
    testWidgets('asks about each project and shows the counters',
        (tester) async {
      final s = WeeklyServer(lookBack: sampleLookBack());
      await _pump(tester, server: s);
      expect(find.text('How did the week of 25 Feb go?'), findsOneWidget);
      // Website is all done: no question. Garden has two tasks left.
      expect(find.byKey(const Key('look-finished-op1')), findsOneWidget);
      expect(find.byKey(const Key('carry-op2')), findsOneWidget);
      expect(find.text('Prune roses'), findsOneWidget);
      expect(find.text('1 of 3 tasks done'), findsOneWidget);
      expect(find.byKey(const Key('carry-op1')), findsNothing);
      Text counter(String key) => tester.widget<Text>(find
          .descendant(of: find.byKey(Key(key)), matching: find.byType(Text))
          .first);
      expect(counter('look-committed').data, '2');
      expect(counter('look-done').data, '1');
      // Counting Garden as done anyway moves the second counter.
      await _tap(tester, 'finished-op2');
      expect(counter('look-done').data, '2');
    });

    testWidgets('saves the decisions and then shows the earlier weeks',
        (tester) async {
      final s = WeeklyServer(lookBack: sampleLookBack());
      final api = FakeApi({
        ...s.allRoutes(),
        'POST /weekly/reviews/old1': (RequestOptions o) {
          s.lookBack = sampleLookBack(reviewed: true);
          return {
            'entries': [
              {
                'plan_id': 'old1',
                'week_start': '2030-02-25',
                'committed_projects': 2,
                'done_projects': 2,
                'committed_tasks': 7,
                'done_tasks': 5,
                'reflection': 'Too much gardening.',
                'projects': [
                  {'name': 'Website', 'done': true},
                  {'name': 'Garden', 'done': true},
                ],
              },
            ],
            'totals': {
              'weeks': 1,
              'committed_projects': 2,
              'done_projects': 2,
              'committed_tasks': 7,
              'done_tasks': 5,
            },
          };
        },
      });
      await pumpWithApi(tester, api, WeeklyPlanningScreen(initialDate: _anyDay),
          overrides: [weeklyPollIntervalProvider.overrideWithValue(null)]);
      await _tap(tester, 'backlog-op2');
      await _tap(tester, 'finished-op2');
      await tester.enterText(
          find.byKey(const Key('reflection')), 'Too much gardening.');
      await _tap(tester, 'save-look-back');
      final body = api.where('POST /weekly/reviews/old1').single.data! as Map;
      expect(body['reflection'], 'Too much gardening.');
      expect(body['projects'], [
        {
          'plan_project_id': 'op1',
          'finished_anyway': false,
          'leftover': 'carry',
          'archive': false,
        },
        {
          'plan_project_id': 'op2',
          'finished_anyway': true,
          'leftover': 'backlog',
          'archive': false,
        },
      ]);
      // The end of the look-back: the earlier weeks with two counters each.
      expect(find.text('Look back is done'), findsOneWidget);
      expect(find.byKey(const Key('history-old1')), findsOneWidget);
      expect(find.text('Week of 25 Feb'), findsOneWidget);
      expect(
          tester
              .widget<Text>(find
                  .descendant(
                      of: find.byKey(const Key('committed-old1')),
                      matching: find.byType(Text))
                  .first)
              .data,
          '2');
      expect(find.text('“Too much gardening.”'), findsOneWidget);
      expect(find.byKey(const Key('done-lookBack')), findsOneWidget);
    });

    testWidgets('the look-back can be skipped', (tester) async {
      final s = WeeklyServer(lookBack: sampleLookBack());
      final (api, _) = await _pump(tester, server: s);
      await _tap(tester, 'skip-look-back');
      expect(api.where('POST /weekly/$weekKey/skip-look-back'), hasLength(1));
      expect(find.text('Choose up to 3 projects'), findsOneWidget);
      await _tap(tester, 'check-lookBack');
      expect(find.text('Look-back skipped'), findsOneWidget);
    });

    testWidgets('history says how realistic the plans are', (tester) async {
      final s = WeeklyServer()
        ..history = {
          'entries': [
            for (var i = 0; i < 3; i++)
              {
                'plan_id': 'h$i',
                'week_start': '2030-02-${18 - 7 * i + (i == 2 ? 14 : 0)}',
                'committed_projects': 3,
                'done_projects': 1,
                'committed_tasks': 9,
                'done_tasks': 3,
                'reflection': '',
                'projects': <Object?>[],
              },
          ],
          'totals': {
            'weeks': 3,
            'committed_projects': 9,
            'done_projects': 3,
            'committed_tasks': 27,
            'done_tasks': 9,
          },
        };
      await _pump(tester, server: s);
      await _tap(tester, 'check-lookBack');
      expect(find.text('Over 3 weeks'), findsOneWidget);
      expect(find.byKey(const Key('realism-note')), findsOneWidget);
      expect(find.textContaining('plan more than you finish'), findsOneWidget);
    });
  });
}
