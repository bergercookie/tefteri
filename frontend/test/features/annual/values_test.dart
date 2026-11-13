import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'annual_fake.dart';

AnnualServer _server() => AnnualServer(goals: [
      annualGoalJson('g1', 'Get fit', keyResults: [
        keyResultJson('kr1', 'Push-ups',
            start: 0,
            target: 50,
            current: 60,
            links: [linkJson('p1', 'Health')]),
        keyResultJson('kr2', 'Weight',
            start: 80,
            target: 70,
            current: 75,
            links: [linkJson('p1', 'Health')]),
        keyResultJson('kr3', 'Stars',
            start: 100,
            target: 200,
            source: 'automatic',
            links: [linkJson('p2', 'Open source')]),
      ]),
    ]);

void main() {
  testWidgets('the value dialog stores a value with a date', (tester) async {
    final api = await pumpAnnual(
        tester,
        _server().routes({
          'POST /annual/key-results/kr1/values': {
            'id': 'v1',
            'value': 30,
            'at': '2030-03-04T10:00:00Z',
            'on_date': '2030-03-04',
            'source': 'manual',
            'key_result':
                keyResultJson('kr1', 'Push-ups', current: 30, target: 50),
          },
        }));
    await tapKey(tester, 'kr-value-btn-kr1');
    final date = tester.widget<TextField>(find.byKey(const Key('value-date')));
    expect(date.controller!.text, '2030-03-10');
    await typeKey(tester, 'value-field', '30');
    await typeKey(tester, 'value-date', '2030-03-04');
    await tapKey(tester, 'value-save');
    expect(api.where('POST /annual/key-results/kr1/values').single.data,
        {'value': 30, 'date': '2030-03-04'});
    expect(find.byKey(const Key('value-dialog')), findsNothing);
  });

  testWidgets('the bar is capped at 100% while the number shows 120%',
      (tester) async {
    await pumpAnnual(tester, _server().routes());
    final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('kr-progress-kr1')));
    expect(bar.value, 1.0);
    expect(tester.widget<Text>(find.byKey(const Key('kr-percent-kr1'))).data,
        '120%');
  });

  testWidgets('a lower target shows progress in the right direction',
      (tester) async {
    await pumpAnnual(tester, _server().routes());
    final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('kr-progress-kr2')));
    expect(bar.value, closeTo(0.5, 1e-9));
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('an automatic key result is marked and takes a manual value',
      (tester) async {
    final api = await pumpAnnual(
        tester,
        _server().routes({
          'POST /annual/key-results/kr3/values': {'id': 'v2', 'value': 150},
        }));
    expect(find.byKey(const Key('kr-auto-kr3')), findsOneWidget);
    expect(find.byKey(const Key('kr-auto-kr1')), findsNothing);
    await tapKey(tester, 'kr-value-btn-kr3');
    expect(find.byKey(const Key('value-auto-note')), findsOneWidget);
    await typeKey(tester, 'value-field', '150');
    await tapKey(tester, 'value-save');
    expect(api.where('POST /annual/key-results/kr3/values'), hasLength(1));
  });

  testWidgets('a failed save shows the server message', (tester) async {
    await pumpAnnual(
        tester,
        _server().routes({
          'POST /annual/key-results/kr1/values': const ApiFailure(
              422, 'The date cannot be in the future.', 'future_date'),
        }));
    await tapKey(tester, 'kr-value-btn-kr1');
    await typeKey(tester, 'value-field', '12');
    await tapKey(tester, 'value-save');
    expect(find.byKey(const Key('value-dialog')), findsOneWidget);
    expect(find.text('The date cannot be in the future.'), findsOneWidget);
  });

  testWidgets('a value that is not a number is refused on the field',
      (tester) async {
    final api = await pumpAnnual(tester, _server().routes());
    await tapKey(tester, 'kr-value-btn-kr1');
    await typeKey(tester, 'value-field', 'ten');
    await tapKey(tester, 'value-save');
    expect(find.text('The value must be a number.'), findsOneWidget);
    expect(api.where('POST /annual/key-results/kr1/values'), isEmpty);
  });
}
