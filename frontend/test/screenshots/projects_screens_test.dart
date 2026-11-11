@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/projects/projects_screen.dart';

import '../features/projects/projects_fake.dart';
import 'screenshot_helper.dart';

/// A tree that has never been labelled: every project shows a suggestion.
List<Map<String, Object?>> _unsorted() => [
      classifiedJson('p1', 'Open source', tasks: 4, subprojects: 2),
      classifiedJson('p2', 'Website', parent: 'p1', tasks: 3),
      classifiedJson('p3', 'Library', parent: 'p1', tasks: 1),
      classifiedJson('p4', 'Home', tasks: 2, subprojects: 2),
      classifiedJson('p5', 'Garden', parent: 'p4', tasks: 5),
      classifiedJson('p6', 'Taxes', parent: 'p4', tasks: 2, inPlan: true),
      classifiedJson('p7', 'Groceries', tasks: 6),
      classifiedJson('p8', 'Old ideas', tasks: 9),
    ];

/// The same tree after the user has sorted it.
List<Map<String, Object?>> _sorted() => [
      classifiedJson('p1', 'Open source',
          label: 'theme', tasks: 4, subprojects: 2),
      classifiedJson('p2', 'Website',
          parent: 'p1', label: 'milestone', parentTheme: 'p1', tasks: 3),
      classifiedJson('p3', 'Library',
          parent: 'p1', label: 'milestone', parentTheme: 'p1', tasks: 1),
      classifiedJson('p4', 'Home', label: 'theme', tasks: 2, subprojects: 2),
      classifiedJson('p5', 'Garden',
          parent: 'p4', label: 'milestone', parentTheme: 'p4', tasks: 5),
      classifiedJson('p6', 'Taxes',
          parent: 'p4',
          label: 'milestone',
          parentTheme: 'p4',
          tasks: 2,
          inPlan: true),
      classifiedJson('p7', 'Groceries', label: 'maintenance', tasks: 6),
      classifiedJson('p8', 'Old ideas', label: 'ignored', tasks: 9),
      classifiedJson('p9', 'Moving house 2028',
          label: 'milestone',
          orphaned: {'reason': 'missing', 'at': '2030-03-01T10:00:00Z'}),
      classifiedJson('p10', 'Garage clear-out',
          parent: 'p4',
          label: 'milestone',
          parentTheme: 'p4',
          orphaned: {'reason': 'archived', 'at': '2030-03-04T10:00:00Z'}),
    ];

Future<void> _pump(WidgetTester tester, ProjectsServer server,
    {Size size = const Size(1100, 900)}) async {
  SharedPreferences.setMockInitialValues({});
  await pumpScreen(
      tester,
      FakeApi({
        ...server.allRoutes(),
        // A task app is connected, so the screen does not ask for one.
        'GET /connections': [connectionJson('c1', 'tasks', 'Vikunja')],
      }),
      const ProjectsScreen(),
      size: size);
}

void main() {
  testWidgets('first visit with suggestions', (tester) async {
    await _pump(tester, ProjectsServer(projects: _unsorted()));
    await saveScreenshot('projects-suggestions');
  });

  testWidgets('preview before saving', (tester) async {
    await _pump(tester, ProjectsServer(projects: _unsorted()));
    await tester.tap(find.byKey(const Key('accept-suggestions')));
    await tester.pumpAndSettle();
    await saveScreenshot('projects-effect');
  });

  testWidgets('sorted tree', (tester) async {
    await _pump(tester, ProjectsServer(projects: _sorted()),
        size: const Size(1100, 1000));
    await saveScreenshot('projects-sorted');
  });

  testWidgets('no longer in your task app', (tester) async {
    await _pump(tester, ProjectsServer(projects: _sorted()),
        size: const Size(1100, 1100));
    final group = find.byKey(const Key('group-orphaned'));
    await tester.ensureVisible(group);
    await tester.pump();
    await tester.tap(group);
    await tester.pumpAndSettle();
    await saveScreenshot('projects-orphaned');
  });

  testWidgets('broken connection', (tester) async {
    await _pump(
        tester,
        ProjectsServer(
            projects: _sorted(),
            status: 'error',
            lastSyncOutcome: 'unreachable'));
    await saveScreenshot('projects-connection-problem');
  });

  testWidgets('phone width', (tester) async {
    await _pump(tester, ProjectsServer(projects: _unsorted()),
        size: const Size(390, 844));
    await saveScreenshot('projects-phone');
  });
}
