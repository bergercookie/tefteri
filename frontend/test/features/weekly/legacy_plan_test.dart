import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weekly_fake.dart';
import 'weekly_pump.dart';

Map<String, Object?> _entry(
        String id, String week, List<Map<String, Object?>> projects) =>
    {
      'plan_id': id,
      'week_start': week,
      'committed_projects': projects.length,
      'done_projects': projects.where((p) => p['done'] == true).length,
      'committed_tasks': 6,
      'done_tasks': 4,
      'reflection': '',
      'projects': projects,
    };

Map<String, Object?> _history(List<Object?> entries) => {
      'entries': entries,
      'totals': {
        'weeks': entries.length,
        'committed_projects': 3,
        'done_projects': 1,
        'committed_tasks': 12,
        'done_tasks': 8,
      },
    };

void main() {
  testWidgets(
      'an old week shows its carried and backlog choices under the '
      'new names', (tester) async {
    final s = WeeklyServer()
      ..history = _history([
        _entry('h0', '2030-02-18', [
          {
            'name': 'Website',
            'done': false,
            'decision': 'recommit',
            'milestone_id': 'm1',
            'theme_name': 'Work',
            'rollover_count': 1,
          },
        ]),
        _entry('h1', '2030-02-11', [
          // Rows from before milestones: the server maps carry and backlog.
          {
            'name': 'Garden shed (old)',
            'done': false,
            'decision': 'carry',
            'milestone_id': null
          },
          {
            'name': 'Tax forms (old)',
            'done': false,
            'decision': 'backlog',
            'milestone_id': null
          },
          {'name': 'Old done project', 'done': true, 'milestone_id': null},
        ]),
      ]);
    await pumpWeekly(tester, s);
    await openStep(tester, 'lookBack');
    expect(find.textContaining('Keep and recommit'), findsNWidgets(2));
    expect(find.textContaining('Keep but park'), findsOneWidget);
    // The second week is old: both of its choices show under the new names.
    expect(
        find.descendant(
            of: find.byKey(const Key('history-h1')),
            matching: find.textContaining('Keep and recommit')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('history-h1')),
            matching: find.textContaining('Keep but park')),
        findsOneWidget);
    expect(find.textContaining('carry'), findsNothing);
    expect(find.textContaining('backlog'), findsNothing);
  });

  testWidgets(
      'a legacy project without a milestone shows its stored name '
      'and counts', (tester) async {
    final s = WeeklyServer()
      ..history = _history([
        _entry('h1', '2030-02-11', [
          {'name': 'Garden shed (old)', 'done': false, 'milestone_id': null},
        ]),
      ]);
    await pumpWeekly(tester, s);
    await openStep(tester, 'lookBack');
    expect(find.text('Garden shed (old)'), findsOneWidget);
    expect(find.byKey(const Key('legacy-note-h1')), findsOneWidget);
    expect(find.textContaining('planned before milestones'), findsOneWidget);
    expect(find.text('4 of 6 tasks done'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find
                .descendant(
                    of: find.byKey(const Key('committed-h1')),
                    matching: find.byType(Text))
                .first)
            .data,
        '1');
  });

  testWidgets('a new week shows no legacy note', (tester) async {
    final s = WeeklyServer()
      ..history = _history([
        _entry('h0', '2030-02-18', [
          {
            'name': 'Website',
            'done': true,
            'decision': null,
            'milestone_id': 'm1',
            'theme_name': 'Work',
            'done_on': '2030-02-20',
            'rollover_count': 0,
          },
        ]),
      ]);
    await pumpWeekly(tester, s);
    await openStep(tester, 'lookBack');
    expect(find.byKey(const Key('legacy-note-h0')), findsNothing);
    expect(find.textContaining('Work · done Wed 20 Feb'), findsOneWidget);
  });

  testWidgets('nothing offers to change an old week', (tester) async {
    final s = WeeklyServer()
      ..history = _history([
        _entry('h1', '2030-02-11', [
          {
            'name': 'Tax forms (old)',
            'done': false,
            'decision': 'backlog',
            'milestone_id': null
          },
        ]),
      ]);
    await pumpWeekly(tester, s);
    await openStep(tester, 'lookBack');
    final card = find.byKey(const Key('history-h1'));
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.byType(ButtonStyleButton)),
        findsNothing);
    expect(find.descendant(of: card, matching: find.byType(IconButton)),
        findsNothing);
    expect(
        find.descendant(of: card, matching: find.byType(Switch)), findsNothing);
    expect(find.byKey(const Key('decision-park-old')), findsNothing);
  });

  testWidgets(
      'an unreviewed week from before milestones shows the stored '
      'name, the counts and no close choice', (tester) async {
    final s = WeeklyServer(
        lookBack: sampleLookBack(projects: [
      lookBackProject('op1', 'Old project',
          noMilestone: true,
          theme: null,
          close: {
            'available': false,
            'reason': 'no_theme',
            'open_tasks': 2,
            'theme_name': null
          }),
    ]));
    await pumpWeekly(tester, s);
    expect(find.text('Old project'), findsOneWidget);
    expect(find.text('1 of 3 tasks done'), findsOneWidget);
    expect(find.byKey(const Key('look-legacy-op1')), findsOneWidget);
    expect(find.byKey(const Key('decision-close-op1')), findsNothing);
    expect(find.byKey(const Key('decision-recommit-op1')), findsOneWidget);
    expect(find.byKey(const Key('decision-park-op1')), findsOneWidget);
  });
}
