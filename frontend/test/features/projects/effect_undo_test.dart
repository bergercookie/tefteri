import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'projects_fake.dart';

void main() {
  testWidgets('the dialog shows the numbers before anything is saved',
      (tester) async {
    final projects = ProjectsServer.defaultProjects();
    projects[1] =
        classifiedJson('p2', 'Website', parent: 'p1', tasks: 3, inPlan: true);
    final server = ProjectsServer(projects: projects);
    final api = await pumpProjects(tester, server);
    await tapKey(tester, 'accept-suggestions');
    expect(find.text('6 projects change.'), findsOneWidget);
    expect(find.text('3 from Unsorted to Theme'), findsOneWidget);
    expect(find.text('3 from Unsorted to Milestone'), findsOneWidget);
    expect(find.textContaining('1 of them is in a committed weekly plan'),
        findsOneWidget);
    // The only call so far is the dry run.
    final puts = api.where('PUT /projects/labels');
    expect(puts, hasLength(1));
    expect((puts.single.data as Map)['dry_run'], true);
    // Cancel saves nothing.
    await tapKey(tester, 'effect-cancel');
    expect(api.where('PUT /projects/labels'), hasLength(1));
    expect(server.projects.every((p) => p['label'] == null), isTrue);
  });

  testWidgets('the snackbar offers Undo, and Undo calls the API',
      (tester) async {
    final server = ProjectsServer();
    final api = await pumpProjects(tester, server);
    await tapKey(tester, 'accept-suggestions');
    await tapKey(tester, 'effect-confirm');
    // The snackbar stays for ten seconds.
    final bar = tester.widget<SnackBar>(find.byKey(const Key('undo-snackbar')));
    expect(bar.duration, const Duration(seconds: 10));
    expect(find.text('Accepted 6 suggestions.'), findsOneWidget);
    expect(server.projects.first['label'], 'theme');

    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    final undo = api.where('POST /projects/labels/undo');
    expect(undo, hasLength(1));
    expect((undo.single.data as Map)['batch_id'], 'b1');
    expect(server.projects.every((p) => p['label'] == null), isTrue);
    expect(find.text('6 projects need a label'), findsOneWidget);
  });

  testWidgets('Undo is still there in the recent changes after the snackbar',
      (tester) async {
    final server = ProjectsServer();
    final api = await pumpProjects(tester, server);
    await tapKey(tester, 'chip-p6-ignored');
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('undo-snackbar')), findsNothing);
    await tapKey(tester, 'recent-toggle');
    await tapKey(tester, 'recent-undo-0');
    expect(api.where('POST /projects/labels/undo'), hasLength(1));
    expect(server.projects.last['label'], isNull);
  });

  testWidgets('a second undo of the same change shows the server message',
      (tester) async {
    final server = ProjectsServer();
    await pumpProjects(tester, server);
    await tapKey(tester, 'chip-p6-ignored');
    server.undone.add('b1'); // undone elsewhere
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(find.text('This change was already undone.'), findsOneWidget);
  });
}
