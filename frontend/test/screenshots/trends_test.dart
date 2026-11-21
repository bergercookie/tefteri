@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/trends/trends_screen.dart';

import 'screenshot_helper.dart';

/// A screenshot of the Trends page, from fake data. It writes
/// `docs/images/weekly-trends.png`.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('trends: the weeks side by side', (tester) async {
    final weeks = [
      weekMetricsJson('2026-09-14',
          committed: 8,
          committedDone: 4,
          goalAligned: 4,
          maintenance: 2,
          offPlan: 4,
          milestonesCommitted: 2,
          milestonesDone: 1,
          themes: 2),
      weekMetricsJson('2026-09-21',
          committed: 9,
          committedDone: 5,
          goalAligned: 5,
          maintenance: 1,
          offPlan: 3,
          milestonesCommitted: 2,
          milestonesDone: 1,
          themes: 2),
      weekMetricsJson('2026-09-28',
          committed: 10,
          committedDone: 6,
          goalAligned: 6,
          maintenance: 2,
          offPlan: 3,
          milestonesCommitted: 2,
          milestonesDone: 1,
          themes: 2),
      weekMetricsJson('2026-10-05',
          committed: 8,
          committedDone: 5,
          goalAligned: 5,
          maintenance: 2,
          offPlan: 2,
          milestonesCommitted: 2,
          milestonesDone: 2,
          themes: 3),
      weekMetricsJson('2026-10-12',
          committed: 10,
          committedDone: 7,
          goalAligned: 8,
          maintenance: 1,
          offPlan: 2,
          milestonesCommitted: 3,
          milestonesDone: 2,
          themes: 3),
      weekMetricsJson('2026-10-19',
          committed: 9,
          committedDone: 7,
          goalAligned: 9,
          maintenance: 2,
          offPlan: 1,
          milestonesCommitted: 3,
          milestonesDone: 2,
          milestonesFinished: 3,
          themes: 3),
      weekMetricsJson('2026-10-26',
          committed: 10,
          committedDone: 9,
          goalAligned: 11,
          maintenance: 1,
          offPlan: 1,
          milestonesCommitted: 3,
          milestonesDone: 3,
          themes: 3),
      weekMetricsJson('2026-11-02',
          finished: false,
          committed: 9,
          committedDone: 3,
          goalAligned: 4,
          maintenance: 1,
          offPlan: 1,
          milestonesCommitted: 3,
          themes: 2),
    ];
    await pumpScreen(tester, FakeApi({'GET /weekly/trends': trendsJson(weeks)}),
        const TrendsScreen(),
        size: const Size(1100, 1500));
    await saveScreenshot('weekly-trends');
  });
}
