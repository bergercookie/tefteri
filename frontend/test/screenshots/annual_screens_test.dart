@Tags(['screenshots'])
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/annual/annual_screen.dart';

import 'screenshot_helper.dart';

/// The example day of the annual plan: 10 March 2027.
final _today = DateTime(2027, 3, 10);

/// A plan of 2027 with each of the three flags. The data is invented.
List<Map<String, Object?>> _goals([int year = 2027]) => [
      annualGoalJson('g1', 'Get better at open source', keyResults: [
        keyResultJson('kr1', 'Stars on the main repository',
            goalId: 'g1',
            start: 120,
            target: 500,
            current: 220,
            currentAt: '$year-03-01T09:00:00Z',
            deadline: '$year-12-31',
            source: 'automatic',
            links: [linkJson('p1', 'Open source')]),
        keyResultJson('kr2', 'Talks given',
            goalId: 'g1',
            start: 0,
            target: 2,
            deadline: '$year-02-28',
            links: [linkJson('p2', 'Talks')],
            flags: [flagJson('overdue')]),
        keyResultJson('kr3', 'Pull requests reviewed',
            goalId: 'g1',
            start: 0,
            target: 50,
            current: 12,
            deadline: '$year-12-31',
            links: [
              linkJson('p3', 'Community',
                  usable: false, state: 'ignored', label: 'theme'),
            ],
            flags: [
              flagJson('no_usable_theme', reasons: [
                {
                  'project_id': 'p3',
                  'name': 'Community',
                  'state': 'ignored',
                  'label': 'theme'
                },
              ]),
            ]),
      ]),
      annualGoalJson('g2', 'Run a half marathon', keyResults: [
        keyResultJson('kr4', 'Longest run in km',
            goalId: 'g2',
            start: 5,
            target: 21,
            current: 12,
            deadline: '$year-10-31',
            links: [linkJson('p4', 'Health')]),
      ]),
      annualGoalJson('g3', 'Read more books',
          criteria: 'Twelve books, two of them in Greek'),
    ];

Object? _retire(RequestOptions o) => {
      'effect': {
        'key_results_retired': 1,
        'links_ended': 1,
        'flags_removed': ['overdue'],
        'history_kept': true,
      },
    };

FakeApi _api({int year = 2027, String state = 'current'}) => FakeApi({
      'GET /annual/$year': annualPlanJson(
          year: year,
          state: state,
          goals: _goals(year),
          retiredGoals: [
            annualGoalJson('g9', 'Learn Rust', status: 'retired'),
          ]),
      'GET /annual/2028': annualPlanJson(year: 2028, state: 'future'),
      'GET /annual/2028/suggestions':
          suggestionsJson(year: 2028, fromYear: 2027, goals: [
        suggestedGoalJson('g1', 'Get better at open source', keyResults: [
          suggestedKeyResultJson('kr1', 'Stars on the main repository',
              start: 430,
              target: 500,
              deadline: '2028-12-31',
              themes: [
                {'project_id': 'p1', 'name': 'Open source'}
              ]),
        ]),
        suggestedGoalJson('g2', 'Run a half marathon'),
      ]),
      'GET /annual/themes': themesJson(unsorted: 3),
      'POST /annual/key-results/kr2/retire': _retire,
      'GET /annual/$year/history': historyJson(year: year, [
        changeJson('c1', 'migrated',
            goalId: 'g3',
            source: 'migration',
            oldValue: 'active',
            at: '2027-01-02T08:00:00Z'),
        changeJson('c2', 'key_result_edited',
            batch: 'b2',
            keyResultId: 'kr1',
            field: 'target',
            oldValue: '400',
            newValue: '500',
            at: '2027-01-20T18:00:00Z'),
        changeJson('c3', 'link_ended',
            batch: 'b3', keyResultId: 'kr4', at: '2027-02-11T19:30:00Z'),
        changeJson('c4', 'link_added',
            batch: 'b3', keyResultId: 'kr4', at: '2027-02-11T19:30:00Z'),
        changeJson('c5', 'goal_retired',
            batch: 'b5',
            goalId: 'g9',
            reason: 'No time this year',
            at: '2027-03-02T07:45:00Z'),
      ]),
      'GET /annual/push-token': {'exists': false},
      'POST /annual/push-token': {
        'token': 'tfv_FAKE_TOKEN_FOR_DOCS_0000000000',
        'hint': '0000',
      },
    });

