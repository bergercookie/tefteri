import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'weekly_fake.dart';
import 'weekly_pump.dart';

/// The review of last week with Garden unfinished. [close] answers the close
/// calls; the dry run is answered here.
Future<(FakeApi, WeeklyServer)> _pump(
  WidgetTester tester, {
  Object? Function(RequestOptions o)? close,
  Object? reopen,
}) async {
  final s = WeeklyServer(lookBack: sampleLookBack());
  void mark(String state) {
    final projects = (s.lookBack!['projects']! as List).cast<Map>();
    projects.firstWhere((p) => p['id'] == 'op2')['milestone_state'] = state;
  }

  final api = await pumpWeekly(tester, s, extra: {
    'POST /milestones/m-op2/close': (RequestOptions o) {
      if ((o.data as Map)['dry_run'] == true) {
        return {
          'open_tasks': 2,
          'theme': {'id': 'th-work', 'name': 'Work'},
          'message': '2 open tasks will move to Work.',
        };
      }
      final r = close?.call(o) ??
          {
            'milestone': {'id': 'm-op2', 'state': 'closed'},
            'moved': 2,
            'closure_id': 'cl1',
          };
      if (r is Map && r.containsKey('moved')) mark('closed');
      return r;
    },
    'POST /milestones/m-op2/reopen': (RequestOptions o) {
      mark('active');
      return reopen ??
          {
            'milestone': {'id': 'm-op2', 'state': 'active'},
            'moved_back': 2,
            'not_moved_back': <Object?>[],
          };
    },
  });
  return (api, s);
}

List<Recorded> _confirms(FakeApi api) => [
      for (final r in api.where('POST /milestones/m-op2/close'))
        if ((r.data as Map)['confirm'] == true) r,
    ];

