import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/weekly/week_progress.dart';
import 'package:tefteri/features/weekly/week_progress_card.dart';

import '../../support/fake_api.dart';

final _monday = DateTime(2026, 11, 2);

/// The days of a week as the server counts them by category.
List<Object?> _days(List<List<int>> byDay) => [
      for (var i = 0; i < 7; i++)
        {
          'start': '2026-11-0${2 + i}',
          'end': '2026-11-0${3 + i}',
          'counts': categoryCountsJson(byDay[i][0], byDay[i][1], byDay[i][2]),
          'hidden': 0,
        },
    ];

Map<String, Object?> _weekly() => {
      'week_start': '2026-11-02',
      'week_end': '2026-11-09',
      'plan': {
        'id': 'p',
        'status': 'committed',
        'max_projects': 3,
        'projects': [
          {
            'id': 'a',
            'name': 'Website',
            'created_here': false,
            'open_tasks': 6,
            'done_tasks': 4,
            'scheduled_tasks': 0,
            'tasks': <Object?>[],
            'committed_tasks': <Object?>[],
          },
        ],
      },
      'look_back': null,
    };

Map<String, Object?> _stats(
        {Map<String, Object?>? progress, List<Object?>? parts}) =>
    statisticsJson(
      goalAligned: 4,
      maintenance: 2,
      offPlan: 3,
      progress: progress,
      parts: parts ??
          _days([
            [2, 0, 1],
            [1, 1, 0],
            [1, 1, 2],
            [0, 0, 0],
            [0, 0, 0],
            [0, 0, 0],
            [0, 0, 0],
          ]),
    );

Future<void> _pumpCard(WidgetTester tester, Map<String, Object?> routes) {
  SharedPreferences.setMockInitialValues({});
  return pumpWithApi(
    tester,
    FakeApi(routes),
    Scaffold(
      body: SingleChildScrollView(
        child: WeekProgressCard(week: _monday, today: DateTime(2026, 11, 4)),
      ),
    ),
  );
}

void main() {
  group('WeekProgress.fromJson', () {
    test('keeps the numbers of the server and calculates nothing', () {
      final p = WeekProgress.fromJson(weekProgressJson(
        committed: 10,
        done: 5,
        doneByDay: const [2, 1, 1, 0, 0, 0, 0],
        doneBefore: 1,
        daysElapsed: 3,
        daysLeft: 5,
        cadence: 1.5,
        neededPerDay: 0.9,
        onTrack: false,
        remainingByDay: const [8, 7, 6, null, null, null, null],
        scope: 9,
      ));
      expect(p.committed, 10);
      expect(p.done, 5);
      expect(p.doneBefore, 1);
      expect(p.doneByDay, [2, 1, 1, 0, 0, 0, 0]);
      expect(p.daysElapsed, 3);
      expect(p.daysLeft, 5);
      // Not the 4 / 3 of the old client calculation: the server decides.
      expect(p.cadence, 1.5);
      expect(p.neededPerDay, 0.9);
      expect(p.onTrack, isFalse);
      expect(p.remainingByDay, [8, 7, 6, null, null, null, null]);
      expect(p.idealByDay, hasLength(7));
      expect(p.scope, 9);
    });

    test('keeps null for a cadence the server could not give', () {
      final p = WeekProgress.fromJson(
          weekProgressJson(cadence: null, neededPerDay: null));
      expect(p.cadence, isNull);
      expect(p.neededPerDay, isNull);
    });
  });

  group('WeekProgressCard', () {
    testWidgets('shows done, left, cadence, days and the burndown',
        (tester) async {
      await _pumpCard(tester, {
        'GET /statistics': _stats(progress: weekProgressJson()),
        'GET /weekly/2026-11-02': _weekly(),
      });
      expect(find.text('4 of 10 tasks done'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('stat-left')), matching: find.text('6')),
          findsOneWidget);
      expect(find.text('1.3 a day'), findsOneWidget);
      expect(find.text('1.2 a day'), findsOneWidget);
      expect(find.text('On track.'), findsOneWidget);
      expect(find.text('Website'), findsNothing);
      expect(find.textContaining('Website'), findsOneWidget);
      expect(find.text('Total 4'), findsOneWidget);
      expect(find.byKey(const Key('burndown')), findsOneWidget);
    });

    testWidgets('the verdict follows the server, not a client rule',
        (tester) async {
      await _pumpCard(tester, {
        'GET /statistics': _stats(progress: weekProgressJson(onTrack: false)),
      });
      expect(find.text('Behind the plan.'), findsOneWidget);
    });

    testWidgets('shows the category counts of each day, not a "+N" extra',
        (tester) async {
      await _pumpCard(tester, {
        'GET /statistics': _stats(progress: weekProgressJson()),
        'GET /weekly/2026-11-02': _weekly(),
      });
      // Wednesday: 1 goal-aligned, 1 maintenance, 2 off-plan.
      for (final entry in {
        'goal_aligned': '1',
        'maintenance': '1',
        'off_plan': '2'
      }.entries) {
        expect(
            find.descendant(
                of: find.byKey(Key('day-${entry.key}-2')),
                matching: find.text(entry.value)),
            findsOneWidget,
            reason: entry.key);
      }
      // Every day names the three categories, also with zero.
      for (var i = 0; i < 7; i++) {
        for (final c in ['goal_aligned', 'maintenance', 'off_plan']) {
          expect(find.byKey(Key('day-$c-$i')), findsOneWidget);
        }
      }
      expect(find.byKey(const Key('stat-extra')), findsNothing);
      expect(find.byKey(const Key('extra-day-1')), findsNothing);
      expect(find.byKey(const Key('done-outside-plan')), findsNothing);
      expect(find.textContaining('outside the plan'), findsNothing);
    });

    testWidgets('a day says its three counts to a screen reader',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpCard(tester, {
        'GET /statistics': _stats(progress: weekProgressJson()),
      });
      expect(
          find.bySemanticsLabel(
              'Wed: 1 goal-aligned, 1 maintenance, 2 off-plan'),
          findsOneWidget);
      handle.dispose();
    });

    testWidgets('a week without a committed plan shows nothing',
        (tester) async {
      await _pumpCard(tester, {
        'GET /statistics': _stats(progress: null),
      });
      expect(find.byKey(const Key('week-progress')), findsNothing);
    });

    testWidgets('shows nothing when the numbers cannot be loaded',
        (tester) async {
      await _pumpCard(tester, {});
      expect(find.byKey(const Key('week-progress')), findsNothing);
    });
  });
}
