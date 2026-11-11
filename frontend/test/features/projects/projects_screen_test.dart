import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'projects_fake.dart';

/// A tree with every group: theme, milestone, routine, ignored, one unsorted
/// and one project that left the task app.
List<Map<String, Object?>> _sorted() => [
      classifiedJson('p1', 'Open source',
          label: 'theme', tasks: 4, subprojects: 2),
      classifiedJson('p2', 'Website',
          parent: 'p1', label: 'milestone', parentTheme: 'p1', tasks: 3),
      classifiedJson('p3', 'Chores', label: 'maintenance'),
      classifiedJson('p4', 'Old ideas', label: 'ignored'),
      classifiedJson('p5', 'Garden'),
      classifiedJson('p6', 'Lost project', label: 'theme', orphaned: {
        'reason': 'missing',
        'at': '2030-03-01T10:00:00Z',
      }),
    ];

void main() {
  testWidgets('suggestions are shown, marked, and explained', (tester) async {
    await pumpProjects(tester, ProjectsServer());
    expect(find.text('6 projects need a label'), findsOneWidget);
    for (final id in ['p1', 'p2', 'p3', 'p4', 'p5', 'p6']) {
      expect(find.byKey(Key('suggested-$id')), findsOneWidget, reason: id);
    }
    expect(find.text('Suggested: Theme, because it is at the top level.'),
        findsWidgets);
    expect(
        find.text('Suggested: Milestone, because it sits inside another '
            'project.'),
        findsWidgets);
    // Nothing is saved until the user chooses.
    final chip =
        tester.widget<ChoiceChip>(find.byKey(const Key('chip-p1-theme')));
    expect(chip.selected, isFalse);
    expect(find.byKey(const Key('accept-suggestions')), findsOneWidget);
    // The one-time hint names the Routine term.
    expect(find.textContaining('Routine (maintenance)'), findsOneWidget);
  });

  testWidgets('every group has one plain sentence', (tester) async {
    await pumpProjects(tester, ProjectsServer(projects: _sorted()));
    for (final g in ['unsorted', 'themes', 'routines', 'ignored', 'orphaned']) {
      expect(find.byKey(Key('group-title-$g')), findsOneWidget, reason: g);
      expect(find.byKey(Key('group-sentence-$g')), findsOneWidget, reason: g);
    }
    expect(find.text('No longer in your task app (1)'), findsOneWidget);
    expect(find.text('Routines (1)'), findsOneWidget);
    expect(find.textContaining('repeats and never finishes'), findsWidgets);
    // The group of lost projects starts collapsed.
    expect(find.byKey(const Key('row-p6')), findsNothing);
    await tapKey(tester, 'group-orphaned');
    expect(find.byKey(const Key('row-p6')), findsOneWidget);
  });

  testWidgets('milestones sit under their theme and name it', (tester) async {
    await pumpProjects(tester, ProjectsServer(projects: _sorted()));
    expect(find.text('Theme: Open source  ·  3 open tasks'), findsOneWidget);
    final theme = tester.getTopLeft(find.byKey(const Key('name-p1')));
    final milestone = tester.getTopLeft(find.byKey(const Key('name-p2')));
    expect(milestone.dx, greaterThan(theme.dx));
    expect(milestone.dy, greaterThan(theme.dy));
  });

  testWidgets('Accept suggestions saves them all after a preview',
      (tester) async {
    final server = ProjectsServer();
    final api = await pumpProjects(tester, server);
    await tapKey(tester, 'accept-suggestions');
    expect(find.byKey(const Key('effect-dialog')), findsOneWidget);
    // The preview wrote nothing.
    expect(server.projects.every((p) => p['label'] == null), isTrue);
    await tapKey(tester, 'effect-confirm');
    final puts = api.where('PUT /projects/labels');
    expect(puts, hasLength(2));
    final body = puts.last.data as Map;
    expect(body['dry_run'], false);
    expect(body['source'], 'suggestion');
    expect((body['changes'] as List), hasLength(6));
    expect(server.projects.map((p) => p['label']),
        ['theme', 'milestone', 'milestone', 'theme', 'milestone', 'theme']);
    expect(find.byKey(const Key('accept-card')), findsNothing);
    expect(find.byKey(const Key('all-sorted')), findsOneWidget);
    expect(find.byKey(const Key('group-title-themes')), findsOneWidget);
    expect(find.byKey(const Key('group-title-unsorted')), findsNothing);
  });

  testWidgets('one tap on a chip changes one project', (tester) async {
    final server = ProjectsServer();
    final api = await pumpProjects(tester, server);
    await tapKey(tester, 'chip-p6-maintenance');
    final puts = api.where('PUT /projects/labels');
    expect(puts, hasLength(1));
    final body = puts.single.data as Map;
    expect(body['dry_run'], false);
    expect(body['source'], 'user');
    expect(body['changes'], [
      {'id': 'p6', 'label': 'maintenance'}
    ]);
    expect(server.projects.last['label'], 'maintenance');
    // The project moved to Routines; the other five are still unsorted.
    expect(find.text('Routines (1)'), findsOneWidget);
    expect(find.text('5 projects need a label'), findsOneWidget);
    // Accepting the suggestion of a project is one tap too.
    await tapKey(tester, 'chip-p1-theme');
    final accepted = api.where('PUT /projects/labels').last.data as Map;
    expect(accepted['source'], 'suggestion');
  });

  testWidgets('a failed save says what happened and keeps the label',
      (tester) async {
    final server = ProjectsServer()
      ..saveFailure = const ApiFailure.contract(
          502, 'task_app_refused', 'Tefteri could not save. Try again.');
    await pumpProjects(tester, server);
    await tapKey(tester, 'chip-p6-maintenance');
    expect(find.byKey(const Key('error-banner')), findsOneWidget);
    expect(find.text('Tefteri could not save. Try again.'), findsOneWidget);
    expect(find.text('6 projects need a label'), findsOneWidget);
  });

  testWidgets('search and collapse work with 300 projects', (tester) async {
    // 20 themes with 14 milestones each.
    final projects = <Map<String, Object?>>[];
    for (var t = 0; t < 20; t++) {
      projects.add(
          classifiedJson('t$t', 'Theme $t', label: 'theme', subprojects: 14));
      for (var m = 0; m < 14; m++) {
        projects.add(classifiedJson('t$t-m$m', 'Milestone $t.$m',
            parent: 't$t', label: 'milestone', parentTheme: 't$t'));
      }
    }
    expect(projects, hasLength(300));
    await pumpProjects(tester, ProjectsServer(projects: projects));
    expect(
        find.text('All 300 projects are labelled. Change any of them with '
            'one tap.'),
        findsOneWidget);
    expect(find.byKey(const Key('row-t0')), findsOneWidget);
    expect(find.byKey(const Key('row-t0-m0')), findsOneWidget);

    // Collapse one theme: its milestones leave the list.
    await tapKey(tester, 'toggle-t0');
    expect(find.byKey(const Key('row-t0-m0')), findsNothing);
    expect(find.byKey(const Key('row-t0')), findsOneWidget);
    await tapKey(tester, 'toggle-t0');
    expect(find.byKey(const Key('row-t0-m0')), findsOneWidget);

    // Collapse all, then expand all.
    await tapKey(tester, 'collapse-all');
    expect(find.byKey(const Key('row-t0-m0')), findsNothing);
    expect(find.byKey(const Key('row-t1')), findsOneWidget);
    await tapKey(tester, 'collapse-all');
    expect(find.byKey(const Key('row-t0-m0')), findsOneWidget);

    // Search finds a deep project, with the theme above it, and nothing else.
    await tester.enterText(
        find.byKey(const Key('project-search')), 'Milestone 17.9');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('row-t17-m9')), findsOneWidget);
    expect(find.byKey(const Key('row-t17')), findsOneWidget);
    expect(find.byKey(const Key('row-t3')), findsNothing);
    expect(find.byKey(const Key('row-t17-m8')), findsNothing);

    await tester.enterText(find.byKey(const Key('project-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('no-match')), findsOneWidget);
  });

  testWidgets('an empty task app offers Sync now and Create a theme',
      (tester) async {
    final api =
        await pumpProjects(tester, ProjectsServer(projects: []), extra: {
      'POST /sync': <Object?>[],
    });
    expect(find.byKey(const Key('no-projects-yet')), findsOneWidget);
    expect(find.byKey(const Key('sync-now')), findsOneWidget);
    expect(find.byKey(const Key('create-theme')), findsOneWidget);
    await tapKey(tester, 'sync-now');
    expect(api.where('POST /sync'), hasLength(1));
  });

  testWidgets('a theme is created in the task app with the label theme',
      (tester) async {
    final server = ProjectsServer();
    final api = await pumpProjects(tester, server);
    await tapKey(tester, 'create-theme');
    expect(find.byKey(const Key('create-theme-dialog')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('create-theme-name')), 'Health');
    await tester.pump();
    await tapKey(tester, 'create-theme-save');
    expect((api.where('POST /projects').single.data as Map), {
      'connection_id': 'c1',
      'name': 'Health',
      'parent_id': null,
      'label': 'theme',
    });
    expect(find.text('Health'), findsOneWidget);
  });

  testWidgets('a load error offers a retry', (tester) async {
    await pumpProjects(tester, ProjectsServer(), extra: {
      'GET /projects/classification':
          const ApiFailure.contract(500, 'boom', 'Something broke.'),
    });
    expect(find.byKey(const Key('projects-error')), findsOneWidget);
    expect(find.byKey(const Key('projects-retry')), findsOneWidget);
  });

  testWidgets('works on a phone width and in dark mode', (tester) async {
    await pumpProjects(tester, ProjectsServer(),
        size: const Size(360, 800), brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('accept-suggestions')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('chip-p1-theme')), 200,
        scrollable: find.descendant(
            of: find.byKey(const Key('projects-list')),
            matching: find.byType(Scrollable)));
    // The chips sit under the name, inside the screen.
    final chip = tester.getRect(find.byKey(const Key('chip-p1-theme')));
    final name = tester.getRect(find.byKey(const Key('name-p1')));
    expect(chip.top, greaterThan(name.bottom));
    expect(chip.right, lessThanOrEqualTo(360));
    await tapKey(tester, 'chip-p1-milestone');
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting several projects labels them with one preview',
      (tester) async {
    final server = ProjectsServer();
    final api = await pumpProjects(tester, server);
    await tapKey(tester, 'select-toggle');
    await tapKey(tester, 'select-p5');
    await tapKey(tester, 'select-p6');
    expect(find.text('2 selected'), findsOneWidget);
    await tapKey(tester, 'bulk-ignored');
    expect(find.text('2 from Unsorted to Ignored'), findsOneWidget);
    await tapKey(tester, 'effect-confirm');
    expect(server.projects.last['label'], 'ignored');
    expect((api.where('PUT /projects/labels').last.data as Map)['changes'],
        hasLength(2));
  });
}
