import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'planner_helpers.dart';

Map<String, Object?> _project(String id, String remote, String name,
        [String? parent]) =>
    {
      'id': id,
      'remote_id': remote,
      'name': name,
      'parent_remote_id': parent,
    };

FakeApi _api({Map<String, Object?> extra = const {}}) => plannerApi(extra: {
      'GET /connections': [connectionJson('c1', 'tasks', 'Home tasks')],
      'GET /connections/c1/containers': [
        _project('k2', '2', 'Website'),
        _project('k1', '1', 'Inbox'),
        _project('k3', '3', 'Launch', '2'),
      ],
      'GET /connections/c1/labels': ['Errands', 'Home', 'Urgent'],
      'POST /tasks': (RequestOptions o) =>
          taskJson('t9', '${(o.data as Map)['title']}'),
      'PUT /tasks/t9/schedule': dueTask('t9', 'x'),
      ...extra,
    });

Future<FakeApi> _open(WidgetTester tester, {FakeApi? api}) async {
  final a = api ?? _api();
  await pumpPlanner(tester, a);
  await tester.tap(find.byKey(const Key('new-task-button')));
  await settle(tester);
  return a;
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pump();
}

Future<void> _create(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('new-task-create')));
  await settle(tester);
}

bool _createEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const Key('new-task-create')))
        .onPressed !=
    null;

String _projectText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('new-task-project')))
    .controller!
    .text;

Map<String, Object?> _body(FakeApi api) =>
    Map<String, Object?>.from(api.where('POST /tasks').single.data! as Map);

