import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/weekly/weekly_models.dart';

import 'weekly_fake.dart';
import 'weekly_pump.dart';

Map<String, Object?> _saved(WeeklyServer s) => reviewAnswer();

Future<dynamic> _pump(
  WidgetTester tester, {
  List<Map<String, Object?>>? projects,
  Map<String, Object?> extra = const {},
}) async {
  final s = WeeklyServer(lookBack: sampleLookBack(projects: projects));
  final api = await pumpWeekly(tester, s, extra: {
    'POST /weekly/reviews/old1': (o) {
      s.lookBack = sampleLookBack(reviewed: true, projects: projects);
      return _saved(s);
    },
    'POST /milestones/m-op2/done': {
      'open_tasks': 2,
      'message': '2 open tasks stay in the project. Nothing is moved or '
          'deleted.',
    },
    ...extra,
  });
  return api;
}

void main() {
  testWidgets(
      'each unfinished milestone offers four chips and explains only the '
      'selected one', (tester) async {
    await _pump(tester);
    for (final d in Decision.values) {
      expect(find.byKey(Key('decision-${d.api}-op2')), findsOneWidget,
          reason: d.api);
      expect(find.text(d.label), findsOneWidget, reason: d.label);
      expect(find.text(d.sentence), findsNothing, reason: d.sentence);
    }
    expect(find.text('Choose what happens to this milestone.'), findsOneWidget);
    await tapKey(tester, 'decision-park-op2');
    expect(find.text(Decision.park.sentence), findsOneWidget);
    expect(find.text(Decision.recommit.sentence), findsNothing);
    expect(find.text('Choose what happens to this milestone.'), findsNothing);
    expect(find.text('Prune roses'), findsOneWidget);
    expect(find.text('Done when: The beds are planted'), findsOneWidget);
  });

  testWidgets('a finished milestone shows as done and has no choice',
      (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('look-finished-op1')), findsOneWidget);
    expect(find.byKey(const Key('decision-recommit-op1')), findsNothing);
    expect(find.byKey(const Key('decision-decide_later-op1')), findsNothing);
    expect(find.byKey(const Key('mark-done-op1')), findsNothing);
    expect(find.text('4 of 4 tasks done'), findsOneWidget);
  });

  testWidgets('saving sends the decisions', (tester) async {
    final api = await _pump(tester);
    await tapKey(tester, 'decision-park-op2');
    await tester.enterText(
        find.byKey(const Key('reflection')), 'Too much gardening.');
    await tapKey(tester, 'save-look-back');
    final body = api.where('POST /weekly/reviews/old1').single.data! as Map;
    expect(body['reflection'], 'Too much gardening.');
    expect(body['projects'], [
      {
        'plan_project_id': 'op1',
        'decision': 'decide_later',
        'expected': false,
        'mark_done': false,
        'archive': false,
      },
      {
        'plan_project_id': 'op2',
        'decision': 'park',
        'expected': false,
        'mark_done': false,
        'archive': false,
      },
    ]);
    // After the save the earlier weeks show.
    expect(find.text('Look back is done'), findsOneWidget);
  });

  testWidgets(
      'milestones without a choice are named and can all be left '
      'for later in one action; nothing blocks the save', (tester) async {
    final api = await _pump(tester, projects: [
      lookBackProject('op2', 'Garden'),
      lookBackProject('op3', 'Taxes'),
      lookBackProject('op4', 'Roof'),
    ]);
    expect(find.byKey(const Key('undecided')), findsOneWidget);
    expect(find.textContaining('"Garden", "Taxes", "Roof"'), findsOneWidget);
    await tapKey(tester, 'decision-recommit-op3');
    expect(find.textContaining('"Garden", "Roof"'), findsOneWidget);
    await tapKey(tester, 'decide-later-all');
    expect(find.byKey(const Key('undecided')), findsNothing);
    // The one that had a choice keeps it.
    await tapKey(tester, 'save-look-back');
    final answers = (api.where('POST /weekly/reviews/old1').single.data!
        as Map)['projects'] as List;
    expect([for (final a in answers) (a as Map)['decision']],
        ['decide_later', 'recommit', 'decide_later']);
  });

  testWidgets('the review can be saved with no choice at all', (tester) async {
    final api = await _pump(tester);
    expect(find.byKey(const Key('undecided')), findsOneWidget);
    await tapKey(tester, 'save-look-back');
    expect(api.where('POST /weekly/reviews/old1'), hasLength(1));
    final answers = (api.where('POST /weekly/reviews/old1').single.data!
        as Map)['projects'] as List;
    expect((answers[1] as Map)['decision'], 'decide_later');
  });

  testWidgets(
      'a milestone with no theme says why it cannot be closed and '
      'offers to label a theme', (tester) async {
    await _pump(tester, projects: [
      lookBackProject('op3', 'Loose milestone', theme: null),
    ]);
    expect(find.byKey(const Key('decision-close-op3')), findsNothing);
    expect(find.byKey(const Key('decision-recommit-op3')), findsOneWidget);
    expect(
        find.textContaining('no theme to return the tasks to'), findsOneWidget);
    expect(find.text('No theme'), findsOneWidget);
    await tapKey(tester, 'label-theme-op3');
    expect(find.text('projects page'), findsOneWidget);
  });

  testWidgets(
      'a task app that cannot move tasks hides the close choice '
      'with a line', (tester) async {
    await _pump(tester, projects: [
      lookBackProject('op2', 'Garden', close: {
        'available': false,
        'reason': 'not_supported',
        'open_tasks': 2,
        'theme_name': 'Work',
      }),
    ]);
    expect(find.byKey(const Key('decision-close-op2')), findsNothing);
    expect(find.byKey(const Key('decision-park-op2')), findsOneWidget);
    expect(find.textContaining('cannot move tasks'), findsOneWidget);
    // The line has no theme button: the theme is not the problem.
    expect(find.byKey(const Key('label-theme-op2')), findsNothing);
  });

  testWidgets('an unusable theme hides the close choice with a line',
      (tester) async {
    await _pump(tester, projects: [
      lookBackProject('op2', 'Garden', close: {
        'available': false,
        'reason': 'theme_unusable',
        'open_tasks': 2,
        'theme_name': 'Work',
      }),
    ]);
    expect(find.byKey(const Key('decision-close-op2')), findsNothing);
    expect(find.textContaining('ignored or gone from your task app'),
        findsOneWidget);
  });

  testWidgets('marking done shows its effect first and is sent when saved',
      (tester) async {
    final api = await _pump(tester);
    expect(find.text('Nothing is moved or deleted.'), findsOneWidget);
    await tapKey(tester, 'mark-done-op2');
    expect(find.byKey(const Key('mark-done-dialog')), findsOneWidget);
    expect(find.textContaining('Nothing is moved or deleted'), findsWidgets);
    expect(find.textContaining('2 open tasks stay in the project'),
        findsOneWidget);
    // Nothing is written by the dialog.
    expect(api.where('POST /milestones/m-op2/done').single.data,
        {'dry_run': true});
    await tapKey(tester, 'mark-done-confirm');
    expect(find.byKey(const Key('marked-done-op2')), findsOneWidget);
    expect(find.byKey(const Key('decision-park-op2')), findsNothing);
    expect(find.byKey(const Key('undecided')), findsNothing);
    await tapKey(tester, 'save-look-back');
    final answers = (api.where('POST /weekly/reviews/old1').single.data!
        as Map)['projects'] as List;
    expect((answers[1] as Map)['mark_done'], isTrue);
    expect(api.where('POST /milestones/m-op2/done'), hasLength(1));
  });

  testWidgets('marking done can be cancelled and taken back', (tester) async {
    await _pump(tester);
    await tapKey(tester, 'mark-done-op2');
    await tapKey(tester, 'mark-done-cancel');
    expect(find.byKey(const Key('marked-done-op2')), findsNothing);
    await tapKey(tester, 'mark-done-op2');
    await tapKey(tester, 'mark-done-confirm');
    await tapKey(tester, 'unmark-done-op2');
    expect(find.byKey(const Key('marked-done-op2')), findsNothing);
    expect(find.byKey(const Key('decision-park-op2')), findsOneWidget);
  });

  testWidgets('the archive switch is offered for every milestone',
      (tester) async {
    final api = await _pump(tester);
    expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('archive-op1')))
            .value,
        isFalse);
    await tapKey(tester, 'archive-op1');
    await tapKey(tester, 'save-look-back');
    final answers = (api.where('POST /weekly/reviews/old1').single.data!
        as Map)['projects'] as List;
    expect((answers[0] as Map)['archive'], isTrue);
    expect((answers[1] as Map)['archive'], isFalse);
  });

  testWidgets('the review fits a phone', (tester) async {
    await _pump(tester);
    tester.view.physicalSize = const Size(360, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'decision-recommit-op2');
    expect(find.byKey(const Key('expected-op2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