Future<void> _pump(WidgetTester tester, FakeApi api,
    {int year = 2027, Size size = const Size(1100, 1400)}) async {
  // The hints are closed, except where a screenshot shows one on purpose.
  SharedPreferences.setMockInitialValues({
    for (final t in [
      'planningYear',
      'keyResult',
      'automatic',
      'themeProject',
      'retire',
      'unmet'
    ])
      'term_hint_closed_annual-$t': true,
  });
  await pumpScreen(tester, api, AnnualScreen(initialYear: year, today: _today),
      size: size);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
  // A change reloads lists after the first settle.
  await tester.pump(const Duration(milliseconds: 10));
  await tester.pumpAndSettle();
}

Future<void> _menu(WidgetTester tester, String key, String item) async {
  await _tap(tester, key);
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('plan with flags', (tester) async {
    await _pump(tester, _api());
    await saveScreenshot('annual-plan');
  });

  testWidgets('key result form', (tester) async {
    await _pump(tester, _api(), size: screenshotSize);
    await _tap(tester, 'add-kr-g2');
    await tester.enterText(
        find.byKey(const Key('kr-metric')), 'Runs of 10 km or more');
    await tester.enterText(find.byKey(const Key('kr-start')), '0');
    await tester.enterText(find.byKey(const Key('kr-target')), '12');
    await tester.pumpAndSettle();
    await saveScreenshot('annual-key-result-form');
  });

  testWidgets('theme picker with no theme', (tester) async {
    await _pump(tester, _api(), size: screenshotSize);
    // The only link of this key result is to an ignored project, so the
    // picker has nothing to offer and shows its two inline actions.
    await _tap(tester, 'flag-action-link_theme-kr3');
    await saveScreenshot('annual-theme-picker');
  });

  testWidgets('retire effect', (tester) async {
    await _pump(tester, _api(), size: screenshotSize);
    await _menu(tester, 'kr-menu-kr2', 'Retire');
    await tester.enterText(
        find.byKey(const Key('retire-reason')), 'No conference this year');
    await tester.pumpAndSettle();
    await saveScreenshot('annual-retire');
  });

  testWidgets('history', (tester) async {
    await _pump(tester, _api(), size: screenshotSize);
    await _tap(tester, 'open-history');
    await saveScreenshot('annual-history');
  });

  testWidgets('value dialog', (tester) async {
    await _pump(tester, _api(), size: screenshotSize);
    await _tap(tester, 'kr-value-btn-kr4');
    await tester.enterText(find.byKey(const Key('value-field')), '14');
    await tester.pumpAndSettle();
    await saveScreenshot('annual-value');
  });

  testWidgets('push token, shown once', (tester) async {
    await _pump(tester, _api(), size: screenshotSize);
    await _tap(tester, 'open-push-token');
    await _tap(tester, 'push-token-create');
    await saveScreenshot('annual-push-token');
  });

  testWidgets('seed panel of the next year', (tester) async {
    await _pump(tester, _api(), year: 2028, size: screenshotSize);
    await _tap(tester, 'seed-accept-kr-kr1');
    await saveScreenshot('annual-seed');
  });

  testWidgets('past year', (tester) async {
    await _pump(tester, _api(year: 2026, state: 'past'), year: 2026);
    await saveScreenshot('annual-past-year');
  });

  testWidgets('phone width', (tester) async {
    await _pump(tester, _api(), size: const Size(390, 1400));
    await saveScreenshot('annual-phone');
  });
}
