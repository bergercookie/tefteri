import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/open_url.dart';

import '../../support/fake_api.dart';
import 'planner_helpers.dart';

Map<String, Object?> _task({String status = 'open'}) => {
      ...dueTask('t1', 'Write report', due: DateTime(2026, 11, 4, 15)),
      'description': null,
      'status': status,
      'project': 'Work stuff',
      'labels': ['errand', 'home'],
      'url': 'https://vikunja.test/tasks/55',
    };

void main() {
  Future<FakeApi> open(WidgetTester tester,
      {List<Uri>? opened, Object? extraRoute}) async {
    var status = 'open';
    final api = plannerApi(
      tasksFor: (_) => [_task()],
      extra: {
        'GET /tasks/t1': (_) => _task(status: status),
        'POST /tasks/t1/complete': (_) {
          status = 'done';
          return _task(status: status);
        },
        'POST /tasks/t1/reopen': (_) {
          status = 'open';
          return _task(status: status);
        },
        'DELETE /tasks/t1': const NoContent(),
      },
    );
    await pumpPlanner(tester, api, overrides: [
      openUrlProvider.overrideWithValue((u) async {
        opened?.add(u);
        return true;
      }),
    ]);
    await tester.tap(find.byKey(const Key('task-t1')));
    await settle(tester);
    return api;
  }

  testWidgets('the details show the project and the labels', (tester) async {
    await open(tester);
    expect(
        tester.widget<Text>(find.byKey(const Key('task-details-project'))).data,
        'Work stuff');
    expect(
        find.descendant(
            of: find.byKey(const Key('task-details-labels')),
            matching: find.byType(Chip)),
        findsNWidgets(2));
    expect(find.text('errand'), findsOneWidget);
  });

  testWidgets('mark done, then not done', (tester) async {
    final api = await open(tester);
    await tester.tap(find.byKey(const Key('task-toggle-done')));
    await settle(tester);
    expect(api.where('POST /tasks/t1/complete'), hasLength(1));
    expect(
        tester.widget<Text>(find.byKey(const Key('task-details-status'))).data,
        'Done');

    await tester.tap(find.byKey(const Key('task-toggle-done')));
    await settle(tester);
    expect(api.where('POST /tasks/t1/reopen'), hasLength(1));
    expect(
        tester.widget<Text>(find.byKey(const Key('task-details-status'))).data,
        'Open');
  });

  testWidgets('open in Vikunja opens the task page', (tester) async {
    final opened = <Uri>[];
    await open(tester, opened: opened);
    await tester.tap(find.byKey(const Key('task-open-app')));
    await tester.pump();
    expect(opened.single.toString(), 'https://vikunja.test/tasks/55');
  });

  testWidgets('delete asks first, then deletes and closes', (tester) async {
    final api = await open(tester);
    await tester.tap(find.byKey(const Key('task-delete')));
    await settle(tester);
    expect(find.byKey(const Key('task-delete-confirm')), findsOneWidget);
    expect(api.where('DELETE /tasks/t1'), isEmpty);

    await tester.tap(find.byKey(const Key('task-delete-confirm-yes')));
    await settle(tester);
    expect(api.where('DELETE /tasks/t1'), hasLength(1));
    expect(find.byKey(const Key('task-details')), findsNothing);
  });
}
