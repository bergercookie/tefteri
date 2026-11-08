import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/goals/goals_screen.dart';
import 'package:tefteri/features/goals/periods.dart';
import 'package:tefteri/core/planning_models.dart';

import '../../support/fake_api.dart';

Object? _goals(RequestOptions o) {
  if (o.queryParameters['parent_id'] == 'g1') {
    return [
      goalJson('g2', 'Beta in March',
          periodType: 'month',
          periodStart: '2026-03-01',
          parentId: 'g1',
          progress: 0.4),
    ];
  }
  if (o.queryParameters['parent_id'] != null) return <Object?>[];
  return [goalJson('g1', 'Ship product', progress: 0.2)];
}

FakeApi _api([Map<String, Object?> extra = const {}]) => FakeApi({
      'GET /goals': _goals,
      'GET /connections': [
        connectionJson('c1', 'tasks', 'Home tasks'),
        connectionJson('c2', 'calendar', 'Work calendar'),
      ],
      ...extra,
    });

Future<void> _pump(WidgetTester tester, FakeApi api) =>
    pumpWithApi(tester, api, GoalsScreen(initialDate: DateTime(2026, 11, 4)));

Future<void> _menu(WidgetTester tester, String id, String item) async {
  await tester.tap(find.byKey(Key('goal-menu-$id')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

Future<void> _openGoal(WidgetTester tester, String title) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  test('child periods follow the hierarchy', () {
    final year = PlanGoal.fromJson(goalJson('g', 'y'));
    expect(childPeriods(year), hasLength(12));
    expect(childPeriods(year).first.start, '2026-01-01');
    final month = PlanGoal.fromJson(
        goalJson('g', 'm', periodType: 'month', periodStart: '2026-11-01'));
    // Mondays in November 2026: 2, 9, 16, 23, 30.
    expect(childPeriods(month).map((c) => c.start),
        ['2026-11-02', '2026-11-09', '2026-11-16', '2026-11-23', '2026-11-30']);
    final week = PlanGoal.fromJson(
        goalJson('g', 'w', periodType: 'week', periodStart: '2026-11-02'));
    expect(childPeriods(week), isEmpty);
  });

  testWidgets('shows year goals with children and progress', (tester) async {
    final api = _api();
    await _pump(tester, api);
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('Ship product'), findsOneWidget);
    expect(find.text('Beta in March'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byKey(const Key('goal-progress-g1')))
            .value,
        0.2);
    expect(find.text('40%'), findsOneWidget);
    final q = api.where('GET /goals').first.query;
    expect(q['period_type'], 'year');
    expect(q['period_start'], '2026-01-01');
    await tester.pumpAndSettle(); // let the nested goal requests finish
  });

  testWidgets('month type asks for the month period', (tester) async {
    final api = _api();
    await _pump(tester, api);
    await tester.tap(find.text('Month').last);
    await tester.pumpAndSettle();
    final q = api
        .where('GET /goals')
        .map((r) => r.query)
        .lastWhere((q) => q['period_type'] == 'month');
    expect(q['period_start'], '2026-11-01');
  });

  testWidgets('add sends the goal for the shown period', (tester) async {
    final api = _api({'POST /goals': goalJson('g9', 'New')});
    await _pump(tester, api);
    await tester.enterText(find.byKey(const Key('goal-title-field')), 'Learn');
    await tester.tap(find.byKey(const Key('goal-add-button')));
    await tester.pumpAndSettle();
    final body = api.where('POST /goals').single.data! as Map;
    expect(body['title'], 'Learn');
    expect(body['period_type'], 'year');
    expect(body['period_start'], '2026-01-01');
  });

  testWidgets('mark done patches the status', (tester) async {
    final api = _api({'PATCH /goals/g1': goalJson('g1', 'x')});
    await _pump(tester, api);
    // The card has no complete button: the goal is completed in its pop-up.
    expect(find.text('Mark done'), findsNothing);
    await _openGoal(tester, 'Ship product');
    await tester.tap(find.byKey(const Key('goal-dialog-complete')));
    await tester.pumpAndSettle();
    expect(
        (api.where('PATCH /goals/g1').single.data! as Map)['status'], 'done');
    expect(find.byKey(const Key('goal-dialog')), findsNothing);
  });

  testWidgets('delete asks and can keep the linked tasks', (tester) async {
    final api = _api({'DELETE /goals/g1': const NoContent()});
    await _pump(tester, api);
    await _openGoal(tester, 'Ship product');
    await tester.tap(find.byKey(const Key('goal-dialog-delete')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Child goals are deleted too'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-keep-tasks')));
    await tester.pumpAndSettle();
    final r = api.where('DELETE /goals/g1').single;
    expect(r.query['linked_tasks'], 'keep');
  });

  testWidgets('delete can remove the linked tasks', (tester) async {
    final api = _api({'DELETE /goals/g1': const NoContent()});
    await _pump(tester, api);
    await _openGoal(tester, 'Ship product');
    await tester.tap(find.byKey(const Key('goal-dialog-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-remove-tasks')));
    await tester.pumpAndSettle();
    expect(
        api.where('DELETE /goals/g1').single.query['linked_tasks'], 'delete');
  });

  testWidgets('cancel in the delete dialog sends nothing', (tester) async {
    final api = _api();
    await _pump(tester, api);
    await _openGoal(tester, 'Ship product');
    await tester.tap(find.byKey(const Key('goal-dialog-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-cancel')));
    await tester.pumpAndSettle();
    expect(api.where('DELETE /goals/g1'), isEmpty);
  });

  testWidgets('breakdown creates child goals and tasks', (tester) async {
    final api = _api({
      'POST /goals/g1/breakdown': {'goals': [], 'tasks': []},
    });
    await _pump(tester, api);
    await _menu(tester, 'g1', 'Break down');
    await tester.tap(find.byKey(const Key('breakdown-add-goal')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('breakdown-goal-title-0')), 'Prototype');
    await tester.tap(find.byKey(const Key('breakdown-add-task')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('breakdown-task-title-0')), 'Buy parts');
    await tester.tap(find.byKey(const Key('breakdown-confirm')));
    await tester.pumpAndSettle();
    final body = api.where('POST /goals/g1/breakdown').single.data! as Map;
    final goal = (body['goals'] as List).single as Map;
    expect(goal['title'], 'Prototype');
    expect(goal['period_type'], 'month');
    expect(goal['period_start'], '2026-01-01');
    final task = (body['tasks'] as List).single as Map;
    expect(task['title'], 'Buy parts');
    expect(task['connection_id'], 'c1');
  });

  testWidgets('a week goal cannot be broken down', (tester) async {
    final api = _api({
      'GET /goals': (RequestOptions o) => o.queryParameters['parent_id'] != null
          ? <Object?>[]
          : [
              goalJson('w1', 'Fix bug',
                  periodType: 'week', periodStart: '2026-11-02'),
            ],
    });
    await _pump(tester, api);
    await tester.tap(find.text('Week').last);
    await tester.pumpAndSettle();
    // A week goal has no menu at all.
    expect(find.byKey(const Key('goal-menu-w1')), findsNothing);
    await tester.tap(find.text('Fix bug'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal-dialog')), findsOneWidget);
    expect(find.byKey(const Key('goal-dialog-bulk-field')), findsNothing);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('a server error shows the message', (tester) async {
    final api = _api({
      'POST /goals': const ApiFailure(
          422, 'A month goal must lie inside its year.', 'invalid'),
    });
    await _pump(tester, api);
    await tester.enterText(find.byKey(const Key('goal-title-field')), 'Bad');
    await tester.tap(find.byKey(const Key('goal-add-button')));
    await tester.pumpAndSettle();
    expect(find.text('A month goal must lie inside its year.'), findsOneWidget);
  });

  testWidgets('goals are numbered and the totals count goals and subgoals',
      (tester) async {
    await _pump(tester, _api());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal-number-g1')), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const Key('goal-number-g1'))).data, '1');
    expect(tester.widget<Text>(find.byKey(const Key('goal-number-g2'))).data,
        '1.1');
    expect(tester.widget<Text>(find.byKey(const Key('goal-totals'))).data,
        '1 goal, 1 subgoal');
  });

  testWidgets('several goals are added at once, one for each line',
      (tester) async {
    final api = _api({
      'POST /goals/bulk': [goalJson('a', 'Run 25 km')],
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('goal-bulk-open')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('goal-bulk-field')),
        'Run 25 km\n\n- Read 12 books\n  \n2. Learn to sail\n');
    await tester.pumpAndSettle();
    expect(find.text('Add 3 goals'), findsOneWidget);
    await tester.tap(find.byKey(const Key('goal-bulk-create')));
    await tester.pumpAndSettle();
    final body = api.where('POST /goals/bulk').single.data! as Map;
    expect(body['titles'], ['Run 25 km', 'Read 12 books', 'Learn to sail']);
    expect(body['period_type'], 'year');
    expect(body['period_start'], '2026-01-01');
  });

  testWidgets('a goal opens when its text is pressed and keeps the criteria',
      (tester) async {
    final api = _api({
      'GET /goals': (RequestOptions o) => o.queryParameters['parent_id'] != null
          ? <Object?>[]
          : [
              goalJson('g1', 'Ship product',
                  description: 'The first public release.',
                  criteria: 'Ten users pay.')
            ],
      'PATCH /goals/g1': goalJson('g1', 'x'),
    });
    await _pump(tester, api);
    await tester.pumpAndSettle();
    // The card shows both texts.
    expect(find.byKey(const Key('goal-description-g1')), findsOneWidget);
    expect(find.byKey(const Key('goal-criteria-g1')), findsOneWidget);
    await tester.tap(find.text('Ship product'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal-dialog')), findsOneWidget);
    expect(find.text('Annual goal'), findsOneWidget);
    // Save is off until something changes.
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('goal-dialog-save')))
            .onPressed,
        isNull);
    await tester.enterText(
        find.byKey(const Key('goal-dialog-criteria')), 'Fifty users pay.');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal-dialog-save')));
    await tester.pumpAndSettle();
    final body = api.where('PATCH /goals/g1').single.data! as Map;
    expect(body, {
      'title': 'Ship product',
      'description': 'The first public release.',
      'criteria': 'Fifty users pay.',
    });
    expect(find.byKey(const Key('goal-dialog')), findsNothing);
  });

  testWidgets('child goals of an annual goal are added in bulk for a month',
      (tester) async {
    final api = _api({
      'POST /goals/bulk': [goalJson('c', 'x')],
    });
    await _pump(tester, api);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ship product'));
    await tester.pumpAndSettle();
    // The existing monthly goal is listed.
    expect(find.byKey(const Key('goal-children')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('goal-children')),
            matching: find.text('Beta in March')),
        findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('goal-dialog-bulk-field')), 'Plan\nBuild');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('goal-dialog-bulk-add')));
    await tester.tap(find.byKey(const Key('goal-dialog-bulk-add')));
    await tester.pumpAndSettle();
    final body = api.where('POST /goals/bulk').single.data! as Map;
    expect(body['titles'], ['Plan', 'Build']);
    expect(body['parent_id'], 'g1');
    expect(body['period_type'], 'month');
  });

  testWidgets('the goal pop-up fits a phone screen', (tester) async {
    await _pump(tester, _api());
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await _openGoal(tester, 'Ship product');
    expect(find.byKey(const Key('goal-dialog')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final box = tester.getRect(find.byKey(const Key('goal-dialog')));
    expect(box.width, lessThanOrEqualTo(390));
  });
}
