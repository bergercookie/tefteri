import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/core/planning_models.dart';
import 'package:tefteri/features/notes/note_editor_screen.dart';
import 'package:tefteri/features/notes/notes_screen.dart';
import 'package:tefteri/features/notes/task_notes_sheet.dart';

import '../../support/fake_api.dart';

Map<String, Object?> _note(String id, String title,
        {String kind = 'custom', String body = '', List<String>? taskIds}) =>
    {
      'id': id,
      'connection_id': 'c3',
      'kind': kind,
      'title': title,
      'body': body,
      'note_date': null,
      'context': 'work',
      'effective_context': 'work',
      'sync_state': 'synced',
      if (taskIds != null) 'task_ids': taskIds,
    };

Object? _byKind(RequestOptions o) => switch (o.queryParameters['kind']) {
      'process' => [
          _note('n2', 'Release process', kind: 'process', body: '1. Tag')
        ],
      'custom' => [_note('n1', 'Server setup', body: 'Install it')],
      _ => <Object?>[],
    };

/// Pumps [location] in a router that holds the notes routes, with a fake
/// backend; returns the router so the test can check the location.
Future<GoRouter> _pumpRouter(
    WidgetTester tester, FakeApi api, String location) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: location, routes: [
    GoRoute(path: '/notes', builder: (_, __) => const NotesScreen()),
    GoRoute(
      path: '/notes/new',
      builder: (_, s) => NoteEditorScreen(
          taskId: s.uri.queryParameters['task'],
          kind: s.uri.queryParameters['kind'] ?? 'custom'),
    ),
    GoRoute(
      path: '/notes/:id',
      builder: (_, s) => NoteEditorScreen(
          key: ValueKey(s.pathParameters['id']),
          noteId: s.pathParameters['id']),
    ),
    GoRoute(
      path: '/task',
      builder: (context, __) => Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const Key('open-sheet'),
            onPressed: () => showTaskNotes(
                context,
                PlanTask.fromJson(
                    taskJson('t1', 'Release v1') as Map<String, dynamic>)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ]);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = api;
  await tester.pumpWidget(ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter r) =>
    r.routerDelegate.currentConfiguration.uri.toString();

void main() {
  testWidgets('lists documentation and process notes and filters by kind',
      (tester) async {
    final api = FakeApi({'GET /notes': _byKind});
    await _pumpRouter(tester, api, '/notes');
    expect(find.text('Server setup'), findsOneWidget);
    expect(find.text('Release process'), findsOneWidget);
    expect(find.text('Process - 1. Tag'), findsOneWidget);
    await tester.tap(find.text('Processes'));
    await tester.pumpAndSettle();
    expect(find.text('Server setup'), findsNothing);
    expect(find.text('Release process'), findsOneWidget);
    expect(api.requests.every((r) => r.query['context'] == 'all'), isTrue);
  });

  testWidgets('a tap opens the note editor', (tester) async {
    final api = FakeApi({
      'GET /notes': _byKind,
      'GET /notes/n1':
          _note('n1', 'Server setup', body: 'Install it', taskIds: ['t1']),
    });
    final router = await _pumpRouter(tester, api, '/notes');
    await tester.tap(find.text('Server setup'));
    await tester.pumpAndSettle();
    expect(_location(router), '/notes/n1');
    expect(find.text('Install it'), findsOneWidget);
    expect(find.text('Linked to 1 task(s).'), findsOneWidget);
  });

  testWidgets('saves an edited note', (tester) async {
    final api = FakeApi({
      'GET /notes/n1': _note('n1', 'Server setup', body: 'old', taskIds: []),
      'PATCH /notes/n1': _note('n1', 'Server setup', body: 'new', taskIds: []),
    });
    await _pumpRouter(tester, api, '/notes/n1');
    await tester.enterText(find.byKey(const Key('note-body')), 'new');
    await tester.tap(find.byKey(const Key('note-save')));
    await tester.pumpAndSettle();
    expect(api.where('PATCH /notes/n1').single.data,
        {'title': 'Server setup', 'body': 'new'});
    expect(find.text('Note saved to your notes app.'), findsOneWidget);
  });

  testWidgets('a failed save names the cause and keeps the text',
      (tester) async {
    final api = FakeApi({
      'GET /notes/n1': _note('n1', 'Server setup', body: 'old', taskIds: []),
      'PATCH /notes/n1': const ApiFailure(
          409,
          'The item changed in Trilium. Sync to see the new version.',
          'remote_conflict'),
    });
    await _pumpRouter(tester, api, '/notes/n1');
    await tester.enterText(find.byKey(const Key('note-body')), 'mine');
    await tester.tap(find.byKey(const Key('note-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('changed in Trilium'), findsOneWidget);
    expect(find.text('mine'), findsOneWidget);
  });

  testWidgets('creates a process note linked to a task', (tester) async {
    final api = FakeApi({
      'POST /notes': _note('n9', 'Release steps',
          kind: 'process', body: '1. Tag', taskIds: ['t1']),
      'GET /notes/n9': _note('n9', 'Release steps',
          kind: 'process', body: '1. Tag', taskIds: ['t1']),
    });
    final router =
        await _pumpRouter(tester, api, '/notes/new?task=t1&kind=process');
    expect(find.text('This note is linked to the task.'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('note-title')), 'Release steps');
    await tester.enterText(find.byKey(const Key('note-body')), '1. Tag');
    await tester.tap(find.byKey(const Key('note-save')));
    await tester.pumpAndSettle();
    expect(api.where('POST /notes').single.data, {
      'title': 'Release steps',
      'body': '1. Tag',
      'kind': 'process',
      'task_ids': ['t1'],
    });
    expect(_location(router), '/notes/n9');
  });

  testWidgets('a new note needs a title', (tester) async {
    final api = FakeApi({});
    await _pumpRouter(tester, api, '/notes/new');
    await tester.tap(find.byKey(const Key('note-save')));
    await tester.pumpAndSettle();
    expect(find.text('Write a title.'), findsOneWidget);
    expect(api.where('POST /notes'), isEmpty);
  });

  testWidgets('deletes a note after confirmation', (tester) async {
    final api = FakeApi({
      'GET /notes': _byKind,
      'GET /notes/n1': _note('n1', 'Server setup', taskIds: []),
      'DELETE /notes/n1': const NoContent(),
    });
    final router = await _pumpRouter(tester, api, '/notes/n1');
    await tester.tap(find.byKey(const Key('note-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('note-delete-confirm')));
    await tester.pumpAndSettle();
    expect(api.where('DELETE /notes/n1'), hasLength(1));
    expect(_location(router), '/notes');
  });

  group('notes of a task', () {
    testWidgets('lists linked notes and opens one', (tester) async {
      final api = FakeApi({
        'GET /tasks/t1/notes': [_note('n1', 'Server setup')],
        'GET /notes/n1': _note('n1', 'Server setup', taskIds: ['t1']),
      });
      final router = await _pumpRouter(tester, api, '/task');
      await tester.tap(find.byKey(const Key('open-sheet')));
      await tester.pumpAndSettle();
      expect(find.text('Notes for "Release v1"'), findsOneWidget);
      await tester.tap(find.byKey(const Key('task-note-n1')));
      await tester.pumpAndSettle();
      expect(_location(router), '/notes/n1');
    });

    testWidgets('new note for the task opens the editor with the task',
        (tester) async {
      final api = FakeApi({'GET /tasks/t1/notes': <Object?>[]});
      final router = await _pumpRouter(tester, api, '/task');
      await tester.tap(find.byKey(const Key('open-sheet')));
      await tester.pumpAndSettle();
      expect(find.text('No notes are linked to this task.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('task-note-new')));
      await tester.pumpAndSettle();
      expect(_location(router), '/notes/new?task=t1');
    });

    testWidgets('remove link deletes only the link', (tester) async {
      var linked = true;
      final api = FakeApi({
        'GET /tasks/t1/notes': (RequestOptions _) =>
            linked ? [_note('n1', 'Server setup')] : <Object?>[],
        'DELETE /tasks/t1/notes/n1': (RequestOptions _) {
          linked = false;
          return const NoContent();
        },
      });
      await _pumpRouter(tester, api, '/task');
      await tester.tap(find.byKey(const Key('open-sheet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unlink-n1')));
      await tester.pumpAndSettle();
      expect(api.where('DELETE /tasks/t1/notes/n1'), hasLength(1));
      expect(api.where('DELETE /notes/n1'), isEmpty);
      expect(find.text('No notes are linked to this task.'), findsOneWidget);
    });
  });
}
