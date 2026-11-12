import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/month/month_screen.dart';
import 'package:tefteri/features/month/review_screen.dart';

import '../../support/fake_api.dart';
import 'month_fake.dart';

void main() {
  testWidgets(
      'orphan keeps its stored name, no rename control and review opens',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = MonthFakeApi(
      plan: monthlyJson(entries: [
        monthlyEntryJson('e1', 'orphan', 'Stored theme name', orphaned: {
          'reason': 'archived',
          'at': '2030-03-11T10:00:00Z',
        }),
      ]),
    );
    final router = GoRouter(
      initialLocation: '/month?date=2030-03-09',
      routes: [
        GoRoute(
          path: '/month',
          builder: (_, __) => MonthScreen(initialDate: DateTime(2030, 3, 9)),
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
    await pumpWithApi(tester, api, const SizedBox.shrink(), router: router);
    expect(find.text('Stored theme name'), findsOneWidget);
    expect(find.textContaining('Archived'), findsOneWidget);
    expect(find.byKey(const Key('rename-theme-orphan')), findsNothing);
    await tester.tap(find.byKey(const Key('open-month-review')));
    await tester.pumpAndSettle();
    expect(find.byType(MonthReviewScreen), findsOneWidget);
    expect(api.where('GET /monthly/2030-03/review'), hasLength(1));
  });
}