void main() {
  testWidgets('the button opens the dialog, which starts at the first project',
      (tester) async {
    await _open(tester);
    expect(find.byKey(const Key('new-task-dialog')), findsOneWidget);
    // Projects are ordered by their path; a subproject follows its parent.
    expect(_projectText(tester), 'Inbox');
    expect(_createEnabled(tester), isFalse); // no title yet
    await _type(tester, 'new-task-title', '  ');
    expect(_createEnabled(tester), isFalse);
    await _type(tester, 'new-task-title', 'Buy bread');
    expect(_createEnabled(tester), isTrue);
  });

  testWidgets('a task with only a title goes to the first project',
      (tester) async {
    final api = await _open(tester);
    await _type(tester, 'new-task-title', '  Buy bread ');
    await _create(tester);
    expect(_body(api),
        {'connection_id': 'c1', 'title': 'Buy bread', 'container_id': 'k1'});
    expect(api.where('PUT /tasks/t9/schedule'), isEmpty);
    expect(find.byKey(const Key('new-task-dialog')), findsNothing);
    expect(find.text('Created "Buy bread" in Inbox.'), findsOneWidget);
    // The planner reloads its list.
    expect(api.where('GET /tasks').length, greaterThan(1));
  });

  testWidgets('the project is chosen from suggestions that narrow as you type',
      (tester) async {
    final api = await _open(tester);
    await _type(tester, 'new-task-title', 'Ship it');
    await _type(tester, 'new-task-project', 'launch');
    await settle(tester);
    // Only the subproject matches, and its path says where it is.
    expect(find.byKey(const Key('project-option-k3')), findsOneWidget);
    expect(find.byKey(const Key('project-option-k1')), findsNothing);
    expect(find.text('Website › Launch'), findsOneWidget);
    expect(_createEnabled(tester), isFalse); // typed, not chosen yet
    expect(find.text('Choose a project from the list.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('project-option-k3')));
    await settle(tester);
    expect(_projectText(tester), 'Website › Launch');
    expect(_createEnabled(tester), isTrue);
    await _create(tester);
    expect(_body(api)['container_id'], 'k3');
    expect(find.text('Created "Ship it" in Website › Launch.'), findsOneWidget);
  });

  testWidgets('an empty project field lists every project', (tester) async {
    await _open(tester);
    await _type(tester, 'new-task-project', '');
    await settle(tester);
    for (final id in ['k1', 'k2', 'k3']) {
      expect(find.byKey(Key('project-option-$id')), findsOneWidget);
    }
  });

  testWidgets('a project name that matches nothing cannot be used',
      (tester) async {
    await _open(tester);
    await _type(tester, 'new-task-title', 'x');
    await _type(tester, 'new-task-project', 'zzz');
    await settle(tester);
    expect(find.byKey(const Key('project-option-k1')), findsNothing);
    expect(_createEnabled(tester), isFalse);
  });

  testWidgets('the next task starts in the project of the last one',
      (tester) async {
    final api = await _open(tester);
    await _type(tester, 'new-task-title', 'First');
    await _type(tester, 'new-task-project', 'website');
    await settle(tester);
    await tester.tap(find.byKey(const Key('project-option-k2')));
    await settle(tester);
    await _create(tester);
    expect(_body(api)['container_id'], 'k2');
    await tester.tap(find.byKey(const Key('new-task-button')));
    await settle(tester);
    expect(_projectText(tester), 'Website');
  });

  group('labels', () {
    testWidgets('a label is chosen from suggestions', (tester) async {
      final api = await _open(tester);
      await _type(tester, 'new-task-title', 'Fix the form');
      await _type(tester, 'new-task-label-field', 'ur');
      await settle(tester);
      expect(find.byKey(const Key('label-option-Urgent')), findsOneWidget);
      expect(find.byKey(const Key('label-option-Home')), findsNothing);
      // What was typed is offered last, as a new label.
      expect(find.text('Create "ur"'), findsOneWidget);
      await tester.tap(find.byKey(const Key('label-option-Urgent')));
      await settle(tester);
      expect(find.byKey(const Key('new-task-label-Urgent')), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('new-task-label-field')))
              .controller!
              .text,
          '');
      await _create(tester);
      expect(_body(api)['labels'], ['Urgent']);
    });

    testWidgets('a new label is created from the typed text', (tester) async {
      final api = await _open(tester);
      await _type(tester, 'new-task-title', 'Plan trip');
      await _type(tester, 'new-task-label-field', 'Holiday');
      await settle(tester);
      // No label matches, so the only suggestion is the new one.
      expect(find.text('Create "Holiday"'), findsOneWidget);
      // Enter in the field, as the keyboard sends it to a text field.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(find.byKey(const Key('new-task-label-Holiday')), findsOneWidget);
      await _create(tester);
      expect(_body(api)['labels'], ['Holiday']);
    });

    testWidgets('a chosen label is not suggested again, and can be removed',
        (tester) async {
      final api = await _open(tester);
      await _type(tester, 'new-task-title', 'x');
      for (final l in ['Urgent', 'Home']) {
        await _type(tester, 'new-task-label-field', l.toLowerCase());
        await settle(tester);
        await tester.tap(find.byKey(Key('label-option-$l')));
        await settle(tester);
      }
      await _type(tester, 'new-task-label-field', 'urgent');
      await settle(tester);
      expect(find.byKey(const Key('label-option-Urgent')), findsNothing);
      expect(
          find.textContaining('Create "urgent"'), findsNothing); // same label
      await _type(tester, 'new-task-label-field', '');
      await tester.tap(find.descendant(
          of: find.byKey(const Key('new-task-label-Urgent')),
          matching: find.byTooltip('Delete')));
      await settle(tester);
      expect(find.byKey(const Key('new-task-label-Urgent')), findsNothing);
      await _create(tester);
      expect(_body(api)['labels'], ['Home']);
    });

    testWidgets('text left in the label field is not lost', (tester) async {
      final api = await _open(tester);
      await _type(tester, 'new-task-title', 'x');
      await _type(tester, 'new-task-label-field', 'Errands');
      await _create(tester);
      expect(_body(api)['labels'], ['Errands']);
    });

    testWidgets('a task without labels sends none', (tester) async {
      final api = await _open(tester);
      await _type(tester, 'new-task-title', 'x');
      await _create(tester);
      expect(_body(api).containsKey('labels'), isFalse);
    });
  });

  group('the day', () {
    testWidgets('a day makes an all-day task', (tester) async {
      final api = await _open(tester);
      await _type(tester, 'new-task-title', 'Pay the invoice');
      expect(
          tester.widget<InkWell>(find.byKey(const Key('new-task-time'))).onTap,
          isNull); // a time needs a day
      await tester.tap(find.byKey(const Key('new-task-date')));
      await settle(tester);
      await tester.tap(find.text('15'));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await settle(tester);
      final shown = tester
          .widget<Text>(find.byKey(const Key('new-task-date-value')))
          .data!;
      expect(shown.endsWith('-15'), isTrue);
      await _create(tester);
      expect(api.where('PUT /tasks/t9/schedule').single.data, {'date': shown});
    });

    testWidgets('a day and a time plan a block that starts then',
        (tester) async {
      final api = await _open(tester);
      await _type(tester, 'new-task-title', 'Call Sam');
      await tester.tap(find.byKey(const Key('new-task-date')));
      await settle(tester);
      await tester.tap(find.text('15'));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('new-task-time')));
      await settle(tester);
      await tester.tap(find.text('OK')); // the picker starts at 09:00
      await settle(tester);
      expect(
          tester
              .widget<Text>(find.byKey(const Key('new-task-time-value')))
              .data,
          '09:00');
      final day = tester
          .widget<Text>(find.byKey(const Key('new-task-date-value')))
          .data!;
      await _create(tester);
      final d = DateTime.parse(day);
      expect(api.where('PUT /tasks/t9/schedule').single.data, {
        'start': DateTime(d.year, d.month, d.day, 9).toUtc().toIso8601String(),
      });
    });

    testWidgets('the day can be cleared again', (tester) async {
      final api = await _open(tester);
      await _type(tester, 'new-task-title', 'x');
      await tester.tap(find.byKey(const Key('new-task-date')));
      await settle(tester);
      await tester.tap(find.text('OK'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('new-task-date-clear')));
      await tester.pump();
      expect(
          tester
              .widget<Text>(find.byKey(const Key('new-task-date-value')))
              .data,
          'No date');
      await _create(tester);
      expect(api.where('PUT /tasks/t9/schedule'), isEmpty);
    });

    testWidgets('a day that cannot be set is reported, the task exists',
        (tester) async {
      final api = _api(extra: {
        'PUT /tasks/t9/schedule': const ApiFailure(
            409, 'Scheduling is not available for this app.', 'not_supported'),
      });
      await _open(tester, api: api);
      await _type(tester, 'new-task-title', 'Pay');
      await tester.tap(find.byKey(const Key('new-task-date')));
      await settle(tester);
      await tester.tap(find.text('OK'));
      await settle(tester);
      await _create(tester);
      expect(api.where('POST /tasks'), hasLength(1));
      expect(find.byKey(const Key('new-task-dialog')), findsNothing);
      expect(
          find.textContaining('but its day could not be set'), findsOneWidget);
      expect(
          find.textContaining('Scheduling is not available'), findsOneWidget);
    });
  });

  testWidgets('a refusal stays in the dialog with the message and the edits',
      (tester) async {
    final api = _api(extra: {
      'POST /tasks': const ApiFailure(
          502,
          'Home tasks cannot be reached. Nothing was changed.',
          'backend_unavailable'),
    });
    await _open(tester, api: api);
    await _type(tester, 'new-task-title', 'Buy bread');
    await _type(tester, 'new-task-label-field', 'Errands');
    await _create(tester);
    expect(find.byKey(const Key('new-task-dialog')), findsOneWidget);
    expect(find.text('Home tasks cannot be reached. Nothing was changed.'),
        findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('new-task-title')))
            .controller!
            .text,
        'Buy bread');
    expect(_createEnabled(tester), isTrue); // the user can try again
  });

  testWidgets('the arrow keys and Enter choose a project and a label',
      (tester) async {
    final api = await _open(tester);
    await _type(tester, 'new-task-title', 'By keyboard');
    // The project list: Inbox, Website, Website › Launch. Down, Down, Enter.
    await _type(tester, 'new-task-project', '');
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(_projectText(tester), 'Website › Launch');
    // The label list for "o": Home, Errands... Down, Enter takes the second.
    await _type(tester, 'new-task-label-field', 'e');
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await _create(tester);
    expect(_body(api)['container_id'], 'k3');
    expect((_body(api)['labels'] as List).length, 1);
  });

  testWidgets('Esc closes the project list', (tester) async {
    await _open(tester);
    await _type(tester, 'new-task-project', '');
    await settle(tester);
    expect(find.byKey(const Key('project-option-k1')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byKey(const Key('project-option-k1')), findsNothing);
  });

  testWidgets('Ctrl+Enter creates the task', (tester) async {
    final api = await _open(tester);
    await _type(tester, 'new-task-title', 'Quick one');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(api.where('POST /tasks'), hasLength(1));
  });

  testWidgets('Cancel creates nothing', (tester) async {
    final api = await _open(tester);
    await _type(tester, 'new-task-title', 'Never mind');
    await tester.tap(find.byKey(const Key('new-task-cancel')));
    await settle(tester);
    expect(api.where('POST /tasks'), isEmpty);
    expect(find.byKey(const Key('new-task-dialog')), findsNothing);
  });

  testWidgets('without a task app the dialog says what to do', (tester) async {
    final api = _api(extra: {'GET /connections': <Object?>[]});
    await _open(tester, api: api);
    expect(find.byKey(const Key('new-task-no-projects')), findsOneWidget);
    expect(_createEnabled(tester), isFalse);
  });

  testWidgets('two task apps: the project says which app it is in',
      (tester) async {
    final api = _api(extra: {
      'GET /connections': [
        connectionJson('c1', 'tasks', 'Home tasks'),
        connectionJson('c2', 'tasks', 'Work tasks'),
      ],
      'GET /connections/c2/containers': [_project('w1', '9', 'Roadmap')],
      'GET /connections/c2/labels': <Object?>[],
    });
    await _open(tester, api: api);
    await _type(tester, 'new-task-project', 'road');
    await settle(tester);
    expect(find.text('Roadmap (Work tasks)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('project-option-w1')));
    await settle(tester);
    await _type(tester, 'new-task-title', 'Plan Q4');
    await _create(tester);
    expect(_body(api)['connection_id'], 'c2');
    expect(_body(api)['container_id'], 'w1');
  });

  testWidgets('the dialog fits a phone screen', (tester) async {
    await _open(tester);
    tester.view.physicalSize = const Size(360, 700);
    await tester.pumpAndSettle();
    await _type(tester, 'new-task-label-field', 'ur');
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
