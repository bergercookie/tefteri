import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/month/review_screen.dart';

import '../../support/fake_api.dart';
import 'month_fake.dart';

void main() {
  testWidgets('a live review is labelled draft and saves an immutable version',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = MonthFakeApi();
    await pumpWithApi(
      tester,
      api,
      const MonthReviewScreen(month: '2030-03'),
    );
    expect(find.byKey(const Key('draft-label')), findsOneWidget);
    expect(find.text('Open source'), findsWidgets);
    await tester.tap(find.byKey(const Key('save-month-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-with-later')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-save-review')));
    await tester.pumpAndSettle();
    expect(api.where('POST /monthly/2030-03/review'), hasLength(2));
    expect(api.review['stored'], isTrue);
    expect(api.review['current_version'], 1);
    expect(find.textContaining('Review snapshot v1'), findsOneWidget);
    expect(find.byKey(const Key('draft-label')), findsNothing);
  });

  testWidgets('reopening warns about a new version and lists stored versions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = MonthFakeApi(
      review: monthlyReviewJson(
        stored: true,
        version: 1,
        currentVersion: 1,
        takenAt: '2030-04-02T08:00:00Z',
        versions: [
          {
            'version': 1,
            'taken_at': '2030-04-02T08:00:00Z',
            'current': true,
          },
        ],
        snapshot: monthlySnapshotJson(
          themes: [
            monthlyReviewThemeJson(name: 'Stored name', done: 2),
          ],
        ),
      ),
    );
    await pumpWithApi(
      tester,
      api,
      const MonthReviewScreen(month: '2030-03'),
    );
    expect(find.text('Stored name'), findsWidgets);
    await tester.tap(find.byKey(const Key('save-month-review')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-version-notice')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-new-version')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-with-later')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-version-effect-note')), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-versions')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Version 1'), findsOneWidget);
    expect(find.textContaining('Current'), findsOneWidget);
  });

  testWidgets('an earlier version can be previewed and made current',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = MonthFakeApi(
      review: monthlyReviewJson(
        stored: true,
        version: 2,
        currentVersion: 2,
        versions: [
          {
            'version': 1,
            'taken_at': '2030-04-02T08:00:00Z',
            'current': false,
          },
          {
            'version': 2,
            'taken_at': '2030-05-02T08:00:00Z',
            'current': true,
          },
        ],
      ),
    );
    await pumpWithApi(
      tester,
      api,
      const MonthReviewScreen(month: '2030-03'),
    );
    await tester.tap(find.byKey(const Key('review-versions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('make-current-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Version 1 becomes the current version'),
        findsOneWidget);
    await tester.tap(find.text('Make current').last);
    await tester.pumpAndSettle();
    expect(api.where('POST /monthly/2030-03/review/current'), hasLength(2));
    expect(api.review['current_version'], 1);
  });
}
