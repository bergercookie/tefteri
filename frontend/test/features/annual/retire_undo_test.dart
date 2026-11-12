import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'annual_fake.dart';

AnnualServer _server() => AnnualServer(goals: [
      annualGoalJson('g1', 'Get better at open source', keyResults: [
        keyResultJson('kr1', 'Stars',
            links: [linkJson('p1', 'Open source'), linkJson('p2', 'Talks')]),
        keyResultJson('kr2', 'Talks given', links: [linkJson('p2', 'Talks')]),
      ]),
    ]);

RouteBuilder _retire(int krs, int links) => (RequestOptions o) {
      final body = o.data as Map;
      final effect = {
        'key_results_retired': krs,
        'links_ended': links,
        'flags_removed': ['no_usable_theme'],
        'history_kept': true,
      };
      return body['dry_run'] == true
          ? {'effect': effect}
          : {'batch_id': 'b1', 'effect': effect};
    };

void main() {
  testWidgets(
      'retire shows the effect first, takes a reason, then offers '
      'Undo for ten seconds', (tester) async {
    final api = await pumpAnnual(
        tester,
        _server().routes({
          'POST /annual/key-results/kr1/retire': _retire(1, 2),
          'POST /annual/undo': {'restored': 1},
        }));
    await menu(tester, 'kr-menu-kr1', 'Retire');
    expect(find.byKey(const Key('retire-dialog')), findsOneWidget);
    expect(
        (api.where('POST /annual/key-results/kr1/retire').single.data!
            as Map)['dry_run'],
        isTrue);
    final effect =
        tester.widget<Text>(find.byKey(const Key('retire-effect'))).data!;
    expect(effect, contains('2 theme links end'));
    expect(effect, contains('history stays'));
    await typeKey(tester, 'retire-reason', 'Too ambitious');
    await tapKey(tester, 'retire-confirm');
    final real =
        api.where('POST /annual/key-results/kr1/retire').last.data! as Map;
    expect(real, {'reason': 'Too ambitious', 'dry_run': false});
    final bar = tester.widget<SnackBar>(find.byKey(const Key('undo-snackbar')));
    expect(bar.duration, const Duration(seconds: 10));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(api.where('POST /annual/undo').single.data, {'batch_id': 'b1'});
  });

  testWidgets('cancel writes nothing', (tester) async {
    final api = await pumpAnnual(
        tester,
        _server()
            .routes({'POST /annual/key-results/kr1/retire': _retire(1, 2)}));
    await menu(tester, 'kr-menu-kr1', 'Retire');
    await tapKey(tester, 'retire-cancel');
    expect(api.where('POST /annual/key-results/kr1/retire'), hasLength(1));
  });

  testWidgets('retiring a goal says how many key results retire',
      (tester) async {
    final api = await pumpAnnual(tester,
        _server().routes({'POST /annual/goals/g1/retire': _retire(2, 3)}));
    await menu(tester, 'goal-menu-g1', 'Retire goal');
    expect(find.textContaining('2 key results retire with this goal'),
        findsOneWidget);
    await tapKey(tester, 'retire-confirm');
    expect(api.where('POST /annual/goals/g1/retire'), hasLength(2));
    expect(find.byKey(const Key('undo-snackbar')), findsOneWidget);
  });

  testWidgets('removing a link shows its effect and can be undone',
      (tester) async {
    final api = await pumpAnnual(
        tester,
        _server().routes({
          'GET /annual/themes': themesJson(themes: [
            themeJson('p1', 'Open source'),
            themeJson('p2', 'Talks')
          ]),
          'PUT /annual/key-results/kr1/themes': (RequestOptions o) {
            final body = o.data as Map;
            return body['dry_run'] == true
                ? {
                    'effect': {
                      'added': <Object?>[],
                      'ended': [
                        {'project_id': 'p2', 'name': 'Talks'}
                      ],
                      'flags_removed': <Object?>[],
                      'flags_added': <Object?>[],
                    }
                  }
                : {
                    'batch_id': 'b5',
                    'key_result': keyResultJson('kr1', 'Stars')
                  };
          },
          'POST /annual/undo': {'restored': 1},
        }));
    await menu(tester, 'kr-menu-kr1', 'Link themes');
    await tapKey(tester, 'theme-option-p2');
    await tapKey(tester, 'themes-done');
    expect(find.byKey(const Key('link-effect-dialog')), findsOneWidget);
    expect(find.text('Ends: Talks'), findsOneWidget);
    await tapKey(tester, 'link-confirm');
    expect(api.where('PUT /annual/key-results/kr1/themes'), hasLength(2));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(api.where('POST /annual/undo').single.data, {'batch_id': 'b5'});
  });

  testWidgets(
      'the history lists every change in time order and keeps Undo '
      'for a batch', (tester) async {
    final api = await pumpAnnual(
        tester,
        _server().routes({
          'GET /annual/2030/history': historyJson([
            changeJson('c1', 'key_result_edited',
                batch: 'b1',
                keyResultId: 'kr1',
                field: 'target',
                oldValue: '400',
                newValue: '500',
                at: '2030-02-01T10:00:00Z'),
            changeJson('c2', 'key_result_retired',
                batch: 'b2',
                keyResultId: 'kr2',
                reason: 'Too ambitious',
                at: '2030-03-01T10:00:00Z'),
            changeJson('c3', 'link_ended',
                batch: 'b2', keyResultId: 'kr2', at: '2030-03-01T10:00:00Z'),
            changeJson('c4', 'link_added',
                batch: 'b3',
                keyResultId: 'kr1',
                undone: true,
                at: '2030-03-02T10:00:00Z'),
          ]),
          'POST /annual/undo': {'restored': 1},
        }));
    await tapKey(tester, 'open-history');
    expect(find.byKey(const Key('plan-history')), findsOneWidget);
    final ys = [
      for (final id in ['c1', 'c2', 'c3', 'c4'])
        tester.getTopLeft(find.byKey(Key('change-$id'))).dy
    ];
    expect([...ys]..sort(), ys);
    expect(find.textContaining('400'), findsOneWidget);
    expect(find.textContaining('500'), findsWidgets);
    expect(find.textContaining('Too ambitious'), findsOneWidget);
    expect(find.byKey(const Key('undo-batch-b2')), findsOneWidget);
    expect(find.byKey(const Key('undo-batch-b3')), findsNothing);
    await tapKey(tester, 'undo-batch-b2');
    expect(api.where('POST /annual/undo').single.data, {'batch_id': 'b2'});
  });
}
