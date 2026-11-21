import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tefteri/features/projects/work_tag.dart';

import '../../support/fake_api.dart';
import 'projects_fake.dart';

List<Map<String, Object?>> _tree({bool work = false}) => [
      classifiedJson('p1', 'Open source',
          label: 'theme', tasks: 4, subprojects: 2, isWork: work),
      classifiedJson('p2', 'Website',
          parent: 'p1',
          label: 'milestone',
          parentTheme: 'p1',
          tasks: 3,
          inWork: work),
      classifiedJson('p3', 'Home', label: 'theme'),
      classifiedJson('p4', 'Garden',
          parent: 'p3', label: 'milestone', parentTheme: 'p3'),
      classifiedJson('p5', 'Chores', label: 'maintenance'),
    ];

void main() {
  testWidgets('only a theme has the Work chip', (tester) async {
    await pumpProjects(tester, ProjectsServer(projects: _tree()));
    expect(find.byKey(const Key('work-p1')), findsOneWidget);
    expect(find.byKey(const Key('work-p3')), findsOneWidget);
    for (final id in ['p2', 'p4', 'p5']) {
      expect(find.byKey(Key('work-$id')), findsNothing, reason: id);
    }
    expect(tester.widget<FilterChip>(find.byKey(const Key('work-p1'))).selected,
        isFalse);
    // Nothing is marked: there is no pill and no briefcase.
    expect(find.byIcon(Icons.work_outline), findsNWidgets(2)); // the two chips
  });

  testWidgets('the chip marks a theme as work and saves it', (tester) async {
    var work = false;
    final api = await pumpProjects(
      tester,
      ProjectsServer(projects: _tree()),
      extra: {
        'PUT /projects/p1/work': (o) {
          work = (o.data as Map)['work'] as bool;
          return classifiedJson('p1', 'Open source',
              label: 'theme', isWork: work);
        },
        // The list is read again after the save.
        'GET /projects/classification': (_) => {
              'connections': [
                {
                  'connection_id': 'c1',
                  'name': 'Tasks',
                  'status': 'ok',
                  'last_sync_outcome': 'ok',
                  'capabilities': {
                    'rename': true,
                    'restore': true,
                    'move_tasks': true
                  },
                  'projects': _tree(work: work),
                }
              ],
              'unsorted_count': 0,
            },
      },
    );
    await tester.tap(find.byKey(const Key('work-p1')));
    await tester.pumpAndSettle();
    expect(api.where('PUT /projects/p1/work').single.data, {'work': true});
    expect(find.byKey(const Key('work-pill-p1')), findsOneWidget);
    // What is under the theme shows the briefcase, not the pill.
    expect(find.byKey(const Key('work-icon-p2')), findsOneWidget);
    expect(find.byKey(const Key('work-pill-p2')), findsNothing);
    expect(find.byKey(const Key('work-pill-p3')), findsNothing);
    expect(find.byKey(const Key('work-icon-p4')), findsNothing);
    expect(tester.widget<FilterChip>(find.byKey(const Key('work-p1'))).selected,
        isTrue);
  });

  testWidgets('a failed save says so and changes nothing', (tester) async {
    await pumpProjects(
      tester,
      ProjectsServer(projects: _tree()),
      extra: {
        'PUT /projects/p1/work':
            const ApiFailure(500, 'Could not save.', 'error'),
      },
    );
    await tester.tap(find.byKey(const Key('work-p1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work-pill-p1')), findsNothing);
    expect(tester.widget<FilterChip>(find.byKey(const Key('work-p1'))).selected,
        isFalse);
  });

  group('WorkTag', () {
    FakeApi api(List<Map<String, Object?>> projects) => FakeApi({
          'GET /projects/classification': {
            'connections': [
              {
                'connection_id': 'c1',
                'name': 'Tasks',
                'status': 'ok',
                'last_sync_outcome': 'ok',
                'capabilities': {
                  'rename': true,
                  'restore': true,
                  'move_tasks': true
                },
                'projects': projects,
              }
            ],
            'unsorted_count': 0,
          },
        });

    testWidgets('shows the pill or the briefcase for a work project only',
        (tester) async {
      await pumpWithApi(
        tester,
        api(_tree(work: true)),
        const Scaffold(
            body: Column(children: [
          WorkTag(projectId: 'p1', pill: true),
          WorkTag(projectId: 'p2'),
          WorkTag(projectId: 'p3', pill: true),
          WorkTag(projectId: 'p4'),
        ])),
      );
      expect(find.byKey(const Key('work-pill-p1')), findsOneWidget);
      expect(find.byKey(const Key('work-icon-p2')), findsOneWidget);
      expect(find.byKey(const Key('work-pill-p3')), findsNothing);
      expect(find.byKey(const Key('work-icon-p4')), findsNothing);
    });

    testWidgets('shows nothing when the call fails', (tester) async {
      await pumpWithApi(
        tester,
        FakeApi({}),
        const Scaffold(body: WorkTag(projectId: 'p1', pill: true)),
      );
      expect(find.byKey(const Key('work-pill-p1')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