void main() {
  testWidgets(
      'the dialog shows how many tasks move before the confirm and '
      'says it can be undone', (tester) async {
    final (api, _) = await _pump(tester);
    await tapKey(tester, 'decision-close-op2');
    expect(find.byKey(const Key('close-dialog')), findsOneWidget);
    expect(find.text('2 open tasks will move to Work.'), findsOneWidget);
    expect(find.byKey(const Key('close-undo-note')), findsOneWidget);
    expect(find.textContaining('undo this later'), findsOneWidget);
    // Nothing has moved: only the dry run went out.
    expect(_confirms(api), isEmpty);
    expect(api.where('POST /milestones/m-op2/close').single.data,
        {'dry_run': true, 'confirm': false});
    await tapKey(tester, 'close-cancel');
    expect(find.byKey(const Key('close-dialog')), findsNothing);
    expect(_confirms(api), isEmpty);
    // A cancelled close does not pick the choice.
    expect(find.byKey(const Key('close-done-op2')), findsNothing);
  });

  testWidgets('confirming calls the API and shows the result', (tester) async {
    final (api, _) = await _pump(tester);
    await tapKey(tester, 'decision-close-op2');
    await tapKey(tester, 'close-confirm');
    expect(_confirms(api).single.data, {'dry_run': false, 'confirm': true});
    expect(find.byKey(const Key('close-result')), findsOneWidget);
    expect(find.text('Closed. 2 tasks moved to Work.'), findsOneWidget);
    await tapKey(tester, 'close-done');
    // The card says it, and offers the undo.
    expect(find.byKey(const Key('close-done-op2')), findsOneWidget);
    expect(find.byKey(const Key('reopen-op2')), findsOneWidget);
    expect(find.byKey(const Key('decision-park-op2')), findsNothing);
    // Saving sends the close.
    await tapKey(tester, 'save-look-back');
    // (the fake review route is not set up: the save is refused, the body
    // is what counts)
    final body = api.where('POST /weekly/reviews/old1').single.data! as Map;
    expect(((body['projects'] as List)[1] as Map)['decision'], 'close');
  });

  testWidgets('a failure part way lists the moved tasks and offers a retry',
      (tester) async {
    var calls = 0;
    final (api, _) = await _pump(tester, close: (o) {
      calls++;
      if (calls == 1) {
        return const ApiFailure(
            502,
            'Your task app stopped answering while tasks were moving.',
            'backend_unavailable',
            extra: {
              'moved': [
                {'task_id': 'g1', 'title': 'Prune roses'}
              ],
              'remaining': 1,
            });
      }
      return {
        'milestone': {'id': 'm-op2', 'state': 'closed'},
        'moved': 2,
        'closure_id': 'cl1',
      };
    });
    await tapKey(tester, 'decision-close-op2');
    await tapKey(tester, 'close-confirm');
    expect(find.byKey(const Key('close-failure')), findsOneWidget);
    expect(find.textContaining('stopped answering'), findsOneWidget);
    expect(find.text('Already moved:'), findsOneWidget);
    expect(find.byKey(const Key('moved-g1')), findsOneWidget);
    expect(find.text('Prune roses'), findsWidgets);
    expect(find.textContaining('1 task still to move'), findsOneWidget);
    expect(find.textContaining('safe to try again'), findsOneWidget);
    // The milestone is not closed yet.
    await tapKey(tester, 'close-retry');
    expect(_confirms(api), hasLength(2));
    expect(find.byKey(const Key('close-result')), findsOneWidget);
    await tapKey(tester, 'close-done');
    expect(find.byKey(const Key('close-done-op2')), findsOneWidget);
  });

  testWidgets('a failure can be left and the milestone stays open',
      (tester) async {
    await _pump(tester,
        close: (o) => const ApiFailure(
            502, 'Your task app is down.', 'backend_unavailable',
            extra: {'moved': <Object?>[], 'remaining': 2}));
    await tapKey(tester, 'decision-close-op2');
    await tapKey(tester, 'close-confirm');
    expect(find.byKey(const Key('close-failure')), findsOneWidget);
    await tapKey(tester, 'close-cancel');
    expect(find.byKey(const Key('close-dialog')), findsNothing);
    expect(find.byKey(const Key('close-done-op2')), findsNothing);
    expect(find.byKey(const Key('decision-close-op2')), findsOneWidget);
  });

  testWidgets('a refused dry run says nothing was moved', (tester) async {
    final s = WeeklyServer(lookBack: sampleLookBack());
    await pumpWeekly(tester, s, extra: {
      'POST /milestones/m-op2/close': const ApiFailure(
          409, 'Your task app cannot move tasks.', 'not_supported'),
    });
    await tapKey(tester, 'decision-close-op2');
    expect(find.byKey(const Key('close-error')), findsOneWidget);
    expect(find.text('Your task app cannot move tasks.'), findsOneWidget);
    expect(find.text('Nothing was moved or closed.'), findsOneWidget);
    expect(find.byKey(const Key('close-confirm')), findsNothing);
  });

  testWidgets(
      'Reopen calls the API and lists tasks that could not move '
      'back', (tester) async {
    final (api, _) = await _pump(tester, reopen: {
      'milestone': {'id': 'm-op2', 'state': 'active'},
      'moved_back': 1,
      'not_moved_back': [
        {'task_id': 'g2', 'title': 'Buy soil', 'reason': 'changed'},
      ],
    });
    await tapKey(tester, 'decision-close-op2');
    await tapKey(tester, 'close-confirm');
    await tapKey(tester, 'close-done');
    await tapKey(tester, 'reopen-op2');
    expect(api.where('POST /milestones/m-op2/reopen'), hasLength(1));
    expect(find.byKey(const Key('reopen-result-op2')), findsOneWidget);
    expect(find.text('Reopened. 1 task moved back.'), findsOneWidget);
    expect(find.byKey(const Key('not-moved-g2')), findsOneWidget);
    expect(
        find.text('Buy soil: You changed it after the move.'), findsOneWidget);
    // The choices are back, with none picked.
    expect(find.byKey(const Key('decision-close-op2')), findsOneWidget);
    expect(find.byKey(const Key('close-done-op2')), findsNothing);
  });

  testWidgets(
      'a closed milestone that comes back from the server shows the '
      'undo too', (tester) async {
    final s = WeeklyServer(
        lookBack: sampleLookBack(projects: [
      lookBackProject('op2', 'Garden', state: 'closed'),
    ]));
    final api = await pumpWeekly(tester, s, extra: {
      'POST /milestones/m-op2/reopen': (RequestOptions o) {
        ((s.lookBack!['projects']! as List).first as Map)['milestone_state'] =
            'active';
        return {
          'milestone': {'id': 'm-op2', 'state': 'active'},
          'moved_back': 0,
          'not_moved_back': <Object?>[],
        };
      },
    });
    expect(find.byKey(const Key('close-done-op2')), findsOneWidget);
    expect(find.byKey(const Key('reopen-op2')), findsOneWidget);
    await tapKey(tester, 'reopen-op2');
    expect(api.where('POST /milestones/m-op2/reopen'), hasLength(1));
    expect(find.text('Reopened. It is active again.'), findsOneWidget);
  });

  testWidgets('a failed reopen says the milestone is still closed',
      (tester) async {
    final s = WeeklyServer(
        lookBack: sampleLookBack(projects: [
      lookBackProject('op2', 'Garden', state: 'closed'),
    ]));
    await pumpWeekly(tester, s, extra: {
      'POST /milestones/m-op2/reopen':
          const ApiFailure(422, 'It is active already.', 'invalid'),
    });
    await tapKey(tester, 'reopen-op2');
    expect(find.byKey(const Key('reopen-error-op2')), findsOneWidget);
    expect(find.textContaining('still closed'), findsOneWidget);
  });

  testWidgets('a mark-done dialog says that nothing is moved or deleted',
      (tester) async {
    final s = WeeklyServer(lookBack: sampleLookBack());
    await pumpWeekly(tester, s);
    await tapKey(tester, 'mark-done-op2');
    expect(find.byKey(const Key('mark-done-dialog')), findsOneWidget);
    // The dry run is not set up here: the fixed sentence says the same.
    expect(find.byKey(const Key('mark-done-effect')), findsOneWidget);
    expect(find.textContaining('Nothing is moved or deleted'), findsWidgets);
    expect(find.textContaining('Its open tasks stay in the project'),
        findsOneWidget);
  });
}
