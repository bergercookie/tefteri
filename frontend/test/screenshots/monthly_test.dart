@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/month/focus_change_dialog.dart';
import 'package:tefteri/features/month/month_screen.dart';
import 'package:tefteri/features/month/review_screen.dart';
import 'package:tefteri/theme/theme.dart';

import '../features/month/month_fake.dart';
import 'screenshot_helper.dart';

/// The example month of the monthly plan: March 2030.
const _month = '2030-03';

Map<String, Object?> _plan({String month = _month}) => monthlyJson(
      month: month,
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
    );

Map<String, Object?> _picker({List<Object?>? themes}) => monthlyPickerJson(
      themes: themes ??
          [
            monthlyThemeJson('p1', 'Open source',
                inFocus: true, lastMonthDone: 2, keyResultIds: const ['kr1']),
            monthlyThemeJson('p2', 'Product quality',
                inFocus: true, lastMonthDone: 1, keyResultIds: const ['kr2']),
            monthlyThemeJson('p3', 'Community',
                inFocus: true, lastMonthDone: 0),
            monthlyThemeJson('p4', 'Writing', lastMonthDone: 3),
            monthlyThemeJson('p5', 'Learning', lastMonthDone: 1),
            monthlyThemeJson('p6', 'Health', lastMonthDone: 4),
          ],
      unsortedCount: 2,
    );

Map<String, Object?> _review() => monthlyReviewJson(
      month: _month,
      stored: true,
      version: 2,
      currentVersion: 2,
      takenAt: '2030-04-02T08:00:00Z',
      versions: const [
        {'version': 2, 'taken_at': '2030-04-02T08:00:00Z', 'current': true},
        {'version': 1, 'taken_at': '2030-04-01T18:00:00Z', 'current': false},
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
    );

MonthFakeApi _api({
  String month = _month,
  Map<String, Object?>? plan,
  Map<String, Object?>? picker,
  Map<String, Object?>? review,
  List<Map<String, Object?>> legacyGoals = const [],
}) =>
    MonthFakeApi(
      month: month,
      plan: plan ?? _plan(),
      picker: picker ?? _picker(),
      review: review ?? _review(),
      legacyGoals: legacyGoals,
    );

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  MonthFakeApi? api,
  Size size = const Size(1100, 1500),
  ThemeData? theme,
}) async {
  SharedPreferences.setMockInitialValues({
    'term_hint_closed_monthly-planning-terms': true,
    'term_hint_closed_monthly-review-terms': true,
  });
  await pumpScreen(tester, api ?? _api(), screen, size: size, theme: theme);
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
    await saveScreenshot('planning-month');
  });

  testWidgets('theme picker', (tester) async {
    await _pump(tester, MonthScreen(initialDate: DateTime(2030, 3, 10)),
        size: screenshotSize);
    await _tap(tester, 'add-theme');
    await saveScreenshot('monthly-picker');
  });

  testWidgets('theme picker with no eligible theme', (tester) async {
    await _pump(
      tester,
      MonthScreen(initialDate: DateTime(2030, 3, 10)),
      api: _api(picker: _picker(themes: const [])),
      size: screenshotSize,
    );
    await _tap(tester, 'add-theme');
    await saveScreenshot('monthly-picker-empty');
  });

  testWidgets('swap effect', (tester) async {
    await _pump(
      tester,
      const Scaffold(
        body: Center(
          child: FocusChangeDialog(
            kind: 'swap',
            effect: {
              'message':
                  'Community leaves the focus today and Writing enters it.',
              'finished_earlier_in_month': 1,
              'finished_earlier': [
                {
                  'milestone_id': 'm1',
                  'name': 'Ship login',
                  'done_on': '2030-03-12'
                },
              ],
              'weekly_commitments_unchanged': 2,
              'out_keeps_results': true,
            },
          ),
        ),
      ),
      size: screenshotSize,
    );
    await saveScreenshot('monthly-swap');
  });

  testWidgets('monthly review', (tester) async {
    await _pump(tester, const MonthReviewScreen(month: _month),
        size: const Size(1100, 1700));
    await saveScreenshot('monthly-review');
  });

  testWidgets('review versions', (tester) async {
    await _pump(tester, const MonthReviewScreen(month: _month),
        size: const Size(1100, 1200));
    await _tap(tester, 'review-versions');
    await saveScreenshot('monthly-versions');
  });

  testWidgets('earlier format', (tester) async {
    await _pump(
      tester,
      MonthScreen(initialDate: DateTime(2029, 9, 10)),
      api: _api(
        month: '2029-09',
        plan: monthlyJson(
          month: '2029-09',
          state: 'past',
          focusKnown: false,
          earlierFormat: true,
        ),
        legacyGoals: [
          {
            'id': 'g1',
            'title': 'Old monthly goal',
            'description': 'Read one book.',
            'criteria': 'A short log.',
            'status': 'active',
          },
        ],
      ),
    );
    await saveScreenshot('monthly-earlier');
  });

  testWidgets('phone width', (tester) async {
    await _pump(tester, MonthScreen(initialDate: DateTime(2030, 3, 10)),
        size: const Size(390, 1700));
    await saveScreenshot('monthly-phone');
  });

  testWidgets('dark mode', (tester) async {
    await _pump(
      tester,
      MonthScreen(initialDate: DateTime(2030, 3, 10)),
      size: const Size(1100, 1500),
      theme: tefteriDark,
    );
    await saveScreenshot('monthly-dark');
  });
}
