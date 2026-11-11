import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'projects_fake.dart';

List<Map<String, Object?>> _withOrphans() => [
      classifiedJson('p1', 'Open source', label: 'theme'),
      classifiedJson('p2', 'Deleted thing', label: 'milestone', orphaned: {
        'reason': 'missing',
        'at': '2030-03-01T10:00:00Z',
      }),
      classifiedJson('p3', 'Archived thing', label: 'milestone', orphaned: {
        'reason': 'archived',
        'at': '2030-03-02T10:00:00Z',
      }),
    ];

Future<void> _openMenu(WidgetTester tester, String id) async {
  await tapKey(tester, 'menu-$id');
}

void main() {
  group('orphaned projects', () {
    testWidgets('show the stored name and the reason in plain words',
        (tester) async {
      await pumpProjects(tester, ProjectsServer(projects: _withOrphans()));
      await tapKey(tester, 'group-orphaned');
      expect(find.text('Deleted thing'), findsOneWidget);
      expect(find.text('Archived thing'), findsOneWidget);
      expect(find.textContaining('No longer in your task app. It was deleted'),
          findsOneWidget);
      expect(find.textContaining('Archived from Tefteri.'), findsOneWidget);
    });

    testWidgets('have no rename control and no chips', (tester) async {
      await pumpProjects(tester, ProjectsServer(projects: _withOrphans()));
      await tapKey(tester, 'group-orphaned');
      for (final id in ['p2', 'p3']) {
        expect(find.byKey(Key('menu-$id')), findsNothing, reason: id);
        expect(find.byKey(Key('rename-$id')), findsNothing, reason: id);
        expect(find.byKey(Key('chip-$id-theme')), findsNothing, reason: id);
      }
      // A live project still has the control.
      expect(find.byKey(const Key('menu-p1')), findsOneWidget);
    });

    testWidgets('an archived project can be restored', (tester) async {
      final server = ProjectsServer(projects: _withOrphans());
      final api = await pumpProjects(tester, server);
      await tapKey(tester, 'group-orphaned');
      expect(find.byKey(const Key('restore-p2')), findsNothing);
      await tapKey(tester, 'restore-p3');
      expect(api.where('POST /projects/p3/restore'), hasLength(1));
      expect(find.byKey(const Key('row-p3')), findsOneWidget);
      expect(find.byKey(const Key('group-orphaned')), findsOneWidget);
    });

    testWidgets('no restore button when the task app cannot restore',
        (tester) async {
      await pumpProjects(
          tester, ProjectsServer(projects: _withOrphans(), canRestore: false));
      await tapKey(tester, 'group-orphaned');
      expect(find.byKey(const Key('restore-p3')), findsNothing);
    });
  });

  group('archive', () {
    testWidgets('says what happens first, then offers Undo', (tester) async {
      final server = ProjectsServer(projects: _withOrphans());
      final api = await pumpProjects(tester, server);
      await _openMenu(tester, 'p1');
      await tapKey(tester, 'archive-p1');
      expect(find.byKey(const Key('project-archive-confirm')), findsOneWidget);
      expect(find.textContaining('hidden from the planning pickers'),
          findsOneWidget);
      expect(
          find.textContaining('You can undo this right after'), findsOneWidget);
      expect(api.where('POST /projects/p1/archive'), isEmpty);
      await tapKey(tester, 'project-archive-yes');
      expect(api.where('POST /projects/p1/archive'), hasLength(1));
      await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
      await tester.pumpAndSettle();
      expect(api.where('POST /projects/p1/restore'), hasLength(1));
    });

    testWidgets('warns when the task app cannot restore', (tester) async {
      await pumpProjects(
          tester, ProjectsServer(projects: _withOrphans(), canRestore: false));
      await _openMenu(tester, 'p1');
      await tapKey(tester, 'archive-p1');
      expect(find.textContaining('cannot restore a project from Tefteri'),
          findsOneWidget);
    });
  });

  group('rename', () {
    testWidgets('writes the new name and shows it', (tester) async {
      final server = ProjectsServer();
      final api = await pumpProjects(tester, server);
      await _openMenu(tester, 'p1');
      await tapKey(tester, 'rename-p1');
      await tester.enterText(find.byKey(const Key('rename-field')), 'OSS');
      await tester.pump();
      await tapKey(tester, 'rename-save');
      expect((api.where('PATCH /projects/p1').single.data as Map),
          {'name': 'OSS'});
      expect(find.byKey(const Key('rename-dialog')), findsNothing);
      expect(find.text('OSS'), findsOneWidget);
      expect(find.text('Open source'), findsNothing);
    });

    testWidgets('shows the error and keeps the old name when refused',
        (tester) async {
      final server = ProjectsServer()
        ..renameFailure = const ApiFailure.contract(
            502,
            'task_app_refused',
            'Your task app refused the new name. Nothing was changed. Check '
                'that you may edit the project, then try again.');
      await pumpProjects(tester, server);
      await _openMenu(tester, 'p1');
      await tapKey(tester, 'rename-p1');
      await tester.enterText(find.byKey(const Key('rename-field')), 'OSS');
      await tester.pump();
      await tapKey(tester, 'rename-save');
      expect(find.byKey(const Key('rename-dialog')), findsOneWidget);
      expect(find.textContaining('refused the new name'), findsOneWidget);
      await tapKey(tester, 'rename-cancel');
      expect(find.text('Open source'), findsOneWidget);
      expect(find.text('OSS'), findsNothing);
      expect(server.projects.first['name'], 'Open source');
    });

    testWidgets('is hidden when the task app cannot rename', (tester) async {
      await pumpProjects(tester, ProjectsServer(canRename: false));
      await _openMenu(tester, 'p1');
      expect(find.byKey(const Key('rename-p1')), findsNothing);
      expect(find.text('Rename'), findsNothing);
      // Archive is still there.
      expect(find.byKey(const Key('archive-p1')), findsOneWidget);
    });
  });

  group('suggestions', () {
    testWidgets('a project inside a routine is suggested as a routine',
        (tester) async {
      await pumpProjects(
        tester,
        ProjectsServer(projects: [
          classifiedJson('p1', 'Admin', label: 'maintenance'),
          classifiedJson('p2', 'Groceries',
              parent: 'p1',
              proposalLabel: 'maintenance',
              proposalReason: 'inside_routine'),
        ]),
      );
      expect(
        find.textContaining('Suggested: Routine, because it sits inside a '
            'routine project'),
        findsOneWidget,
      );
    });
  });
}
