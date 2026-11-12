import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/month/review_key_results_section.dart';

import '../../support/fake_api.dart';

void main() {
  testWidgets('shows timestamp, manual entry, skip and typed gap',
      (tester) async {
    final snapshot = monthlySnapshotJson(
      themes: [
        monthlyReviewThemeJson(
          projectId: 'p1',
          name: 'Theme',
          done: 6,
        ),
      ],
      keyResults: [
        monthlyReviewKeyResultJson(
          id: 'kr1',
          themeIds: const ['p1'],
          latestValue: 15,
          baseValue: 10,
          latestAt: '2030-03-20T09:00:00Z',
          status: 'not_updated',
          shared: true,
        ),
      ],
    );
    final values = <String, num>{};
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ReviewKeyResultsSection(
            snapshot: snapshot,
            values: values,
            onValueChanged: (id, value) {
              setState(() {
                if (value == null) {
                  values.remove(id);
                } else {
                  values[id] = value;
                }
              });
            },
          ),
        ),
      ),
    ));
    expect(find.textContaining('6 milestones shipped'), findsOneWidget);
    expect(find.textContaining('Not updated this month'), findsOneWidget);
    expect(find.textContaining('2030-03-20T09:00:00Z'), findsOneWidget);
    expect(find.byKey(const Key('shared-key-result-kr1')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('manual-value-kr1')), '22');
    await tester.pump();
    expect(values['kr1'], 22);
    expect(find.textContaining('Latest 22'), findsOneWidget);
    expect(find.textContaining('Change +'), findsOneWidget);
    expect(find.textContaining('does not say one caused the other'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('skip-value-kr1')));
    await tester.pump();
    expect(values, isEmpty);
  });

  testWidgets(
      'automatic values have no prompt and shared results repeat by theme',
      (tester) async {
    final snapshot = monthlySnapshotJson(
      themes: [
        monthlyReviewThemeJson(projectId: 'p1'),
        monthlyReviewThemeJson(projectId: 'p2', name: 'Second theme'),
      ],
      keyResults: [
        monthlyReviewKeyResultJson(
          updateSource: 'automatic',
          themeIds: const ['p1', 'p2'],
          shared: true,
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReviewKeyResultsSection(
          snapshot: snapshot,
          values: const {},
          onValueChanged: (_, __) {},
        ),
      ),
    ));
    expect(find.byKey(const Key('manual-value-kr1')), findsNothing);
    expect(find.byKey(const Key('review-key-result-kr1')), findsNWidgets(2));
    expect(find.text('Shared by more than one theme.'), findsNWidgets(2));
  });
}
