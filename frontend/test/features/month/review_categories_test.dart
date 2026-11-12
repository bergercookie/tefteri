import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/month/review_categories_section.dart';

import '../../support/fake_api.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the server category counts, hidden count and rising trend',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: ReviewCategoriesSection(
            snapshot: monthlySnapshotJson(categories: const {
              'goal_aligned': 12,
              'maintenance': 8,
              'off_plan': 5,
              'hidden': 2,
            }),
            trend: const {'state': 'rising', 'share': 0.2, 'previous': []},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('12'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byKey(const Key('off-plan-trend')), findsOneWidget);
    expect(find.byKey(const Key('review-category-bar')), findsOneWidget);
    expect(find.text('Goal-aligned'), findsOneWidget);
    expect(find.text('Maintenance'), findsOneWidget);
    expect(find.text('Off-plan'), findsOneWidget);
  });

  testWidgets('not enough history is noted and no-work month has no bar',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: ReviewCategoriesSection(
            snapshot: monthlySnapshotJson(categories: const {
              'goal_aligned': 0,
              'maintenance': 0,
              'off_plan': 0,
              'hidden': 0,
            }),
            trend: const {
              'state': 'not_enough_history',
              'share': null,
              'previous': [],
            },
            categoriesNote: 'no_data',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('not-enough-history')), findsOneWidget);
    expect(find.textContaining('No completed work'), findsOneWidget);
    expect(find.byKey(const Key('review-category-bar')), findsNothing);
  });
}
