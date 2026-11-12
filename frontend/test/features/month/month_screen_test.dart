import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/month/review_screen.dart';
import 'package:tefteri/features/month/month_screen.dart';

import '../../support/fake_api.dart';
import 'month_fake.dart';

Map<String, Object?> _checklist(List<(String, bool)> items) => {
      'period_type': 'month',
      'period_start': '2030-03-01',
      'items': [
        for (final (text, checked) in items) {'text': text, 'checked': checked},
      ],
      'done': items.where((item) => item.$2).length,
      'total': items.length,
    };

Future<void> _pump(WidgetTester tester, MonthFakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  final router = GoRouter(
    initialLocation: '/month?date=2030-03-10',
    routes: [
      GoRoute(
        path: '/month',
        builder: (_, __) => MonthScreen(initialDate: DateTime(2030, 3, 10)),
      ),
      GoRoute(
        path: '/month/review',
        builder: (_, state) => MonthReviewScreen(
          month: (state.uri.queryParameters['date'] ?? '2030-03-01')
              .substring(0, 7),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await pumpWithApi(
    tester,
    api,
    const SizedBox.shrink(),
    router: router,
  );
}

void main() {
  testWidgets('shows monthly focus, targets, progress and key results',
      (tester) async {
    final api = MonthFakeApi(
      plan: monthlyJson(
        entries: [
          monthlyEntryJson('e1', 'p1', 'Open source',
              target: 3, done: 2, marker: 'missed', lastMonthDone: 1),
        ],
        keyResults: [
          monthlyKeyResultJson(
            id: 'kr1',
            goalTitle: 'Grow the project',
            metric: 'Active users',
            startValue: 4,
            currentValue: 8,
            target: 20,
            themeIds: const ['p1'],
          ),
        ],
      ),
    );
    api.routes['GET /checklists/month/2030-03-01'] = _checklist([
      ('Review commitments', false),
    ]);
    await _pump(tester, api);

    expect(find.text('Mar 2030'), findsOneWidget);
    expect(find.text('Open source'), findsOneWidget);
    expect(find.byKey(const Key('target-p1')), findsOneWidget);
    expect(find.byKey(const Key('focus-progress-p1')), findsOneWidget);
    expect(find.textContaining('Grow the project'), findsOneWidget);
    expect(find.text('Monthly checklist'), findsOneWidget);
    expect(find.byKey(const Key('open-month-review')), findsOneWidget);
    expect(find.text('Launch site'), findsNothing);
    expect(find.text('Create a month goal'), findsNothing);
  });

  testWidgets('the monthly checklist remains tickable at the top',
      (tester) async {
    final api = MonthFakeApi();
    api.routes['GET /checklists/month/2030-03-01'] =
        _checklist([('Review commitments', false)]);
    api.routes['PUT /checklists/month/2030-03-01/items'] = (options) {
      final body = options.data as Map;
      return _checklist([
        ('Review commitments', body['checked'] as bool),
      ]);
    };
    await _pump(tester, api);
    expect(find.text('Review commitments'), findsOneWidget);
    await tester.tap(find.byKey(const Key('checklist-item-0')));
    await tester.pumpAndSettle();
    expect(api.where('PUT /checklists/month/2030-03-01/items'), hasLength(1));
  });

  testWidgets(
      'suggestions remain a draft until Save and six themes are allowed',
      (tester) async {
    final api = MonthFakeApi(
      plan: monthlyJson(month: '2030-03', state: 'future', focusKnown: false),
      picker: monthlyPickerJson(themes: [
        for (var i = 0; i < 6; i++) monthlyThemeJson('p$i', 'Theme $i'),
      ]),
      suggestions: monthlySuggestionsJson(
        fromMonth: '2030-02',
        suggestions: [monthlySuggestionJson('p1', 'Carry theme', target: 2)],
      ),
    );
    await _pump(tester, api);
    expect(find.byKey(const Key('suggestions-card')), findsOneWidget);
    expect(find.text('Carry theme'), findsOneWidget);
    expect(api.where('PUT /monthly/2030-03/focus'), isEmpty);
    await tester.tap(find.byKey(const Key('add-theme')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      if (i == 1) continue;
      await tester.tap(find.byKey(Key('theme-option-p$i')));
    }
    expect(find.textContaining('Three to five is usual'), findsOneWidget);
    await tester.tap(find.byKey(const Key('theme-picker-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-focus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-save-focus')));
    await tester.pumpAndSettle();
    expect(api.where('PUT /monthly/2030-03/focus').last.data, isA<Map>());
    expect(
      ((api.where('PUT /monthly/2030-03/focus').last.data as Map)['entries']
          as List),
      hasLength(6),
    );
  });

  testWidgets('shows an orphan by its stored name without rename controls',
      (tester) async {
    final api = MonthFakeApi(
      plan: monthlyJson(entries: [
        monthlyEntryJson('e1', 'orphan', 'Old theme name',
            target: 2,
            orphaned: {
              'reason': 'missing',
              'at': '2030-03-12T10:00:00Z',
            }),
      ]),
    );
    await _pump(tester, api);
    expect(find.text('Old theme name'), findsOneWidget);
    expect(find.textContaining('No longer in the task app'), findsOneWidget);
    expect(find.byKey(const Key('rename-theme-orphan')), findsNothing);
    await tester.tap(find.byKey(const Key('open-month-review')));
    await tester.pumpAndSettle();
    expect(find.byType(MonthReviewScreen), findsOneWidget);
    expect(api.where('GET /monthly/2030-03/review'), hasLength(1));
  });

  testWidgets('next month loads its monthly plan and preserves period keys',
      (tester) async {
    final api = MonthFakeApi();
    api.routes['GET /monthly/2030-04'] =
        monthlyJson(month: '2030-04', state: 'future', focusKnown: false);
    api.routes['GET /monthly/2030-04/suggestions'] =
        monthlySuggestionsJson(fromMonth: null);
    api.routes['GET /monthly/2030-04/themes'] = monthlyPickerJson();
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('next-period')));
    await tester.pumpAndSettle();
    expect(find.text('Apr 2030'), findsOneWidget);
    expect(api.where('GET /monthly/2030-04'), hasLength(1));
    expect(find.byKey(const Key('period-label')), findsOneWidget);
    expect(find.byKey(const Key('today-button')), findsOneWidget);
    expect(find.byKey(const Key('prev-period')), findsOneWidget);
    expect(find.byKey(const Key('next-period')), findsOneWidget);
  });

  testWidgets('the month offers no goal section and no goal control (SC-005)',
      (tester) async {
    final api = MonthFakeApi(
      plan: monthlyJson(
        entries: [monthlyEntryJson('e1', 'p1', 'Open source', target: 3)],
        keyResults: [monthlyKeyResultJson(id: 'kr1')],
      ),
    );
    await _pump(tester, api);
    expect(find.text('Goals'), findsNothing);
    expect(find.byKey(const Key('no-goals')), findsNothing);
    expect(find.text('Link to goal'), findsNothing);
    expect(find.textContaining('Add goal'), findsNothing);
    expect(api.requests.where((r) => r.path.startsWith('/goals')), isEmpty);
    expect(
        api.requests.where((r) => r.path.startsWith('/views/month')), isEmpty);
  });
}
