import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'planner_helpers.dart';

Future<void> _pumpNarrow(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpPlanner(tester, api);
  // pumpWithApi resets the window size; apply the narrow size again.
  tester.view.physicalSize = const Size(400, 900);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('below 840 dp the screen shows two tabs instead of two columns',
      (tester) async {
    await _pumpNarrow(tester, plannerApi());
    expect(find.byKey(const Key('planner-tabs')), findsOneWidget);
    expect(find.byKey(const Key('task-pane')), findsOneWidget);
    // only the selected tab is visible
    expect(find.byKey(const Key('calendar-pane')).hitTestable(), findsNothing);
    await tester.tap(find.byKey(const Key('tab-calendar')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('calendar-pane')).hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('task-pane')).hitTestable(), findsNothing);
  });

  testWidgets('filter, search text and week survive a tab switch',
      (tester) async {
    final api = plannerApi();
    await _pumpNarrow(tester, api);
    await tester.tap(find.byKey(const Key('filter-week')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('task-search')), 'trip');
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);

    await tester.tap(find.byKey(const Key('tab-calendar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('next-week')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('tab-tasks')));
    await tester.pumpAndSettle();

    expect(
        tester
            .widget<TextField>(find.byKey(const Key('task-search')))
            .controller!
            .text,
        'trip');
    await tester.tap(find.byKey(const Key('tab-calendar')));
    await tester.pumpAndSettle();
    expect(find.text('Week of 2026-11-09'), findsOneWidget);
  });

  testWidgets('Schedule… chooses a date and time without dragging',
      (tester) async {
    final api =
        plannerApi(extra: {'PUT /tasks/t1/schedule': dueTask('t1', 'x')});
    await _pumpNarrow(tester, api);
    // step 1: Schedule…  step 2: choose the time  step 3: confirm
    await tester.tap(find.byKey(const Key('schedule-task-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-time')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('14:30'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('14:30').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-confirm')));
    await settle(tester);

    final put = api.where('PUT /tasks/t1/schedule').single;
    final start = DateTime.parse('${(put.data! as Map)['start']}').toLocal();
    expect((start.hour, start.minute), (14, 30));
    expect(api.where('POST /calendar/entries'), isEmpty);
  });

  testWidgets('the dialog can be cancelled and then nothing is saved',
      (tester) async {
    final api = plannerApi();
    await _pumpNarrow(tester, api);
    await tester.tap(find.byKey(const Key('schedule-task-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-cancel')));
    await settle(tester);
    expect(api.where('PUT /tasks/t1/schedule'), isEmpty);
  });

  testWidgets('a failed save on a small screen shows the server message',
      (tester) async {
    final api = plannerApi(extra: {
      'PUT /tasks/t1/schedule': const ApiFailure(
          502,
          'Vikunja cannot be reached. Nothing was changed.',
          'backend_unavailable'),
    });
    await _pumpNarrow(tester, api);
    await tester.tap(find.byKey(const Key('schedule-task-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-confirm')));
    await settle(tester);
    expect(find.text('Vikunja cannot be reached. Nothing was changed.'),
        findsOneWidget);
  });

  testWidgets('the wide layout has no tabs and no Schedule… buttons',
      (tester) async {
    await pumpPlanner(tester, plannerApi());
    expect(find.byKey(const Key('planner-tabs')), findsNothing);
    expect(find.byKey(const Key('schedule-task-t1')), findsNothing);
  });
}
