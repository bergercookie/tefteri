@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/month/month_screen.dart';
import 'package:tefteri/features/month/review_screen.dart';

import '../features/month/month_fake.dart';
import 'screenshot_helper.dart';

/// The example month of the monthly plan: March 2030.
const _month = '2030-03';

MonthFakeApi _api() => MonthFakeApi(
      month: _month,
      plan: monthlyJson(
        month: _month,
        entries: [
          monthlyEntryJson('e1', 'p1', 'Open source',
              target: 3, done: 2, lastMonthDone: 2),
          monthlyEntryJson('e2', 'p2', 'Product quality',
              target: 2, done: 2, marker: 'met', lastMonthDone: 1),
          monthlyEntryJson('e3', 'p3', 'Community', target: 1, done: 0),
        ],
        keyResults: [
          monthlyKeyResultJson(
            id: 'kr1',
            goalTitle: 'Get better at open source',
            metric: 'Stars on the main repository',
            startValue: 120,
            currentValue: 220,
            target: 500,
            themeIds: const ['p1'],
          ),
          monthlyKeyResultJson(
            id: 'kr2',
            goalTitle: 'Ship a useful product',
            metric: 'Active users',
            startValue: 40,
            currentValue: 75,
            target: 200,
            updateSource: 'automatic',
            themeIds: const ['p2'],
          ),
        ],
        review: const {'stored': false, 'current_version': null, 'versions': 0},
      ),
      picker: monthlyPickerJson(
        themes: [
          monthlyThemeJson('p1', 'Open source',
              inFocus: true, lastMonthDone: 2, keyResultIds: const ['kr1']),
          monthlyThemeJson('p2', 'Product quality',
              inFocus: true, lastMonthDone: 1, keyResultIds: const ['kr2']),
          monthlyThemeJson('p3', 'Community', inFocus: true, lastMonthDone: 0),
          monthlyThemeJson('p4', 'Writing', lastMonthDone: 3),
          monthlyThemeJson('p5', 'Learning', lastMonthDone: 1),
          monthlyThemeJson('p6', 'Health', lastMonthDone: 4),
        ],
        unsortedCount: 2,
      ),
      review: monthlyReviewJson(
        month: _month,
        stored: true,
        version: 1,
        currentVersion: 1,
        takenAt: '2030-04-02T08:00:00Z',
        versions: const [
          {'version': 1, 'taken_at': '2030-04-02T08:00:00Z', 'current': true},
        ],
        trendState: 'rising',
        share: 0.24,
        previous: const [
          {'month': '2030-02', 'share': 0.18},
          {'month': '2030-01', 'share': 0.12},
        ],
        snapshot: monthlySnapshotJson(
          month: '$_month-01',
          themes: [
            monthlyReviewThemeJson(
              projectId: 'p1',
              name: 'Open source',
              target: 3,
              done: 2,
              marker: 'missed',
              milestones: const [
                {
                  'milestone_id': 'm1',
                  'name': 'Ship login',
                  'done_on': '2030-03-12'
                },
                {
                  'milestone_id': 'm2',
                  'name': 'Write the guide',
                  'done_on': '2030-03-25'
                },
              ],
              keyResultIds: const ['kr1'],
            ),
            monthlyReviewThemeJson(
              projectId: 'p2',
              name: 'Product quality',
              target: 2,
              done: 2,
              marker: 'met',
              milestones: const [
                {
                  'milestone_id': 'm3',
                  'name': 'Fix the settings page',
                  'done_on': '2030-03-08'
                },
                {
                  'milestone_id': 'm4',
                  'name': 'Add the export',
                  'done_on': '2030-03-19'
                },
              ],
              keyResultIds: const ['kr2'],
            ),
            monthlyReviewThemeJson(
              projectId: 'p3',
              name: 'Community',
              target: null,
              done: 0,
              marker: 'no_target',
              keyResultIds: const [],
            ),
          ],
          outsideFocus: const [
            {
              'milestone_id': 'm5',
              'name': 'Rewrite the readme',
              'done_on': '2030-03-16',
              'theme_id': 'p4',
              'theme_name': 'Writing',
            },
            {
              'milestone_id': 'm6',
              'name': 'Answer the survey',
              'done_on': '2030-03-21',
              'theme_id': null,
              'theme_name': null,
            },
          ],
          keyResults: [
            monthlyReviewKeyResultJson(
              id: 'kr1',
              goalTitle: 'Get better at open source',
              metric: 'Stars on the main repository',
              startValue: 120,
              baseValue: 180,
              latestValue: 220,
              change: 40,
              target: 500,
              themeIds: const ['p1'],
            ),
            monthlyReviewKeyResultJson(
              id: 'kr2',
              goalTitle: 'Ship a useful product',
              metric: 'Active users',
              updateSource: 'automatic',
              startValue: 40,
              baseValue: 60,
              latestValue: 75,
              change: 15,
              target: 200,
              themeIds: const ['p2'],
            ),
          ],
          decisions: const [
            {
              'project_id': 'p1',
              'decision': 'carry',
              'target': 3,
              'suggested_theme': null,
            },
            {
              'project_id': 'p2',
              'decision': 'drop',
              'target': null,
              'suggested_theme': null,
            },
            {
              'project_id': 'p3',
              'decision': 'replace',
              'target': null,
              'suggested_theme': {'project_id': 'p5', 'name': 'Learning'},
            },
          ],
        ),
      ),
    );

Future<void> _pump(WidgetTester tester, Widget screen,
    {Size size = const Size(1100, 1500)}) async {
  SharedPreferences.setMockInitialValues({
    'term_hint_closed_monthly-planning-terms': true,
    'term_hint_closed_monthly-review-terms': true,
  });
  await pumpScreen(tester, _api(), screen, size: size);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('monthly plan', (tester) async {
    await _pump(tester, MonthScreen(initialDate: DateTime(2030, 3, 10)));
    await saveScreenshot('monthly-planning');
  });

  testWidgets('theme picker', (tester) async {
    await _pump(tester, MonthScreen(initialDate: DateTime(2030, 3, 10)),
        size: screenshotSize);
    await _tap(tester, 'add-theme');
    await saveScreenshot('monthly-picker');
  });

  testWidgets('monthly review', (tester) async {
    await _pump(tester, const MonthReviewScreen(month: _month),
        size: const Size(1100, 1700));
    await saveScreenshot('monthly-review');
  });

  testWidgets('phone width', (tester) async {
    await _pump(tester, MonthScreen(initialDate: DateTime(2030, 3, 10)),
        size: const Size(390, 1700));
    await saveScreenshot('monthly-phone');
  });
}
