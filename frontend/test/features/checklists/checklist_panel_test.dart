import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/core/planning_models.dart';
import 'package:tefteri/features/checklists/checklist_panel.dart';

import '../../support/fake_api.dart';

// 2026-11-04 is a Wednesday; its week starts on Monday 2026-11-02.
final _wednesday = DateTime(2026, 11, 4);
const _get = 'GET /checklists/week/2026-11-02';
const _put = 'PUT /checklists/week/2026-11-02/items';

Map<String, Object?> _list(List<(String, bool)> items) => {
      'period_type': 'week',
      'period_start': '2026-11-02',
      'items': [
        for (final (t, c) in items) {'text': t, 'checked': c},
      ],
      'done': items.where((i) => i.$2).length,
      'total': items.length,
    };

/// A server whose ticks are kept in [state].
FakeApi _server(Map<String, bool> state, {Object? onPut}) => FakeApi({
      _get: (_) => _list([for (final e in state.entries) (e.key, e.value)]),
      _put: onPut ??
          (RequestOptions o) {
            final body = o.data as Map;
            state[body['text'] as String] = body['checked'] as bool;
            return _list([for (final e in state.entries) (e.key, e.value)]);
          },
    });

Future<void> _pump(WidgetTester tester, FakeApi api,
    {bool collapsible = false, bool card = false}) async {
  tester.view.physicalSize = const Size(600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = api;
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => Scaffold(
        body: SingleChildScrollView(
          child: PlanningChecklist(
              kind: ChecklistKind.week,
              day: _wednesday,
              collapsible: collapsible,
              card: card),
        ),
      ),
    ),
    GoRoute(
        path: '/settings/checklists',
        builder: (_, __) => const Scaffold(body: Text('the settings page'))),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

String _summary(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('checklist-summary'))).data!;

bool _box(WidgetTester tester, int i) =>
    tester.widget<Checkbox>(find.byKey(Key('checklist-box-$i'))).value!;

void main() {
  testWidgets('shows the items and how many are done', (tester) async {
    await _pump(tester,
        _server({'Look back': true, 'Clear the inbox': false, 'Plan': false}));
    expect(find.text('Weekly checklist'), findsOneWidget);
    expect(_summary(tester), '1 of 3 done');
    expect(find.text('Clear the inbox'), findsOneWidget);
    expect([for (var i = 0; i < 3; i++) _box(tester, i)], [true, false, false]);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byKey(const Key('checklist-bar')))
            .value,
        closeTo(1 / 3, 1e-9));
    expect(find.byKey(const Key('checklist-hint')), findsNothing);
  });

  testWidgets('any day of the week asks for the Monday', (tester) async {
    final api = _server({'a': false});
    await _pump(tester, api);
    expect(api.where(_get), hasLength(1));
  });

  testWidgets('a tap on a row ticks the item and a second tap unticks it',
      (tester) async {
    final state = {'Look back': false, 'Clear the inbox': false};
    final api = _server(state);
    await _pump(tester, api);

    await tester.tap(find.byKey(const Key('checklist-item-1')));
    await tester.pumpAndSettle();
    expect(api.where(_put).single.data,
        {'text': 'Clear the inbox', 'checked': true});
    expect(state['Clear the inbox'], isTrue);
    expect(_box(tester, 1), isTrue);
    expect(_summary(tester), '1 of 2 done');

    await tester.tap(find.byKey(const Key('checklist-box-1')));
    await tester.pumpAndSettle();
    expect(api.where(_put).last.data,
        {'text': 'Clear the inbox', 'checked': false});
    expect(_box(tester, 1), isFalse);
  });

  testWidgets('a ticked item is struck through', (tester) async {
    await _pump(tester, _server({'Done thing': true, 'Open thing': false}));
    TextDecoration? decoration(String t) =>
        tester.widget<Text>(find.text(t)).style?.decoration;
    expect(decoration('Done thing'), TextDecoration.lineThrough);
    expect(decoration('Open thing'), isNot(TextDecoration.lineThrough));
  });

  testWidgets('when every item is ticked it says so', (tester) async {
    await _pump(tester, _server({'a': true, 'b': false}));
    expect(find.byKey(const Key('checklist-all-done')), findsNothing);
    await tester.tap(find.byKey(const Key('checklist-item-1')));
    await tester.pumpAndSettle();
    expect(_summary(tester), 'All 2 done');
    expect(find.byKey(const Key('checklist-all-done')), findsOneWidget);
  });

  testWidgets('a refused tick goes back and shows the message', (tester) async {
    final state = {'a': false};
    await _pump(
        tester,
        _server(state,
            onPut: const ApiFailure(
                422, 'That item is not in the checklist.', 'invalid')));
    await tester.tap(find.byKey(const Key('checklist-item-0')));
    await tester.pumpAndSettle();
    expect(find.text('That item is not in the checklist.'), findsOneWidget);
    expect(_box(tester, 0), isFalse);
    expect(_summary(tester), '0 of 1 done');
  });

  testWidgets('two quick ticks are written in the order they were made',
      (tester) async {
    final state = {'a': false, 'b': false};
    final api = _server(state);
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('checklist-item-0')));
    await tester.tap(find.byKey(const Key('checklist-item-1')));
    await tester.pumpAndSettle();
    expect(
        [for (final r in api.where(_put)) (r.data as Map)['text']], ['a', 'b']);
    expect(_summary(tester), 'All 2 done');
  });

  testWidgets('without a list it says so and offers to make one',
      (tester) async {
    final api = FakeApi({_get: _list([])});
    await _pump(tester, api);
    expect(_summary(tester), 'Not set up yet');
    expect(find.byKey(const Key('checklist-hint')), findsOneWidget);
    expect(find.textContaining('You have no weekly checklist yet'),
        findsOneWidget);
    expect(find.byKey(const Key('checklist-item-0')), findsNothing);

    await tester.tap(find.byKey(const Key('checklist-create')));
    await tester.pumpAndSettle();
    expect(find.text('the settings page'), findsOneWidget);
  });

  testWidgets('the list can be edited from the checklist', (tester) async {
    await _pump(tester, _server({'a': false}));
    await tester.tap(find.byKey(const Key('checklist-edit')));
    await tester.pumpAndSettle();
    expect(find.text('the settings page'), findsOneWidget);
  });

  testWidgets('a load error is shown with a way to try again', (tester) async {
    var fail = true;
    final api = FakeApi({
      _get: (_) => fail
          ? throw DioException(
              requestOptions: RequestOptions(path: ''),
              response: Response(
                  requestOptions: RequestOptions(path: ''),
                  statusCode: 500,
                  data: {'detail': 'Server trouble.'}),
              type: DioExceptionType.badResponse)
          : _list([('a', false)]),
    });
    await _pump(tester, api);
    expect(find.byKey(const Key('checklist-error')), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const Key('checklist-retry')));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
  });

  testWidgets('collapsed, it shows the count and opens on a tap',
      (tester) async {
    await _pump(tester, _server({'Look back': true, 'Plan': false}),
        collapsible: true);
    expect(_summary(tester), '1 of 2 done');
    expect(find.text('Plan'), findsNothing);
    await tester.tap(find.byKey(const Key('checklist-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Plan'), findsOneWidget);
    await tester.tap(find.byKey(const Key('checklist-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Plan'), findsNothing);
  });

  testWidgets('collapsed without a list, the header already says so',
      (tester) async {
    await _pump(tester, FakeApi({_get: _list([])}), collapsible: true);
    expect(_summary(tester), 'Not set up yet');
    await tester.tap(find.byKey(const Key('checklist-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checklist-create')), findsOneWidget);
  });
}
