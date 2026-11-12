import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/month/review_results_section.dart';

import '../../support/fake_api.dart';

void main() {
  testWidgets(
      'shows target markers, outside no-theme work and earlier milestones',
      (tester) async {
    final snapshot = monthlySnapshotJson(
      themes: [
        monthlyReviewThemeJson(
          projectId: 'missed',
          name: 'Missed theme',
          target: 3,
          done: 2,
          marker: 'missed',
          earlierNotCounted: [
            {
              'milestone_id': 'old',
              'name': 'Finished before swap',
              'done_on': '2030-03-03',
            },
          ],
        ),
        monthlyReviewThemeJson(
            projectId: 'met',
            name: 'Met theme',
            target: 0,
            done: 0,
            marker: 'met'),
        monthlyReviewThemeJson(
            projectId: 'beaten',
            name: 'Beaten theme',
            target: 2,
            done: 3,
            marker: 'beaten'),
        monthlyReviewThemeJson(
            projectId: 'none',
            name: 'No target theme',
            target: null,
            done: 5,
            marker: 'no_target'),
        monthlyReviewThemeJson(
            projectId: 'swapped',
            name: 'Swapped theme',
            status: 'swapped_out',
            target: 4,
            done: 1,
            marker: 'missed'),
      ],
      outsideFocus: [
        {
          'milestone_id': 'outside',
          'name': 'Unthemed work',
          'done_on': '2030-03-15',
          'theme_project_id': null,
          'theme_name': null,
        },
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReviewResultsSection(snapshot: snapshot),
        ),
      ),
    ));
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.text('Met'), findsOneWidget);
    expect(find.text('Beaten'), findsOneWidget);
    expect(find.text('No target'), findsOneWidget);
    expect(find.textContaining('Swapped out during the month'), findsOneWidget);
    expect(find.textContaining('Finished before swap'), findsOneWidget);
    expect(find.textContaining('Theme: no theme'), findsOneWidget);
  });
}
